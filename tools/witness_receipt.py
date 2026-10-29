#!/usr/bin/env python3
r"""witness_receipt.py — детерминированная квитанция прогона инвариантов rETH.

Зачем: в заявке на грант Rocket Pool обещан «детерминированный верификатор, который выдаёт подписанную
квитанцию для сдачи». Здесь реализована **первая половина** этого обещания — квитанция, которую можно
пересчитать: она фиксирует блок, версии инструментов, дайджесты входных файлов и построчный результат
тестов. Подписи пока нет, и квитанция это честно пишет в поле `signed: false`.

    python tools/witness_receipt.py --block 26294800
    python tools/witness_receipt.py --block 26294800 --json receipts/r.json

Пересчёт: две квитанции на один блок и одинаковые дайджесты входов должны совпасть по полю `tests`
(имена и статусы). Если не совпали — значит изменился код или окружение, и это видно.

Зависимости: forge (Foundry), python 3.11+. Сеть нужна только чтобы `forge` поднял форк.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import datetime as dt

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_RPC = "https://eth-mainnet.public.blastapi.io"


def find_forge() -> str | None:
    env = os.environ.get("FORGE_BIN")
    if env and pathlib.Path(env).exists():
        return env
    w = shutil.which("forge")
    if w:
        return w
    home = pathlib.Path.home() / ".foundry" / "bin"
    for name in ("forge.exe", "forge"):
        cand = home / name
        if cand.exists():
            return str(cand)
    return None


def digest(path: pathlib.Path) -> str:
    if not path.exists():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--block", type=int, required=True, help="номер блока для форка (пин)")
    ap.add_argument("--rpc", default=DEFAULT_RPC)
    ap.add_argument("--json", help="куда записать квитанцию (по умолчанию receipts/<block>.json)")
    a = ap.parse_args(argv[1:])

    forge = find_forge()
    if not forge:
        print("не найден forge (FORGE_BIN / PATH / ~/.foundry/bin)")
        return 2

    env = dict(os.environ)
    env["FORK_BLOCK"] = str(a.block)
    env.setdefault("FORK_RPC_URL", a.rpc)
    print(f"прогон: block={a.block} rpc={a.rpc}")

    try:
        r = subprocess.run([forge, "test", "--json"], cwd=str(ROOT), env=env,
                           capture_output=True, text=True, timeout=1800,
                           encoding="utf-8", errors="ignore")
    except subprocess.TimeoutExpired:
        print("таймаут forge test")
        return 1

    out = (r.stdout or "").strip()
    tests: list[dict] = []
    try:
        data = json.loads(out.splitlines()[-1]) if out else {}
        for suite, payload in (data.items() if isinstance(data, dict) else []):
            for name, res in (payload.get("test_results") or {}).items():
                tests.append({"suite": suite.split(":")[-1], "test": name,
                              "status": res.get("status"), "reason": res.get("reason") or None,
                              "gas": res.get("gas")})
    except Exception:
        tests = []

    passed = sum(1 for t in tests if t["status"] == "Success")
    receipt = {
        "kind": "reth-invariant-witness-receipt",
        "version": 1,
        "generated_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "block": a.block,
        "rpc": a.rpc,
        "forge_exit_code": r.returncode,
        "signed": False,
        "signature_note": "no signing key is used; this receipt is reproducible, not attested",
        "inputs": {
            "test/REthAccounting.t.sol": digest(ROOT / "test" / "REthAccounting.t.sol"),
            "foundry.toml": digest(ROOT / "foundry.toml"),
            "CLAIMS.md": digest(ROOT / "CLAIMS.md"),
            "NOT-CLAIMED.md": digest(ROOT / "NOT-CLAIMED.md"),
        },
        "summary": {"tests": len(tests), "passed": passed, "failed": len(tests) - passed},
        "tests": sorted(tests, key=lambda t: t["test"]),
    }

    out_path = pathlib.Path(a.json) if a.json else ROOT / "receipts" / f"{a.block}.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"квитанция: {out_path}")
    print(f"итог: {passed}/{len(tests)} пройдено, exit={r.returncode}")
    for t in receipt["tests"]:
        print(f"  {'PASS' if t['status'] == 'Success' else 'FAIL':4} {t['test']}")
    return 0 if r.returncode == 0 and passed == len(tests) and tests else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
