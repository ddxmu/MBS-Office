const form = document.getElementById('search-form');
const input = document.getElementById('query');
const output = document.getElementById('output');
let controller;
function message(text) { output.replaceChildren(); const p = document.createElement('p'); p.className = 'status'; p.textContent = text; output.append(p); }
async function search(query) {
  if (controller) controller.abort();
  controller = new AbortController();
  message('正在搜索，请稍候…');
  try {
    const response = await fetch('/api/search?q=' + encodeURIComponent(query), {signal: controller.signal});
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || '搜索失败，请稍后重试');
    output.replaceChildren();
    const count = document.createElement('p'); count.className = 'result-count'; count.textContent = `“${query}”的搜索结果 · ${data.results.length} 条`; output.append(count);
    if (!data.results.length) return message('没有找到相关结果，请尝试其他关键词。');
    for (const item of data.results) {
      const card = document.createElement('article'); card.className = 'result';
      const link = document.createElement('a'); link.href = item.url; link.rel = 'noopener noreferrer'; link.textContent = item.title || item.url;
      const url = document.createElement('div'); url.className = 'url'; url.textContent = item.url;
      const description = document.createElement('p'); description.textContent = item.description;
      card.append(link, url, description); output.append(card);
    }
  } catch (error) { if (error.name !== 'AbortError') message(error.message || '网络连接失败，请稍后重试'); }
}
form.addEventListener('submit', (event) => { event.preventDefault(); const query = input.value.trim(); if (!query) return; history.replaceState(null, '', '/sousuo/?q=' + encodeURIComponent(query)); search(query); });
const initial = new URLSearchParams(location.search).get('q');
if (initial) { input.value = initial.slice(0, 200); search(input.value); }
