#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
"${PYTHON:-python3}" -m PyInstaller --noconfirm --clean --onedir --name MbsPdfEngine \
  --distpath build/pdf-engine-dist --workpath build/pdf-engine-work --specpath build \
  --collect-all pymupdf --collect-all fitz --collect-submodules pkg_resources._vendor \
  tests/MbsPdfConvertTest.py
