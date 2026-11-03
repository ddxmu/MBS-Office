import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import fitz
from docx import Document
from openpyxl import load_workbook

SCRIPT = Path(__file__).with_name('MbsPdfConvertTest.py')


class PdfConvertPrototypeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='mbs-pdf-test-')
        self.directory = Path(self.tmp.name)
        self.source = self.directory / 'source.pdf'
        pdf = fitz.open()
        pdf.new_page().insert_text((60, 100), '=1+1')
        pdf.new_page().insert_text((60, 100), 'Second page')
        pdf.save(self.source)
        pdf.close()

    def tearDown(self):
        self.tmp.cleanup()

    def run_convert(self, mode, first, last):
        return subprocess.run([sys.executable, str(SCRIPT), mode, str(self.source),
                               str(self.directory), str(first), str(last)],
                              text=True, capture_output=True)

    def test_excel_preserves_existing_file_and_literal_text(self):
        existing = self.directory / 'source.xlsx'
        existing.write_bytes(b'keep me')
        result = self.run_convert('excel', 1, 1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(existing.read_bytes(), b'keep me')
        output = self.directory / 'source (1).xlsx'
        sheet = load_workbook(output).active
        self.assertEqual(sheet['A1'].value, '=1+1')
        self.assertEqual(sheet['A1'].data_type, 's')

    def test_invalid_range_leaves_no_output(self):
        result = self.run_convert('excel', 0, 3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.directory.glob('*.xlsx')), [])

    def test_word_page_range(self):
        result = self.run_convert('word', 2, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        doc = Document(self.directory / 'source.docx')
        text = ''.join(doc.element.body.xpath('.//w:t/text()'))
        self.assertIn('Second page', text)
        self.assertNotIn('=1+1', text)

    def test_image_export_preserves_existing_and_page_range(self):
        existing = self.directory / 'source-2.png'
        existing.write_bytes(b'keep me')
        result = self.run_convert('image', 2, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(existing.read_bytes(), b'keep me')
        self.assertTrue((self.directory / 'source-2 (1).png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'))
        self.assertFalse((self.directory / 'source-1.png').exists())


if __name__ == '__main__':
    unittest.main()
