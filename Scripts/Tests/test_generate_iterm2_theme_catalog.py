from __future__ import annotations

import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "generate_iterm2_theme_catalog.py"
SPEC = importlib.util.spec_from_file_location("generate_iterm2_theme_catalog", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load generator at {SCRIPT_PATH}")

GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def color(red: float, green: float, blue: float) -> dict[str, float]:
    return {
        "Red Component": red,
        "Green Component": green,
        "Blue Component": blue,
        "Alpha Component": 1.0,
    }


def required_theme_colors() -> dict[str, dict[str, float]]:
    colors = {
        "Foreground Color": color(0.0, 0.0, 0.0),
        "Background Color": color(1.0, 1.0, 1.0),
        "Cursor Color": color(1.0, 0.0, 0.0),
        "Selection Color": color(0.0, 1.0, 0.0),
    }
    colors.update(
        {
            f"Ansi {index} Color": color(0.0, 0.0, 0.0)
            for index in range(16)
        }
    )
    return colors


class ThemeCatalogGeneratorTests(unittest.TestCase):
    def load_theme(
        self,
        colors: dict[str, dict[str, float]],
    ) -> dict[str, str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Fixture.itermcolors"
            path.write_bytes(plistlib.dumps(colors))
            return GENERATOR.load_theme(path)

    def test_missing_optional_text_colors_use_semantic_fallbacks(self) -> None:
        theme = self.load_theme(required_theme_colors())

        self.assertEqual(theme["cursorAccent"], "#FFFFFF")
        self.assertEqual(theme["selectionForeground"], "#000000")
        self.assertEqual(theme["selectionInactiveBackground"], "#00FF00")

    def test_explicit_optional_text_colors_take_precedence(self) -> None:
        colors = required_theme_colors()
        colors["Cursor Text Color"] = color(0.0, 0.0, 1.0)
        colors["Selected Text Color"] = color(1.0, 0.0, 1.0)

        theme = self.load_theme(colors)

        self.assertEqual(theme["cursorAccent"], "#0000FF")
        self.assertEqual(theme["selectionForeground"], "#FF00FF")


if __name__ == "__main__":
    unittest.main()
