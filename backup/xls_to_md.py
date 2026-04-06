#!/usr/bin/env python3
"""
PISA CheckItems XLS → AI-Friendly Markdown Converter
------------------------------------------------------
입력: checkitems_list_KO_*.xls  (SpreadsheetML / HTML-XLS 포맷)
출력: PISA_CheckItems_<날짜>.md

변환 전략:
  - YAML frontmatter 로 메타데이터 구조화 (Code, Area, 중요도 등)
  - 점검방법(명령어)은 shell code block 으로 감지·변환
  - 점검기준의 *, - 리스트를 Markdown 리스트로 정규화
  - 참고(Reference)의 명령어 라인을 code block 으로 분리
  - 섹션 구분자(---) 와 앵커(# ID)로 AI 검색 가독성 향상
"""

import re
import sys
import argparse
from pathlib import Path
from datetime import datetime
from bs4 import BeautifulSoup


# ─────────────────────────────────────────────
# 컬럼 인덱스 매핑 (Row 1 헤더 기준)
# ─────────────────────────────────────────────
COL = {
    "area":           0,
    "pisa_category":  1,
    "lookin_service": 2,
    "lookin_killer":  3,
    "cloud":          4,
    "code":           5,
    "lang":           6,
    "category":       7,
    "subcategory":    8,
    "subject":        9,
    "check_command":  10,
    "check_criteria": 11,
    "check_result":   12,
    "vuln_problem":   13,
    "improvement":    14,
    "reference":      15,
    "score":          16,
    "importance":     17,
    "improve_timing": 18,
    "check_method":   19,   # 자동점검 / 수동점검
    "self_developed": 20,
    "failure_case":   21,
    "interconnect":   22,
    "work_char":      23,
    "killer_content": 24,
}

# 중요도 → 영문 매핑 (AI 이해용)
IMPORTANCE_MAP = {"하": "low", "중": "medium", "상": "high"}
TIMING_MAP     = {"단기": "short-term", "중기": "mid-term", "장기": "long-term"}


# ─────────────────────────────────────────────
# 헬퍼 함수
# ─────────────────────────────────────────────

def get_cell(cells: list, idx: int) -> str:
    """BeautifulSoup cell 리스트에서 텍스트 추출 (줄바꿈 보존)."""
    if idx >= len(cells):
        return ""
    return cells[idx].get_text(separator="\n", strip=True)


def is_shell_line(line: str) -> bool:
    """shell 명령어 라인 여부 판별."""
    stripped = line.strip()
    if not stripped:
        return False
    shell_patterns = [
        r"^[#$]\s+\S",          # # cmd  또는  $ cmd
        r"^kubectl\b",
        r"^systemctl\b",
        r"^cat\s+/",
        r"^vi\s+/",
        r"^ls\b",
        r"^grep\b",
        r"^awk\b",
        r"^sed\b",
        r"^echo\b",
        r"^export\b",
        r"^\[.*server\]",        # [gateway server] 류
    ]
    return any(re.match(p, stripped) for p in shell_patterns)


def format_command_block(raw: str) -> str:
    """점검방법(명령어 문자열)을 shell code block으로 변환."""
    lines = [l for l in raw.splitlines()]
    # 서버 지시어 ([gateway server] 등) 와 명령어를 모두 코드블록으로 묶음
    return "```shell\n" + "\n".join(lines) + "\n```"


def normalize_bullets(text: str) -> str:
    """
    `*`로 시작하는 항목을 헤딩(###)으로, `-`로 시작하는 항목을 bullet(-)으로 정규화.
    숫자 리스트(1. 2. ...)는 그대로 유지.
    """
    lines = text.splitlines()
    output = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("* "):
            output.append(f"### {stripped[2:]}")
        elif stripped.startswith("- "):
            output.append(f"- {stripped[2:]}")
        elif re.match(r"^\d+\.\s", stripped):
            output.append(stripped)
        else:
            output.append(stripped)
    return "\n".join(output).strip()


def format_reference(raw: str) -> str:
    """
    참고 필드: * 섹션 제목 + 명령어/일반 텍스트 혼재 처리.
    명령어 라인은 코드블록으로, 나머지는 bullet 으로 변환.
    """
    lines = raw.splitlines()
    output = []
    code_buffer = []

    def flush_code():
        if code_buffer:
            output.append("```shell")
            output.extend(code_buffer)
            output.append("```")
            code_buffer.clear()

    for line in lines:
        stripped = line.strip()
        if not stripped:
            flush_code()
            output.append("")
            continue

        if stripped.startswith("* "):
            flush_code()
            output.append(f"### {stripped[2:]}")
        elif stripped.startswith("- "):
            flush_code()
            output.append(f"- {stripped[2:]}")
        elif is_shell_line(stripped):
            code_buffer.append(stripped)
        elif re.match(r"^https?://", stripped):
            flush_code()
            output.append(f"- <{stripped}>")
        else:
            flush_code()
            output.append(stripped)

    flush_code()
    return "\n".join(output).strip()


