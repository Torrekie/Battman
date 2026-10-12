#!/usr/bin/env python3
"""Bounded Foundation-only statistics check using the current source tree."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[6]
statistics = Path(__file__).resolve().parent.parent
data = repo / "Battman/Features/Analytics/Data"
sources = [data / name for name in ("BAAnalyticsHistoryModels.m", "BAAnalyticsReport.m")]
missing = [source.name for source in sources if not source.is_file()]
if missing:
    raise SystemExit("Missing Analytics data sources: " + ", ".join(missing))
clang = subprocess.check_output(["xcrun", "--sdk", "macosx", "--find", "clang"], text=True).strip()
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="battman-statistics-") as directory:
    temporary = Path(directory)
    binary = temporary / "statistics-analysis-tests"
    subprocess.run([clang, "-isysroot", sdk, "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-framework", "Foundation", "-I", str(data), str(statistics / "Tests/BAStatisticsAnalysisTests.m"), str(statistics / "BAStatisticsAnalysis.m"), *(str(source) for source in sources), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
