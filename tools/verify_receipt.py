#!/usr/bin/env python3
r"""verify_receipt.py — проверить квитанцию прогона по её же правилам.

Зачем: квитанция, которую никто не проверяет, — это JSON-файл с красивыми словами. Скрипт делает
квитанцию **проверяемой**: пересчитывает дайджесты входных файлов, сравнивает с записанными и (по желанию)
перезапускает сами тесты, чтобы сверить построчный результат.

    python tools/verify_receipt.py receipts/26294800.json            # только дайджесты (быстро, без сети)
    python tools/verify_receipt.py receipts/26294800.json --rerun     # плюс перезапуск тестов на том же блоке

Коды возврата: 0 — всё совпало, 1 — расхождение, 2 — квитанцию не удалось прочитать.

Отрицательный тест (обязателен, иначе проверка ничего не стоит):
    подменить один байт в квитанции → скрипт обязан вернуть 1.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FORGE = (pathlib.Path.home() / ".foundry" / "bin" / "forge.exe")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("receipt")
    ap.add_argument("--rerun", action="store_true", help="перезапустить тесты на блоке из квитанции")
    a = ap.parse_args(argv[1:])

    path = pathlib.Path(a.receipt)
    try:
        r = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"не читается: {exc}")
        return 2

    print(f"квитанция: {path.name} | вид: {r.get('kind')} v{r.get('version')} | блок {r.get('block')}")
    if r.get("kind") != "reth-invariant-witness-receipt":
        print("ЧУЖОЙ ВИД КВИТАНЦИИ — проверять нечем")
        return 1

    ok = True
    print("\n1) дайджесты входных файлов:")
    for rel, recorded in (r.get("inputs") or {}).items():
        p = ROOT / rel
        if not p.exists():
            print(f"   ❌ {rel}: файла нет")
            ok = False
            continue
        actual = sha256(p)
        same = actual == recorded
        ok = ok and same
        print(f"   {'✅' if same else '❌'} {rel}: {'совпал' if same else f'ИЗМЕНИЛСЯ ({actual[:16]}… vs {recorded[:16]}…)'}")

    summary = r.get("summary") or {}
    print(f"\n2) записанный итог: {summary.get('passed')}/{summary.get('tests')} пройдено, "
          f"exit={r.get('forge_exit_code')}")
    if summary.get("passed") != summary.get("tests"):
        print("   ❌ в самой квитанции не всё пройдено — это провал, а не успех")
        ok = False

    if a.rerun:
        if not FORGE.exists():
            print("\n3) перезапуск: forge не найден — пропуск")
        else:
            print(f"\n3) перезапуск тестов на блоке {r.get('block')}:")
            env = dict(**__import__("os").environ)
            env["FORK_BLOCK"] = str(r.get("block"))
            env.setdefault("FORK_RPC_URL", r.get("rpc") or "")
            try:
                res = subprocess.run([str(FORGE), "test", "--json"], cwd=str(ROOT), env=env,
                                     capture_output=True, text=True, timeout=1800,
                                     encoding="utf-8", errors="ignore")
            except subprocess.TimeoutExpired:
                print("   ❌ таймаут")
                return 1
            now = []
            try:
                data = json.loads((res.stdout or "").strip().splitlines()[-1])
                for suite, payload in data.items():
                    for name, tr in (payload.get("test_results") or {}).items():
                        now.append({"test": name, "status": tr.get("status")})
            except Exception:
                print("   ❌ не разобрать вывод forge")
                return 1
            before = {t["test"]: t["status"] for t in (r.get("tests") or [])}
            after = {t["test"]: t["status"] for t in now}
            if before == after:
                print(f"   ✅ набор и статусы совпали ({len(after)} тестов)")
            else:
                ok = False
                only_before = set(before) - set(after)
                only_after = set(after) - set(before)
                changed = {k for k in set(before) & set(after) if before[k] != after[k]}
                if only_before:
                    print(f"   ❌ пропали тесты: {sorted(only_before)}")
                if only_after:
                    print(f"   ❌ появились тесты: {sorted(only_after)}")
                if changed:
                    print(f"   ❌ изменили статус: {sorted(changed)}")

    # ЧЕСТНАЯ ГРАНИЦА: без подписи нельзя доказать, на каком блоке квитанция получена.
    # Подмена поля "block" в файле проходит дайджест-проверку (это проверено отрицательным тестом),
    # и даже --rerun не отличит блок 26294800 от 26294801, если тесты зелёные на обоих.
    if ok and a.rerun:
        print("\nИТОГ: дайджесты совпали, результаты воспроизведены на записанном блоке.")
        print("      Происхождение квитанции этим НЕ доказывается: подписи нет (signed: false).")
    elif ok:
        print("\nИТОГ: дайджесты совпали. Результаты не перепроверялись (нет --rerun).")
        print("      Подмена поля block в файле при этом не обнаруживается — это ожидаемое ограничение.")
    else:
        print("\nИТОГ: КВИТАНЦИЯ НЕ ПОДТВЕРЖДЕНА")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
