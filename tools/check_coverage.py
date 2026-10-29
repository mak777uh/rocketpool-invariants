#!/usr/bin/env python3
r"""check_coverage.py — матрица покрытия обязана совпадать с кодом.

Проверка: каждый тест из `test/*.sol` упомянут в `COVERAGE.md`, и в матрице нет тестов, которых в коде нет.
Если файлы расходятся — выход 1. Тот же принцип, что у верификатора квитанции: документ, который никто не
сверяет с кодом, через месяц становится ложью.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    cov_path = ROOT / "COVERAGE.md"
    if not cov_path.exists():
        print("COVERAGE.md отсутствует")
        return 1
    cov = cov_path.read_text(encoding="utf-8")
    code = ""
    for f in sorted((ROOT / "test").glob("*.sol")):
        code += f.read_text(encoding="utf-8")
    names = set(re.findall(r"function (test\w+)\s*\(", code))
    listed = set(re.findall(r"`(test\w+)", cov))
    missing = sorted(names - listed)
    extra = sorted(listed - names)
    print(f"тестов в коде: {len(names)} | в матрице: {len(listed)}")
    if missing:
        print(f"НЕ в матрице: {missing}")
    if extra:
        print(f"в матрице, но нет в коде: {extra}")
    ok = not missing and not extra
    print("ИТОГ:", "матрица соответствует коду" if ok else "МАТРИЦА РАСХОДИТСЯ С КОДОМ")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
