#!/usr/bin/env python3
"""PDF conversion worker bundled with Mbs Office."""
import math
import os
from pathlib import Path
import sys
import tempfile
import unicodedata

import fitz
import pdfplumber
from docx import Document
from docx.oxml.ns import qn
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Side
from openpyxl.utils import get_column_letter
from pdf2docx import Converter


def repair_word_tables(path):
    doc = Document(path)
    for table in doc.element.body.xpath('.//w:tbl'):
        grid = table.xpath('./w:tblGrid/w:gridCol')
        cells = table.xpath('./w:tr[1]/w:tc')
        if not grid or len(grid) != len(cells):
            continue
        widths = []
        for cell in cells:
            width = cell.xpath('./w:tcPr/w:tcW')
            if not width or cell.xpath('./w:tcPr/w:gridSpan') or width[0].get(qn('w:type')) != 'dxa':
                break
            widths.append(width[0].get(qn('w:w')))
        if len(widths) == len(grid) and all(w and w.isdigit() and int(w) > 0 for w in widths):
            for column, width in zip(grid, widths):
                column.set(qn('w:w'), width)
    for height in doc.element.body.xpath('.//w:trHeight'):
        if height.get(qn('w:hRule')) == 'exact':
            height.set(qn('w:hRule'), 'atLeast')
    doc.save(path)


def convert_excel(source, output, first, last):
    workbook = Workbook()
    workbook.remove(workbook.active)
    side = Side(style='thin', color='000000')
    with pdfplumber.open(source) as document, fitz.open(source) as text_document:
        for page_index in range(first - 1, last):
            page = document.pages[page_index]
            sheet = workbook.create_sheet(f'第{page_index + 1}页')
            sheet.page_setup.orientation = 'landscape'
            sheet.page_setup.paperSize = sheet.PAPERSIZE_A4
            sheet.sheet_properties.pageSetUpPr.fitToPage = True
            sheet.page_setup.fitToWidth = 1
            sheet.page_setup.fitToHeight = 0
            tables = page.find_tables()
            if not tables:
                cell = sheet.cell(1, 1, page.extract_text() or '该页没有可识别的表格或文字')
                cell.data_type = 's'
                continue
            row_offset = 1
            top = min(t.bbox[1] for t in tables)
            header = page.crop((0, 0, page.width, top)).extract_text() if top > 1 else ''
            if header:
                cell = sheet.cell(row_offset, 1, header)
                cell.data_type = 's'
                cell.alignment = Alignment(wrap_text=True, vertical='top')
                if len(tables[0].columns) > 1:
                    sheet.merge_cells(start_row=row_offset, start_column=1, end_row=row_offset, end_column=len(tables[0].columns))
                sheet.row_dimensions[row_offset].height = max(20, 16 * len(header.splitlines()))
                row_offset += 1
            for table in tables:
                rows = table.extract()
                widths = [max(12, min(80, (c.bbox[2] - c.bbox[0]) / 5)) for c in table.columns]
                for column, width in enumerate(widths, 1):
                    sheet.column_dimensions[get_column_letter(column)].width = width
                row_ranges = []
                for index, row in enumerate(rows):
                    lines = 1
                    for column, value in enumerate(row, 1):
                        box = table.rows[index].cells[column - 1] if column <= len(table.rows[index].cells) else None
                        if box:
                            positioned_text = text_document[page_index].get_textbox(fitz.Rect(box)).strip()
                            if positioned_text:
                                value = positioned_text
                        if value and len(value) > 32767:
                            raise ValueError('a table cell exceeds Excel text limits')
                        cell = sheet.cell(row_offset, column, value or '')
                        cell.data_type = 's'
                        cell.alignment = Alignment(wrap_text=True, vertical='top')
                        cell.border = Border(left=side, right=side, top=side, bottom=side)
                        if value:
                            width = widths[column - 1] if column <= len(widths) else 30
                            count = sum(max(1, math.ceil(sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in line) / width)) for line in value.split('\n'))
                            lines = max(lines, count)
                    heights = [box[3] - box[1] for box in table.rows[index].cells if box]
                    required = max(min(heights, default=15), lines * 14)
                    segments = max(1, math.ceil(required / 409.5))
                    row_ranges.append((row_offset, row_offset + segments - 1))
                    for offset in range(segments):
                        sheet.row_dimensions[row_offset + offset].height = required / segments
                    row_offset += segments
                for column in range(len(widths)):
                    row = 0
                    while row < len(table.rows):
                        if column >= len(table.rows[row].cells) or not table.rows[row].cells[column]:
                            row += 1
                            continue
                        end = row + 1
                        while end < len(table.rows) and column < len(table.rows[end].cells) and table.rows[end].cells[column] is None:
                            end += 1
                        start_row, end_row = row_ranges[row][0], row_ranges[end - 1][1]
                        if end_row > start_row:
                            sheet.merge_cells(start_row=start_row, start_column=column + 1, end_row=end_row, end_column=column + 1)
                        row = end
                row_offset += 1
            bottom = max(t.bbox[3] for t in tables)
            footer = page.crop((0, bottom, page.width, page.height)).extract_text() if bottom < page.height - 1 else ''
            if footer:
                cell = sheet.cell(row_offset, 1, footer)
                cell.data_type = 's'
                cell.alignment = Alignment(wrap_text=True, vertical='top')
    workbook.save(output)


def main():
    if len(sys.argv) != 6 or sys.argv[1] not in ('word', 'excel', 'image'):
        raise ValueError('invalid arguments')
    mode, source, directory = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    first, last = int(sys.argv[4]), int(sys.argv[5])
    with fitz.open(source) as pdf:
        if pdf.needs_pass or first < 1 or last < first or last > len(pdf):
            raise ValueError('invalid page range or locked PDF')
    if not directory.is_dir():
        raise ValueError('output directory is unavailable')
    if mode == 'image':
        with fitz.open(source) as pdf, tempfile.TemporaryDirectory(prefix='.mbs-pdf-', dir=directory) as work:
            for page_index in range(first - 1, last):
                staged = Path(work) / f'{page_index + 1}.png'
                pdf[page_index].get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False).save(str(staged))
                for number in range(10000):
                    suffix = '' if not number else f' ({number})'
                    target = directory / f'{source.stem}-{page_index + 1}{suffix}.png'
                    try:
                        os.link(staged, target)
                        break
                    except FileExistsError:
                        continue
                else:
                    raise FileExistsError('too many existing outputs')
        print(directory, flush=True)
        return
    extension = '.docx' if mode == 'word' else '.xlsx'
    with tempfile.TemporaryDirectory(prefix='.mbs-pdf-', dir=directory) as work:
        staged = Path(work) / ('output' + extension)
        if mode == 'word':
            converter = Converter(str(source))
            try:
                converter.convert(str(staged), start=first - 1, end=last)
            finally:
                converter.close()
            repair_word_tables(staged)
        else:
            convert_excel(source, staged, first, last)
        for number in range(10000):
            suffix = '' if not number else f' ({number})'
            target = directory / f'{source.stem}{suffix}{extension}'
            try:
                os.link(staged, target)
                print(target, flush=True)
                return
            except FileExistsError:
                continue
        raise FileExistsError('too many existing outputs')


if __name__ == '__main__':
    main()
