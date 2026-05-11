import sys
from pathlib import Path
from pypdf import PdfReader

src = Path(r"D:\matlab\ice_developer_docs")
out = Path(r"D:\matlab\extracted_text")
out.mkdir(exist_ok=True)

for pdf in src.rglob("*.pdf"):
    rel = pdf.relative_to(src).with_suffix(".txt")
    dst = out / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    reader = PdfReader(str(pdf))
    pieces = []
    for i, page in enumerate(reader.pages, 1):
        try:
            txt = page.extract_text() or ""
        except Exception as e:
            txt = f"[extract error: {e}]"
        pieces.append(f"\n\n===== PAGE {i} =====\n{txt}")
    dst.write_text("".join(pieces), encoding="utf-8")
    print(f"{pdf.name} -> {dst} ({len(reader.pages)} pages)")