def format_criteria(raw: str) -> str:
    """점검기준: 정상/취약 라인 강조 + 하위 리스트 정규화."""
    lines = raw.splitlines()
    output = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("정상:"):
            output.append(f"✅ **{stripped}**")
        elif stripped.startswith("취약:"):
            output.append(f"❌ **{stripped}**")
        elif stripped.startswith("* "):
            output.append(f"### {stripped[2:]}")
        elif stripped.startswith("- "):
            output.append(f"- {stripped[2:]}")
        elif re.match(r"^\d+\.\s", stripped):
            output.append(stripped)
        else:
            output.append(stripped)
    return "\n".join(output).strip()


def yn_bool(val: str) -> str:
    """Y/N 값을 명시적 문자열로 변환."""
    v = val.strip().upper()
    if v == "Y":
        return "true"
    if v == "N":
        return "false"
    return val.strip() if val.strip() else "N/A"


def make_anchor(code: str) -> str:
    """마크다운 앵커용 ID 생성."""
    return code.replace(".", "-").lower()


# ─────────────────────────────────────────────
# 핵심 변환 함수
# ─────────────────────────────────────────────

def row_to_markdown(cells: list, index: int) -> str:
    """데이터 행 하나를 AI-friendly 마크다운 블록으로 변환."""

    def c(key: str) -> str:
        return get_cell(cells, COL[key])

    code            = c("code")
    area            = c("area")
    pisa_cat        = c("pisa_category")
    lookin_service  = c("lookin_service")
    cloud           = c("cloud")
    lang            = c("lang")
    category        = c("category")
    subcategory     = c("subcategory")
    subject         = c("subject")
    check_command   = c("check_command")
    check_criteria  = c("check_criteria")
    check_result    = c("check_result")
    vuln_problem    = c("vuln_problem")
    improvement     = c("improvement")
    reference       = c("reference")
    score           = c("score")
    importance_ko   = c("importance")
    timing_ko       = c("improve_timing")
    check_method    = c("check_method")
    self_developed  = c("self_developed")
    failure_case    = c("failure_case")
    interconnect    = c("interconnect")
    work_char       = c("work_char")
    killer_content  = c("killer_content")

    anchor = make_anchor(code)
    importance_en = IMPORTANCE_MAP.get(importance_ko, importance_ko)
    timing_en     = TIMING_MAP.get(timing_ko, timing_ko)

    lines = []

    # ── 제목 (H2 = 항목 제목, 코드로 식별 가능) ──────────────────────
    lines.append(f'<a id="{anchor}"></a>')
    lines.append(f"## [{code}] {subject}")
    lines.append("")

    # ── YAML frontmatter 스타일 메타데이터 블록 ──────────────────────
    lines.append("```yaml")
    lines.append(f"code:            {code}")
    lines.append(f"area:            {area}")
    lines.append(f"pisa_category:   {pisa_cat}")
    lines.append(f"category:        {category}")
    lines.append(f"subcategory:     {subcategory}")
    lines.append(f"lang:            {lang}")
    lines.append(f"score:           {score}")
    lines.append(f"importance:      {importance_ko} ({importance_en})")
    lines.append(f"improve_timing:  {timing_ko} ({timing_en})")
    lines.append(f"check_method:    {check_method}")
    lines.append(f"lookin_service:  {yn_bool(lookin_service)}")
    lines.append(f"cloud:           {yn_bool(cloud)}")
    lines.append(f"self_developed:  {self_developed}")
    lines.append(f"failure_case:    {yn_bool(failure_case)}")
    lines.append(f"interconnect:    {yn_bool(interconnect)}")
    lines.append(f"work_char:       {yn_bool(work_char)}")
    lines.append("```")
    lines.append("")

    # ── 점검 방법 (명령어) ────────────────────────────────────────────
    lines.append("### 📋 점검 방법 (Check Command)")
    lines.append("")
    if check_command.strip():
        lines.append(format_command_block(check_command))
    else:
        lines.append("_(명령어 없음)_")
    lines.append("")

    # ── 점검 기준 ─────────────────────────────────────────────────────
    lines.append("### ✅ 점검 기준 (Check Criteria)")
    lines.append("")
    if check_criteria.strip():
        lines.append(format_criteria(check_criteria))
    lines.append("")

    # ── 점검 결과 (취약 상태 설명) ────────────────────────────────────
    lines.append("### 🔍 점검 결과 (Vulnerable State Description)")
    lines.append("")
    lines.append(f"> {check_result.strip()}" if check_result.strip() else "> _(없음)_")
    lines.append("")

    # ── 취약시 문제점 ─────────────────────────────────────────────────
    lines.append("### ⚠️ 취약시 문제점 (Risk)")
    lines.append("")
    lines.append(vuln_problem.strip() if vuln_problem.strip() else "_(없음)_")
    lines.append("")

    # ── 개선 방안 ─────────────────────────────────────────────────────
    lines.append("### 🔧 개선 방안 (Remediation)")
    lines.append("")
    lines.append(improvement.strip() if improvement.strip() else "_(없음)_")
    lines.append("")

    # ── 참고 ──────────────────────────────────────────────────────────
    if reference.strip():
        lines.append("### 📎 참고 (Reference)")
        lines.append("")
        lines.append(format_reference(reference))
        lines.append("")

    # ── Killer Contents ───────────────────────────────────────────────
    if killer_content.strip():
        lines.append("### 💡 Killer Contents")
        lines.append("")
        lines.append(f"> {killer_content.strip()}")
        lines.append("")

    return "\n".join(lines)


