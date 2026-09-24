import json
import sys
from pathlib import Path


def validate_style_results(path):
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"failed to read style50 JSON at {path}: {error}") from error

    required = {"files", "score", "version"}
    if not isinstance(result, dict) or not required.issubset(result):
        raise SystemExit("style50 JSON output is missing required fields")

    files = result["files"]
    if not isinstance(files, list) or not files:
        raise SystemExit("style50 JSON output did not include a file list")
    if result["score"] != 1:
        raise SystemExit("style50 JSON output reported a failing score")
    if not isinstance(result["version"], str) or not result["version"]:
        raise SystemExit("style50 JSON output has an invalid version")
    if any(not isinstance(file, dict) for file in files):
        raise SystemExit("style50 JSON output contains an invalid file entry")

    hello_result = next(
        (file for file in files if file.get("name") == "hello.c"),
        None,
    )
    if hello_result is None:
        raise SystemExit("style50 JSON output did not identify hello.c")
    if hello_result.get("score") != 1:
        raise SystemExit("style50 JSON output reported a failing file")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} JSON_FILE")
    validate_style_results(Path(sys.argv[1]))
