import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import bootstrap_native  # noqa: E402


class PrepareCMakeBuildTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.source = self.root / "source"
        self.build = self.root / "build"
        self.build.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_cache(self, build: Path, source: Path) -> None:
        (self.build / "CMakeCache.txt").write_text(
            f"CMAKE_CACHEFILE_DIR:INTERNAL={build}\n"
            f"CMAKE_HOME_DIRECTORY:INTERNAL={source}\n",
            encoding="utf-8",
        )

    def test_current_location_preserves_build_tree(self) -> None:
        self.write_cache(self.build, self.source)
        marker = self.build / "marker"
        marker.touch()

        bootstrap_native.prepare_cmake_build(self.build, self.source)

        self.assertTrue(marker.exists())

    def test_previous_location_removes_build_tree(self) -> None:
        self.write_cache(self.root / "old-build", self.root / "old-source")

        bootstrap_native.prepare_cmake_build(self.build, self.source)

        self.assertFalse(self.build.exists())


if __name__ == "__main__":
    unittest.main()
