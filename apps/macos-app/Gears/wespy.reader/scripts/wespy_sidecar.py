#!/usr/bin/env python3
"""GeeAgent WeSpy Reader sidecar.

This wrapper intentionally imports the user's installed `wespy` package instead
of vendoring third-party source into GeeAgent.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


def main() -> int:
    if len(sys.argv) != 2:
        emit_error("missing_request", "Usage: wespy_sidecar.py <request.json>")
        return 2

    try:
        request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        action = str(request.get("action") or "")
        params = request.get("params") or {}
        if not isinstance(params, dict):
            raise ValueError("params must be an object")

        result = run(action, params)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0 if result.get("status") != "failed" else 1
    except Exception as exc:  # noqa: BLE001 - sidecar boundary should report all failures.
        emit_error("sidecar_failed", str(exc))
        return 1


def run(action: str, params: dict[str, Any]) -> dict[str, Any]:
    try:
        from wespy import ArticleFetcher  # type: ignore
        from wespy.main import WeChatAlbumFetcher  # type: ignore
    except Exception as exc:  # noqa: BLE001
        return failed(
            action=action,
            code="wespy_import_failed",
            message=(
                "Could not import the Python package `wespy`. "
                "Open WeSpy Reader from Gears and let GeeAgent finish dependency setup. "
                f"Detail: {exc}"
            ),
        )

    url = clean_string(params.get("url"))
    if not url:
        return failed(action=action, code="missing_url", message="`url` is required.")

    output_dir = Path(clean_string(params.get("output_dir")) or "articles").expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)
    before = snapshot_files(output_dir)
    log_buffer = io.StringIO()

    save_html = bool(params.get("save_html"))
    save_json = bool(params.get("save_json"))
    save_markdown = params.get("save_markdown")
    if save_markdown is None:
        save_markdown = True
    max_articles = bounded_int(params.get("max_articles"), default=10, minimum=1, maximum=200)

    with contextlib.redirect_stdout(log_buffer):
        if action == "list_album":
            articles = WeChatAlbumFetcher().fetch_album_articles(url, max_articles)
            list_path = output_dir / f"album_articles_{int(time.time())}.json"
            list_path.write_text(json.dumps(articles, ensure_ascii=False, indent=2), encoding="utf-8")
            result: Any = articles
        elif action == "fetch_album":
            result = ArticleFetcher().fetch_album_articles(
                url,
                str(output_dir),
                max_articles=max_articles,
                save_html=save_html,
                save_json=save_json,
                save_markdown=bool(save_markdown),
            )
        elif action == "fetch_article":
            result = ArticleFetcher().fetch_article(
                url,
                str(output_dir),
                save_html=save_html,
                save_json=save_json,
                save_markdown=bool(save_markdown),
            )
        else:
            return failed(action=action, code="unsupported_action", message=f"Unsupported action `{action}`.")

    after = snapshot_files(output_dir)
    files = sorted(str(path) for path in after - before)

    if not result:
        return failed(
            action=action,
            code="wespy_no_result",
            message="WeSpy did not return any article data.",
            output_dir=str(output_dir),
            files=files,
            log=log_buffer.getvalue(),
        )

    payload = {
        "status": "completed",
        "action": action,
        "url": url,
        "output_dir": str(output_dir),
        "files": files,
        "log": log_buffer.getvalue(),
    }

    if isinstance(result, list):
        payload["article_count"] = len(result)
        payload["articles"] = compact_articles(result)
    elif isinstance(result, dict):
        payload["article_count"] = 1
        payload["title"] = clean_string(result.get("title"))
        payload["author"] = clean_string(result.get("author"))
        payload["publish_time"] = clean_string(result.get("publish_time"))
        payload["source_url"] = clean_string(result.get("url")) or url
        payload["articles"] = compact_articles([result])
    else:
        payload["article_count"] = 0
        payload["articles"] = []
        payload["raw_result_type"] = type(result).__name__

    return payload


def compact_articles(articles: list[Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for item in articles[:200]:
        if not isinstance(item, dict):
            continue
        out.append(
            {
                key: clean_string(item.get(key))
                for key in ["title", "author", "publish_time", "url", "msgid", "create_time"]
                if clean_string(item.get(key))
            }
        )
    return out


def snapshot_files(root: Path) -> set[Path]:
    if not root.exists():
        return set()
    return {path.resolve() for path in root.rglob("*") if path.is_file()}


def bounded_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = default
    return min(max(parsed, minimum), maximum)


def clean_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def failed(
    *,
    action: str,
    code: str,
    message: str,
    output_dir: str | None = None,
    files: list[str] | None = None,
    log: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "status": "failed",
        "action": action,
        "code": code,
        "error": message,
    }
    if output_dir:
        payload["output_dir"] = output_dir
    if files is not None:
        payload["files"] = files
    if log:
        payload["log"] = log
    return payload


def emit_error(code: str, message: str) -> None:
    print(json.dumps(failed(action="unknown", code=code, message=message), ensure_ascii=False))


if __name__ == "__main__":
    raise SystemExit(main())
