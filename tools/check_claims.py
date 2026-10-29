#!/usr/bin/env python3
"""check_claims.py — fails if a claim in CLAIMS.md has no test, or if the suite does not pass.

The point: a claim registry that is not enforced decays into marketing. This guard reads CLAIMS.md,
extracts every `test` evidence reference, checks that the named test exists in the Solidity file, and
(optionally, with --run) runs the suite and requires "7 passed".

    python tools/check_claims.py            # static check only
    python tools/check_claims.py --run      # also run forge test (needs MAINNET_RPC_URL)
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAIMS = ROOT / "CLAIMS.md"
SOL = ROOT / "test" / "REthAccounting.t.sol"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", action="store_true", help="also run forge test")
    a = ap.parse_args()

    if not CLAIMS.exists() or not SOL.exists():
        print("FAIL: CLAIMS.md or the test file is missing")
        return 1

    claims = CLAIMS.read_text(encoding="utf-8")
    source = SOL.read_text(encoding="utf-8")

    # every backticked test name referenced as evidence must exist in the Solidity file
    referenced = set(re.findall(r"`(test\w+)`", claims))
    referenced |= set(re.findall(r"`(testFuzz_\w+)`", claims))
    missing = [t for t in sorted(referenced) if f"function {t}(" not in source]
    if missing:
        print("FAIL: claims reference tests that do not exist:")
        for t in missing:
            print("  -", t)
        return 1

    # ДЫРА, найденная 29.10: строка таблицы, где свидетельство `test`, но имя теста НЕ в бэктиках,
    # проходила молча — парсер её просто не видел. Это P12 («новый код отказа — новый дефект»):
    # гейт обязан падать на строке, которую не смог разобрать.
    unparsed = []
    for line in claims.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        joined = " ".join(cells).lower()
        has_test_evidence = ("test" in joined) or ("тест" in joined)
        if not has_test_evidence:
            continue
        names = re.findall(r"`(test\w+)`", " ".join(cells))
        if not names:
            unparsed.append(line.strip()[:120])
    if unparsed:
        print("FAIL: строки утверждают свидетельство `test`, но не называют теста в бэктиках:")
        for u in unparsed:
            print("  -", u)
        return 1

    defined = set(re.findall(r"function (test\w*|testFuzz_\w+)\(", source))
    unused = sorted(defined - referenced)
    print(f"claims with test evidence: {len(referenced)}")
    print(f"tests defined: {len(defined)}")
    if unused:
        print("note: tests defined but not referenced by a claim (not an error):")
        for t in unused:
            print("  -", t)

    if a.run:
        rpc = os.environ.get("MAINNET_RPC_URL")
        if not rpc:
            print("FAIL: --run needs MAINNET_RPC_URL")
            return 1
        env = dict(os.environ, MAINNET_RPC_URL=rpc)
        forge = os.environ.get("FORGE_BIN") or shutil.which("forge")
        if not forge:
            default = Path(os.environ.get("USERPROFILE", "")) / ".foundry" / "bin" / ("forge.exe" if os.name == "nt" else "forge")
            forge = str(default) if default.exists() else "forge"
        proc = subprocess.run(
            [forge, "test", "--match-contract", "REthAccountingTest", "--fuzz-runs", "200"],
            cwd=ROOT, env=env, capture_output=True, text=True,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        m = re.search(r"(\d+) passed; (\d+) failed", out)
        if not m:
            print("FAIL: could not read the test summary")
            print(out[-800:])
            return 1
        passed, failed = int(m.group(1)), int(m.group(2))
        print(f"forge test: {passed} passed, {failed} failed")
        if failed:
            return 1
        if passed != len(defined):
            print(f"FAIL: {len(defined)} tests defined but {passed} passed")
            return 1

    print("OK: every claim with test evidence points at an existing, passing test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
