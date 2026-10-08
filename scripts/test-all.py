#!/usr/bin/env python3
"""Run the existing Luau fixtures without PowerShell (Python 3.9+, no packages).

The PowerShell suite files remain the source of module lists and environment
wrappers. This adapter supports their explicit AppendLine forms, not arbitrary
PowerShell. Unknown forms fail instead of silently skipping fixture setup.
"""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
AGGREGATE = "test-performance-polish.ps1"
ENTRY = re.compile(r"^\s*(\w+)\s*=\s*'((?:src|tests)/[^']+)'", re.M)
FILE = re.compile(r"'((?:src|tests)/[^']+)'")


def bundle(suite, test_filter=None):
    source = suite.read_text(encoding="utf-8-sig")
    entries = ENTRY.findall(source)
    output = []

    def emit(line, key=None, path=None):
        if ".AppendLine(" not in line:
            return
        expression = line.split(".AppendLine(", 1)[1].strip()
        if not expression.endswith(")"):
            raise ValueError(f"Unsupported multiline AppendLine in {suite.name}")
        expression = expression[:-1]
        if "$filterExpression" in expression:
            expected = "'end)(); tests(function(name, env) return loaders[name](env or {}) end, ' + $filterExpression + ')'"
            if expression != expected:
                raise ValueError(f"Unsupported filter invocation in {suite.name}")
            encoded = ",".join(str(byte) for byte in (test_filter or "").encode("utf-8"))
            value = f"string.char({encoded})" if encoded else "nil"
            output.append(f"end)(); tests(function(name, env) return loaders[name](env or {{}}) end, {value})")
        elif re.fullmatch(r"'(?:[^']|'')*'", expression):
            output.append(expression[1:-1].replace("''", "'"))
        elif re.fullmatch(r'"loaders\.\$\(\$\w+\.Key\) = function\((?:env)?\)"', expression) and key:
            arguments = "env" if "function(env)" in expression else ""
            output.append(f"loaders.{key} = function({arguments})")
        elif expression.startswith("[System.IO.File]::ReadAllText((Join-Path "):
            fixed = FILE.search(expression)
            file_path = fixed.group(1) if fixed else path
            if not file_path:
                raise ValueError(f"Missing input path in {suite.name}: {expression}")
            output.append((ROOT / file_path).read_text(encoding="utf-8-sig"))
        elif expression.startswith("$caseShopSource.Substring("):
            # Use the same literal anchors as the native case-viewport runner.
            kind = "Prelude" if "$casePreludeStart," in expression else "Reel"
            anchors = []
            for endpoint in ("Start", "End"):
                match = re.search(r"\$case" + kind + endpoint + r" = \$caseShopSource.IndexOf\('([^']+)'", source)
                if not match:
                    raise ValueError(f"Missing {kind}{endpoint} extraction anchor")
                anchors.append(match.group(1))
            shop = (ROOT / "src/PlayerClient/ShopGUI.luau").read_text(encoding="utf-8")
            start = shop.index(anchors[0])
            output.append(shop[start:shop.index(anchors[1], start)])
        else:
            raise ValueError(f"Unsupported AppendLine in {suite.name}: {expression}")

    lines = iter(source.splitlines())
    for line in lines:
        if line.startswith("foreach "):
            if not entries:
                raise ValueError(f"No modules for loop in {suite.name}")
            body = []
            for loop_line in lines:
                if loop_line == "}":
                    break
                body.append(loop_line)
            else:
                raise ValueError(f"Unterminated module loop in {suite.name}")
            for key, path in entries:
                for loop_line in body:
                    emit(loop_line, key, path)
        else:
            emit(line)
    if not output or not any("local tests =" in line for line in output):
        raise ValueError(f"No test invocation generated for {suite.name}")
    return "\n".join(output) + "\n"


def executable(value):
    found = shutil.which(value)
    if found:
        return found
    path = Path(value).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"Executable not found: {value}")
    return str(path)


def main():
    suites = {p.stem.removeprefix("test-"): p for p in sorted((ROOT / "scripts").glob("test-*.ps1")) if p.name != AGGREGATE}
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default="luau", help="Official Luau CLI path (tested with 0.741)")
    parser.add_argument("--suite", nargs="+", choices=sorted(suites), help="Default: all suites")
    parser.add_argument("--test-filter", help="Literal name filter; requires --suite game-systems")
    parser.add_argument("--output-dir", type=Path, help="Retain generated bundles and logs here")
    parser.add_argument("--compile", metavar="LUAU_COMPILE", help="Also syntax-check every source, test and dependency script")
    parser.add_argument("--rojo", help="Also build default.project.json with this Rojo executable")
    args = parser.parse_args()
    if args.test_filter is not None and args.suite != ["game-systems"]:
        parser.error("--test-filter requires --suite game-systems")
    luau = executable(args.luau)
    failed = 0
    selected = args.suite or list(suites)
    with tempfile.TemporaryDirectory(prefix="stab-tests-") as temporary:
        output = args.output_dir.resolve() if args.output_dir else Path(temporary)
        output.mkdir(parents=True, exist_ok=True)
        for name in selected:
            target = output / f"test-{name}.luau"
            target.write_text(bundle(suites[name], args.test_filter), encoding="utf-8")
            try:
                result = subprocess.run([luau, str(target)], cwd=ROOT, capture_output=True, text=True, timeout=90)
                log = result.stdout + result.stderr
                ok = result.returncode == 0
            except subprocess.TimeoutExpired:
                log, ok = "Suite exceeded 90 seconds.\n", False
            target.with_suffix(".log").write_text(log, encoding="utf-8")
            print(f"{'PASS' if ok else 'FAIL'} {name}", flush=True)
            if not ok:
                print(log)
                failed += 1
        print(f"{len(selected) - failed}/{len(selected)} suites passed")
        if args.compile:
            compiler = executable(args.compile)
            files = sorted(p for directory in ("src", "tests", "Packages") for p in (ROOT / directory).rglob("*") if p.suffix in (".lua", ".luau"))
            compile_failures = 0
            for path in files:
                result = subprocess.run([compiler, "--null", str(path)], capture_output=True, text=True, timeout=30)
                if result.returncode:
                    print(result.stdout + result.stderr)
                    compile_failures += 1
            print(f"Compiled {len(files)} scripts; failures: {compile_failures}")
            failed += compile_failures
        if args.rojo:
            result = subprocess.run([executable(args.rojo), "build", "default.project.json", "-o", str(output / "Stab-Combat.rbxlx")], cwd=ROOT, timeout=90)
            failed += result.returncode != 0
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
