#!/usr/bin/env python3
import html
import json
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CACHE = {}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path)
        if path.path != '/api/search':
            return self.send_json(404, {'error': '页面不存在'})
        query = urllib.parse.parse_qs(path.query).get('q', [''])[0].strip()
        if not query or len(query) > 200:
            return self.send_json(400, {'error': '请输入 1 至 200 个字符的搜索内容'})
        try:
            now = time.monotonic()
            cached = CACHE.get(query)
            if cached and now - cached[0] < 60:
                return self.send_json(200, cached[1])
            url = 'https://www.bing.com/search?' + urllib.parse.urlencode({'format': 'rss', 'q': query})
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (compatible; MbsOfficeSearch/1.0)'})
            with urllib.request.urlopen(req, timeout=8) as response:
                data = response.read(512 * 1024)
            root = ET.fromstring(data)
            results = []
            for item in root.findall('./channel/item')[:20]:
                link = item.findtext('link', '').strip()
                parsed = urllib.parse.urlsplit(link)
                if parsed.scheme not in ('http', 'https') or not parsed.netloc:
                    continue
                results.append({'title': html.unescape(item.findtext('title', '')),
                                'url': link, 'description': html.unescape(item.findtext('description', ''))})
            body = {'query': query, 'results': results, 'source': 'Bing'}
            if len(CACHE) >= 256:
                CACHE.clear()
            CACHE[query] = (now, body)
            self.send_json(200, body)
        except Exception:
            self.send_json(502, {'error': '搜索服务暂时不可用，请稍后重试'})

    def send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18768), Handler).serve_forever()
