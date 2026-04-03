#!/usr/bin/env python3
"""Deterministic repository logic scanner for Meta-Master.

Outputs:
- JSON report with phase integrity + secure automation signals.
- Markdown upgrade plan with prioritized actions.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PHASE_PATTERN = re.compile(r"^(\d+)-.+\.sh$")


@dataclass
class CheckResult:
    name: str
    status: str
    details: str


@dataclass
class ScanSummary:
    repository: str
    generated_at_utc: str
    phase_count: int
    check_count: int
    pass_count: int
    warn_count: int
    fail_count: int


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_phase_integrity(phases_dir: Path) -> tuple[list[CheckResult], list[str]]:
    checks: list[CheckResult] = []
    phase_files = sorted(p.name for p in phases_dir.glob("*.sh"))
    seen_numbers: set[str] = set()
    duplicate_numbers: list[str] = []

    for name in phase_files:
        match = PHASE_PATTERN.match(name)
        if not match:
            continue
        number = match.group(1)
        if number in seen_numbers:
            duplicate_numbers.append(number)
        seen_numbers.add(number)

    if duplicate_numbers:
        checks.append(
            CheckResult(
                name="phase_duplicate_numbers",
                status="fail",
                details=f"Duplicate phase prefixes found: {sorted(set(duplicate_numbers))}",
            )
        )
    else:
        checks.append(
            CheckResult(
                name="phase_duplicate_numbers",
                status="pass",
                details="No duplicate phase prefixes found.",
            )
        )

    missing_safety: list[str] = []
    for filename in phase_files:
        content = read_text(phases_dir / filename)
        if "set -Eeuo pipefail" not in content:
            missing_safety.append(filename)

    if missing_safety:
        checks.append(
            CheckResult(
                name="phase_strict_mode",
                status="warn",
                details=f"Missing strict mode in: {missing_safety}",
            )
        )
    else:
        checks.append(
            CheckResult(
                name="phase_strict_mode",
                status="pass",
                details="All phase scripts contain strict shell mode.",
            )
        )

    return checks, phase_files


def check_repo_signals(repo_root: Path) -> list[CheckResult]:
    checks: list[CheckResult] = []

    critical_files = [
        repo_root / "README.md",
        repo_root / "CHANGELOG.md",
        repo_root / "generator" / "VERSION",
    ]
    missing_critical = [str(path.relative_to(repo_root)) for path in critical_files if not path.exists()]

    checks.append(
        CheckResult(
            name="release_metadata_files",
            status="fail" if missing_critical else "pass",
            details=(
                f"Missing release metadata files: {missing_critical}"
                if missing_critical
                else "README, CHANGELOG, and generator/VERSION are present."
            ),
        )
    )

    hit_count = 0
    scan_globs = ["**/*.sh", "**/*.ts", "**/*.py", "**/*.md"]
    excluded_paths = {
        Path("scripts/full_logic_scan.py"),
    }
    excluded_dirs = {"reports", ".git", "node_modules", "__pycache__"}
    for pattern in scan_globs:
        for path in repo_root.glob(pattern):
            relative_path = path.relative_to(repo_root)
            if any(part in excluded_dirs for part in relative_path.parts):
                continue
            if relative_path in excluded_paths:
                continue
            text = read_text(path)
            hit_count += text.count("TODO") + text.count("FIXME")

    checks.append(
        CheckResult(
            name="todo_fixme_debt",
            status="warn" if hit_count else "pass",
            details=f"Found {hit_count} TODO/FIXME markers in scanned files.",
        )
    )

    ci_candidates = [repo_root / ".github" / "workflows", repo_root / ".gitlab-ci.yml"]
    has_ci = any(path.exists() for path in ci_candidates)
    checks.append(
        CheckResult(
            name="cicd_presence",
            status="pass" if has_ci else "warn",
            details="CI/CD config detected." if has_ci else "No standard CI/CD pipeline file detected.",
        )
    )

    return checks


def build_upgrade_actions(checks: list[CheckResult]) -> list[str]:
    actions: list[str] = []
    for check in checks:
        if check.status == "fail":
            actions.append(f"[P0] Resolve {check.name}: {check.details}")
        elif check.status == "warn":
            actions.append(f"[P1] Improve {check.name}: {check.details}")

    if not actions:
        actions.append("[P2] No urgent gaps detected. Continue with periodic compliance scans.")

    actions.extend(
        [
            "[P1] Generate SBOM artifact in CI (SPDX/CycloneDX) and store alongside releases.",
            "[P1] Add automated vulnerability scan stage (e.g., Trivy/grype) before release packaging.",
            "[P2] Include reproducibility check by hashing generated artifacts across two clean runs.",
        ]
    )
    return actions


def write_upgrade_markdown(path: Path, actions: list[str], summary: ScanSummary) -> None:
    lines = [
        "# Logic Scan Upgrade Plan",
        "",
        f"Generated at (UTC): {summary.generated_at_utc}",
        f"Repository: `{summary.repository}`",
        "",
        "## Summary",
        f"- Checks: **{summary.check_count}**",
        f"- Pass: **{summary.pass_count}**",
        f"- Warn: **{summary.warn_count}**",
        f"- Fail: **{summary.fail_count}**",
        "",
        "## Prioritized Actions",
    ]
    lines.extend(f"- {item}" for item in actions)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(repo_root: Path, output_json: Path, output_md: Path) -> dict[str, Any]:
    phases_dir = repo_root / "generator" / "phases"
    if not phases_dir.exists():
        raise SystemExit(f"Missing phases directory: {phases_dir}")

    phase_checks, phase_files = check_phase_integrity(phases_dir)
    repo_checks = check_repo_signals(repo_root)
    checks = phase_checks + repo_checks

    pass_count = sum(1 for c in checks if c.status == "pass")
    warn_count = sum(1 for c in checks if c.status == "warn")
    fail_count = sum(1 for c in checks if c.status == "fail")

    summary = ScanSummary(
        repository=str(repo_root),
        generated_at_utc=datetime.now(timezone.utc).isoformat(),
        phase_count=len(phase_files),
        check_count=len(checks),
        pass_count=pass_count,
        warn_count=warn_count,
        fail_count=fail_count,
    )

    payload = {
        "summary": asdict(summary),
        "checks": [asdict(c) for c in checks],
        "upgrade_actions": build_upgrade_actions(checks),
    }

    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    write_upgrade_markdown(output_md, payload["upgrade_actions"], summary)
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run deterministic full logic scan and produce upgrade artifacts.")
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    parser.add_argument(
        "--output-json",
        default="reports/logic-scan-report.json",
        help="Path for JSON report output (relative to repo root)",
    )
    parser.add_argument(
        "--output-md",
        default="reports/logic-scan-upgrade-plan.md",
        help="Path for markdown upgrade plan output (relative to repo root)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_json = (repo_root / args.output_json).resolve()
    output_md = (repo_root / args.output_md).resolve()

    payload = run(repo_root, output_json, output_md)
    print(json.dumps(payload["summary"], indent=2))


if __name__ == "__main__":
    main()
