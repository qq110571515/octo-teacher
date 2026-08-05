#!/usr/bin/env python3
"""Build reproducible official content seed data without bundling it in the app."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def read_xlsx_rows(path: Path) -> dict[str, list[dict[str, str]]]:
    ns = {"m": MAIN_NS, "r": REL_NS}
    with ZipFile(path) as archive:
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        targets = {item.attrib["Id"]: item.attrib["Target"] for item in relationships}
        shared_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        shared = [
            "".join(node.text or "" for node in item.findall(".//m:t", ns))
            for item in shared_root.findall("m:si", ns)
        ]

        result: dict[str, list[dict[str, str]]] = {}
        for sheet in workbook.findall("m:sheets/m:sheet", ns):
            name = sheet.attrib["name"]
            target = targets[sheet.attrib[f"{{{REL_NS}}}id"]].lstrip("/")
            sheet_path = target if target.startswith("xl/") else f"xl/{target}"
            root = ET.fromstring(archive.read(sheet_path))
            rows: list[list[str]] = []
            for row in root.findall(".//m:sheetData/m:row", ns):
                values: dict[int, str] = {}
                for cell in row.findall("m:c", ns):
                    column = re.match(r"[A-Z]+", cell.attrib.get("r", "A"))
                    if not column:
                        continue
                    index = 0
                    for character in column.group(0):
                        index = index * 26 + ord(character) - 64
                    value_node = cell.find("m:v", ns)
                    inline = cell.find("m:is", ns)
                    cell_type = cell.attrib.get("t")
                    if cell_type == "s" and value_node is not None:
                        value = shared[int(value_node.text or "0")]
                    elif cell_type == "inlineStr" and inline is not None:
                        value = "".join(node.text or "" for node in inline.findall(".//m:t", ns))
                    else:
                        value = value_node.text if value_node is not None and value_node.text else ""
                    values[index - 1] = value.strip()
                if values:
                    rows.append([values.get(index, "") for index in range(max(values) + 1)])

            header_index = next((index for index, row in enumerate(rows) if row and row[0] == "编号"), None)
            if header_index is None:
                continue
            headers = rows[header_index]
            result[name] = [
                {headers[index]: value for index, value in enumerate(row) if index < len(headers)}
                for row in rows[header_index + 1 :]
                if row and row[0].startswith("EV-")
            ]
        return result


def duration_seconds(value: str) -> int:
    parts = [int(part) for part in value.split(":") if part.isdigit()]
    if len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    return 0


def age_range(value: str) -> tuple[int, int]:
    ages = [int(item) for item in re.findall(r"\d+", value)]
    if not ages:
        return 3, 13
    return max(2, ages[0]), min(18, ages[-1])


def build_videos(workbook: Path) -> list[dict[str, object]]:
    sheets = read_xlsx_rows(workbook)
    combined = sheets.get("分龄视频", []) + sheets.get("拓展视频", [])
    preschool = {row["编号"]: row for row in sheets.get("幼儿重点", [])}
    by_id = {row["编号"]: row for row in combined}
    by_id.update(preschool)
    videos: list[dict[str, object]] = []
    for resource_id in sorted(by_id):
        row = by_id[resource_id]
        minimum, maximum = age_range(row.get("推荐年龄", ""))
        videos.append(
            {
                "id": f"video-{resource_id.lower()}",
                "kind": "video",
                "titleZh": row.get("视频标题（原文）", ""),
                "titleEn": row.get("视频标题（原文）", ""),
                "summaryZh": row.get("中文简介", ""),
                "summaryEn": "Parent-curated educational video. Review the Chinese guide or watch together before assigning.",
                "sourceName": row.get("来源频道", ""),
                "sourceURL": row.get("视频真实链接", ""),
                "languageCode": "en",
                "minAge": minimum,
                "maxAge": maximum,
                "durationSeconds": duration_seconds(row.get("时长", "")),
                "categoriesZh": [row.get("学科 / 类别", "教育视频")],
                "categoriesEn": ["Educational Video"],
                "metadata": {
                    "learningSuggestionZh": row.get("陪看 / 学习建议", ""),
                    "validation": row.get("链接状态", ""),
                    "catalog": "official-education-videos-2026-07",
                },
            }
        )
    return videos


def build_books(catalog_path: Path) -> list[dict[str, object]]:
    catalog = json.loads(catalog_path.read_text())
    grouped: dict[int, dict[str, object]] = {}
    for section in catalog.get("categories", []):
        category = section.get("category", "图书")
        for book in section.get("books", []):
            item = grouped.setdefault(
                int(book["id"]),
                {
                    "id": f"book-gutenberg-{book['id']}",
                    "kind": "book",
                    "titleZh": book["title"],
                    "titleEn": book["title"],
                    "summaryZh": "章鱼老师精选的免费公版 EPUB 书目。家长确认后再下载并布置阅读。",
                    "summaryEn": "A free public-domain EPUB selected by Octo Teacher. Parents confirm before download or assignment.",
                    "sourceName": "Project Gutenberg",
                    "sourceURL": book["url"],
                    "languageCode": "en",
                    "minAge": 3,
                    "maxAge": 18,
                    "durationSeconds": 0,
                    "categoriesZh": [],
                    "categoriesEn": ["Free Books"],
                    "metadata": {"gutenbergID": int(book["id"]), "catalog": "official-free-library-2026-07"},
                },
            )
            categories = item["categoriesZh"]
            if category not in categories:
                categories.append(category)
    return sorted(grouped.values(), key=lambda item: item["id"])


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: build-official-content-data.py VIDEO_XLSX BOOK_JSON OUTPUT_JSON")
    videos = build_videos(Path(sys.argv[1]))
    books = build_books(Path(sys.argv[2]))
    payload = {
        "schemaVersion": 1,
        "generatedAt": "2026-07-12",
        "resources": books + videos,
        "packs": {
            "octoteacher-free-library": [item["id"] for item in books],
            "octoteacher-education-videos": [item["id"] for item in videos],
        },
    }
    Path(sys.argv[3]).parent.mkdir(parents=True, exist_ok=True)
    Path(sys.argv[3]).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"generated {len(books)} books and {len(videos)} videos")


if __name__ == "__main__":
    main()