# ─────────────────────────────────────────────
# 파일 파싱 & 출력
# ─────────────────────────────────────────────

def parse_xls(path: Path) -> list[list]:
    """SpreadsheetML HTML-XLS 파일을 행(셀 리스트) 목록으로 파싱."""
    with open(path, "r", encoding="utf-8") as f:
        soup = BeautifulSoup(f.read(), "html.parser")
    table = soup.find("table")
    if not table:
        raise ValueError("테이블을 찾을 수 없습니다.")
    rows = table.find_all("tr")
    return rows   # BeautifulSoup Tag 리스트


def convert(input_path: Path, output_path: Path) -> None:
    rows = parse_xls(input_path)

    # Row 0 = 전체 제목, Row 1 = 헤더, Row 2+ = 데이터
    data_rows = rows[2:]
    total = len(data_rows)

    now_str = datetime.now().strftime("%Y-%m-%d")

    # ── 문서 헤더 ─────────────────────────────────────────────────────
    doc_lines = []
    doc_lines.append(f"# PISA CheckItems")
    doc_lines.append(f"")
    doc_lines.append(f"> **생성일**: {now_str}  ")
    doc_lines.append(f"> **원본**: `{input_path.name}`  ")
    doc_lines.append(f"> **총 항목**: {total}개  ")
    doc_lines.append(f"> **언어**: 한국어 (KO)")
    doc_lines.append(f"")
    doc_lines.append("---")
    doc_lines.append("")

    # ── 목차 ──────────────────────────────────────────────────────────
    doc_lines.append("## 📑 목차 (Table of Contents)")
    doc_lines.append("")
    for i, row_tag in enumerate(data_rows, 1):
        cells = row_tag.find_all(["td", "th"])
        code    = get_cell(cells, COL["code"])
        subject = get_cell(cells, COL["subject"])
        anchor  = make_anchor(code)
        doc_lines.append(f"{i}. [{code} — {subject}](#{anchor})")
    doc_lines.append("")
    doc_lines.append("---")
    doc_lines.append("")

    # ── 각 항목 변환 ──────────────────────────────────────────────────
    for i, row_tag in enumerate(data_rows, 1):
        cells = row_tag.find_all(["td", "th"])
        block = row_to_markdown(cells, i)
        doc_lines.append(block)
        doc_lines.append("")
        doc_lines.append("---")
        doc_lines.append("")

    output_path.write_text("\n".join(doc_lines), encoding="utf-8")
    print(f"✅ 변환 완료: {output_path}  ({total}개 항목)")


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="PISA CheckItems XLS → AI-Friendly Markdown Converter"
    )
    parser.add_argument(
        "input",
        type=Path,
        help="입력 XLS 파일 경로 (SpreadsheetML HTML 포맷)"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=None,
        help="출력 마크다운 파일 경로 (기본값: 입력파일명_변환.md)"
    )
    args = parser.parse_args()

    input_path: Path = args.input
    if not input_path.exists():
        print(f"❌ 파일을 찾을 수 없습니다: {input_path}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        output_path = args.output
    else:
        stem = input_path.stem
        # 날짜 접미사가 있으면 유지, 없으면 오늘 날짜 추가
        date_str = datetime.now().strftime("%Y%m%d")
        output_path = input_path.parent / f"{stem}_converted.md"

    convert(input_path, output_path)


if __name__ == "__main__":
    main()
