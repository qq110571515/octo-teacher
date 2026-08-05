#!/usr/bin/env python3
"""Render idempotent SQL batches for environments where DB credentials stay sealed."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def quote(value: object) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def array(values: list[str]) -> str:
    return "array[" + ",".join(quote(value) for value in values) + "]::text[]"


def resources(payload: dict[str, object], offset: int, limit: int) -> str:
    rows = []
    for item in payload["resources"][offset : offset + limit]:
        rows.append(
            "(" + ",".join(
                [
                    quote(item["id"]), quote(item["kind"]), quote(item["titleZh"]), quote(item["titleEn"]),
                    quote(item["summaryZh"]), quote(item["summaryEn"]), quote(item["sourceName"]), quote(item["sourceURL"]),
                    quote(item.get("thumbnailURL")), quote(item["languageCode"]), str(item["minAge"]), str(item["maxAge"]),
                    str(item["durationSeconds"]), array(item["categoriesZh"]), array(item["categoriesEn"]),
                    quote(json.dumps(item["metadata"], ensure_ascii=False)) + "::jsonb",
                    quote("creator-octoteacher-official"), quote("published"), "now()", "now()",
                ]
            ) + ")"
        )
    return """insert into marketplace_content_resources (
id,kind,title_zh,title_en,summary_zh,summary_en,source_name,source_url,thumbnail_url,language_code,
min_age,max_age,duration_seconds,categories_zh,categories_en,metadata,creator_id,status,published_at,updated_at
) values
""" + ",\n".join(rows) + """
on conflict (id) do update set
kind=excluded.kind,title_zh=excluded.title_zh,title_en=excluded.title_en,summary_zh=excluded.summary_zh,
summary_en=excluded.summary_en,source_name=excluded.source_name,source_url=excluded.source_url,
thumbnail_url=excluded.thumbnail_url,language_code=excluded.language_code,min_age=excluded.min_age,
max_age=excluded.max_age,duration_seconds=excluded.duration_seconds,categories_zh=excluded.categories_zh,
categories_en=excluded.categories_en,metadata=excluded.metadata,creator_id=excluded.creator_id,
status='published',published_at=coalesce(marketplace_content_resources.published_at,now()),updated_at=now();
"""


def links(payload: dict[str, object]) -> str:
    resources_by_id = {item["id"]: item for item in payload["resources"]}
    statements = []
    for listing_id, identifiers in payload["packs"].items():
        statements.append(f"delete from marketplace_listing_resources where listing_id={quote(listing_id)};")
        rows = []
        for position, identifier in enumerate(identifiers):
            kind = resources_by_id[identifier]["kind"]
            behavior = "library_reference" if kind == "book" else "video_reference" if kind == "video" else "creation_template"
            rows.append(f"({quote(listing_id)},{quote(identifier)},{position},{quote(behavior)})")
        statements.append(
            "insert into marketplace_listing_resources (listing_id,resource_id,position,install_behavior) values\n"
            + ",\n".join(rows) + ";"
        )
    return "\n".join(statements)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: render-official-content-sql.py JSON resources OFFSET LIMIT | links")
    payload = json.loads(Path(sys.argv[1]).read_text())
    if sys.argv[2] == "links":
        print(links(payload))
    elif sys.argv[2] == "resources":
        print(resources(payload, int(sys.argv[3]), int(sys.argv[4])))
    else:
        raise SystemExit("unknown mode")


if __name__ == "__main__":
    main()
