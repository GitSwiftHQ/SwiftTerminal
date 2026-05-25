#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import json
import plistlib
import subprocess
from pathlib import Path


COLOR_KEY_MAP = {
    "Foreground Color": "foreground",
    "Background Color": "background",
    "Cursor Color": "cursor",
    "Cursor Text Color": "cursorAccent",
    "Selection Color": "selectionBackground",
    "Selected Text Color": "selectionForeground",
}

ANSI_KEY_MAP = {
    **{f"Ansi {index} Color": key for index, key in enumerate(
        [
            "black",
            "red",
            "green",
            "yellow",
            "blue",
            "magenta",
            "cyan",
            "white",
            "brightBlack",
            "brightRed",
            "brightGreen",
            "brightYellow",
            "brightBlue",
            "brightMagenta",
            "brightCyan",
            "brightWhite",
        ]
    )}
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a SwiftTerminal built-in theme catalog from iTerm2 .itermcolors files."
    )
    parser.add_argument(
        "source",
        type=Path,
        help="Path to the iTerm2-Color-Schemes repository root or its schemes directory.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Sources/SwiftTerminal/Resources/TerminalThemes/iTerm2Themes.json"),
        help="Output JSON path relative to the current working directory.",
    )
    parser.add_argument(
        "--source-repository-url",
        default="https://github.com/mbadolato/iTerm2-Color-Schemes",
        help="Repository URL recorded in the generated catalog.",
    )
    return parser.parse_args()


def resolve_scheme_directory(source: Path) -> Path:
    source = source.resolve()
    if source.is_dir() and source.name == "schemes":
        return source

    schemes_directory = source / "schemes"
    if schemes_directory.is_dir():
        return schemes_directory

    raise SystemExit(f"Could not find a schemes directory under {source}")


def read_git_commit(source: Path) -> str:
    try:
        return (
            subprocess.check_output(
                ["git", "-C", str(source), "rev-parse", "HEAD"],
                stderr=subprocess.DEVNULL,
                text=True,
            )
            .strip()
        )
    except (OSError, subprocess.CalledProcessError):
        return ""


def component_to_int(value: float) -> int:
    bounded_value = min(max(float(value), 0.0), 1.0)
    return round(bounded_value * 255)


def color_to_hex(color: dict[str, object]) -> str:
    red = component_to_int(color.get("Red Component", 0.0))
    green = component_to_int(color.get("Green Component", 0.0))
    blue = component_to_int(color.get("Blue Component", 0.0))
    alpha = component_to_int(color.get("Alpha Component", 1.0))

    if alpha == 255:
        return f"#{red:02X}{green:02X}{blue:02X}"

    return f"#{red:02X}{green:02X}{blue:02X}{alpha:02X}"


def load_theme(path: Path) -> dict[str, str]:
    data = plistlib.loads(path.read_bytes())
    theme: dict[str, str] = {"name": path.stem}

    for plist_key, json_key in COLOR_KEY_MAP.items():
        theme[json_key] = color_to_hex(data[plist_key])

    theme["selectionInactiveBackground"] = theme["selectionBackground"]

    for plist_key, json_key in ANSI_KEY_MAP.items():
        theme[json_key] = color_to_hex(data[plist_key])

    return theme


def main() -> None:
    arguments = parse_arguments()
    source = arguments.source.resolve()
    scheme_directory = resolve_scheme_directory(source)
    themes = [load_theme(path) for path in sorted(scheme_directory.glob("*.itermcolors"))]

    catalog = {
        "sourceRepositoryURL": arguments.source_repository_url,
        "sourceCommit": read_git_commit(source),
        "generatedAt": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "themeCount": len(themes),
        "themes": themes,
    }

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
