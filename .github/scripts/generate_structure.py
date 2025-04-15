import os
import yaml
from pathlib import Path
from datetime import datetime
from collections import defaultdict

DOCS_DIR = Path("docs")
MKDOCS_YML = Path("mkdocs.yml")
CATEGORY_TEMPLATE = (
    "---\ntitle: \"{title}\"\nhide:\n  - toc\n---\n\n{{% include \"category.md\" %}}\n"
)

def parse_date_from_md(md_file):
    with open(md_file, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
        if not lines or lines[0].strip() != "---":
            return None
        meta_end = lines[1:].index("---") + 1
        meta = yaml.safe_load("\n".join(lines[1:meta_end]))
        return meta.get("date", None)

def ensure_index_file(year, month):
    folder = DOCS_DIR / year / month
    folder.mkdir(parents=True, exist_ok=True)
    index_file = folder / "index.md"
    if not index_file.exists():
        with open(index_file, "w", encoding="utf-8") as f:
            title = f"{year}년 {int(month)}월"
            f.write(CATEGORY_TEMPLATE.format(title=title))

def regenerate_nav(structure):
    with open(MKDOCS_YML, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    data["nav"] = [{"홈": "index.md"}, {"문서 분류": []}]

    for year in sorted(structure.keys(), reverse=True):
        months = []
        for month in sorted(structure[year], reverse=True):
            months.append({f"{int(month)}월": f"{year}/{month}/index.md"})
        data["nav"][1]["문서 분류"].append({year: months})

    with open(MKDOCS_YML, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True)

def main():
    structure = defaultdict(set)
    for md_file in DOCS_DIR.glob("*.md"):
        date_str = parse_date_from_md(md_file)
        if not date_str:
            continue
        # 유연하게 datetime 처리
        if isinstance(date_str, datetime):
            dt = date_str
        elif hasattr(date_str, "year") and hasattr(date_str, "month"):
            dt = datetime(date_str.year, date_str.month, date_str.day)
        else:
            dt = datetime.strptime(str(date_str), "%Y-%m-%d")
        year, month = str(dt.year), f"{dt.month:02d}"
        structure[year].add(month)
        ensure_index_file(year, month)

    regenerate_nav(structure)

if __name__ == "__main__":
    main()
