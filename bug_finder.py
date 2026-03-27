#!/usr/bin/env python3
"""
Automated Bug Finder & Updater Loop (2026)
- Runs tests on an interval
- Parses failures
- Requests AI patch suggestions
- Applies deterministic replacement patches
- Commits changes and can rollback if failures worsen
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional

import requests


@dataclass
class Config:
    project_path: Path
    check_interval: int = 300
    max_iterations: int = 50
    model: str = "gpt-4.1-mini"
    api_url: str = "https://api.openai.com/v1/responses"


@dataclass
class TestResult:
    return_code: int
    stdout: str
    stderr: str


def run_command(cmd: list[str], cwd: Path, check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=str(cwd), text=True, capture_output=True, check=check)


def run_tests(project_path: Path) -> TestResult:
    result = run_command(["pytest", "--maxfail=5", "--disable-warnings", "-q"], cwd=project_path)
    return TestResult(return_code=result.returncode, stdout=result.stdout, stderr=result.stderr)


def analyze_output(stdout: str, stderr: str) -> list[str]:
    issues: list[str] = []
    for line in (stdout.splitlines() + stderr.splitlines()):
        if "FAILED" in line or "ERROR" in line:
            issues.append(line.strip())
    return issues


def codex_patch(issue: str, cfg: Config) -> Optional[str]:
    api_key = os.getenv("OPENAI_API_KEY", "")
    if not api_key:
        print("[ERROR] OPENAI_API_KEY is not set. Skipping AI patch request.")
        return None

    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    prompt = (
        "You are a precise code-fix assistant.\n"
        f"Project path: {cfg.project_path}\n"
        f"Issue: {issue}\n\n"
        "Respond in this exact format for each replacement:\n"
        "FILE: <relative_path>\n"
        "OLD: <original literal text>\n"
        "NEW: <replacement literal text>\n"
    )
    payload = {
        "model": cfg.model,
        "input": prompt,
        "max_output_tokens": 1200,
        "temperature": 0,
    }

    try:
        response = requests.post(cfg.api_url, headers=headers, json=payload, timeout=45)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"[ERROR] OpenAI API request failed: {exc}")
        return None

    data = response.json()
    text_output = data.get("output_text")
    if text_output:
        print(f"[AI PATCH] Suggested fix:\n{text_output}")
        return text_output

    # fallback extraction
    try:
        fragments = []
        for item in data.get("output", []):
            for content in item.get("content", []):
                if content.get("type") in {"output_text", "text"}:
                    fragments.append(content.get("text", ""))
        patch = "\n".join(fragments).strip()
        if patch:
            print(f"[AI PATCH] Suggested fix:\n{patch}")
            return patch
    except Exception:
        pass

    print("[ERROR] API response did not include text output.")
    return None


def apply_patch_text(project_path: Path, patch_text: str) -> int:
    file_pattern = re.compile(r"^FILE:\s*(.+)$")
    old_pattern = re.compile(r"^OLD:\s*(.+)$")
    new_pattern = re.compile(r"^NEW:\s*(.+)$")

    current_file: Optional[Path] = None
    old_code: Optional[str] = None
    applied = 0

    for raw_line in patch_text.splitlines():
        line = raw_line.rstrip("\n")
        file_match = file_pattern.match(line)
        old_match = old_pattern.match(line)
        new_match = new_pattern.match(line)

        if file_match:
            rel = file_match.group(1).strip()
            target = (project_path / rel).resolve()
            try:
                target.relative_to(project_path.resolve())
            except ValueError:
                print(f"[WARNING] Skipping path traversal attempt: {target}")
                current_file = None
                continue
            current_file = target
            old_code = None
            continue

        if old_match:
            old_code = old_match.group(1)
            continue

        if new_match and current_file and old_code is not None:
            new_code = new_match.group(1)
            if not current_file.exists():
                print(f"[WARNING] Target file does not exist: {current_file}")
                old_code = None
                continue
            content = current_file.read_text(encoding="utf-8")
            if old_code not in content:
                print(f"[WARNING] OLD segment not found in {current_file}")
                old_code = None
                continue
            updated = content.replace(old_code, new_code, 1)
            current_file.write_text(updated, encoding="utf-8")
            applied += 1
            print(f"[PATCH APPLIED] {current_file}")
            old_code = None

    return applied


def commit_changes(project_path: Path) -> bool:
    run_command(["git", "add", "-A"], cwd=project_path)
    status = run_command(["git", "status", "--porcelain"], cwd=project_path)
    if not status.stdout.strip():
        print("[INFO] No changes to commit.")
        return False

    commit = run_command(["git", "commit", "-m", "Automated bug fix via AI loop"], cwd=project_path)
    if commit.returncode != 0:
        print(f"[ERROR] Commit failed:\n{commit.stderr}")
        return False

    push = run_command(["git", "push"], cwd=project_path)
    if push.returncode != 0:
        print(f"[WARNING] Push failed (continuing):\n{push.stderr}")
    return True


def rollback_last_commit(project_path: Path) -> None:
    reset = run_command(["git", "reset", "--hard", "HEAD~1"], cwd=project_path)
    if reset.returncode == 0:
        print("[ROLLBACK] Last commit reverted.")
        push = run_command(["git", "push", "--force-with-lease"], cwd=project_path)
        if push.returncode != 0:
            print(f"[WARNING] Force push failed:\n{push.stderr}")
    else:
        print(f"[ERROR] Rollback failed:\n{reset.stderr}")


def append_patch_log(project_path: Path, issue: str, patch: str) -> None:
    log_path = project_path / "codex_patch.log"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write("\n=== Issue ===\n")
        handle.write(issue)
        handle.write("\n=== Patch ===\n")
        handle.write(patch)
        handle.write("\n")


def main_loop(cfg: Config) -> None:
    for iteration in range(1, cfg.max_iterations + 1):
        print(f"\n[LOOP] Iteration {iteration}/{cfg.max_iterations}")
        before = run_tests(cfg.project_path)
        issues_before = analyze_output(before.stdout, before.stderr)

        if not issues_before:
            print("[CLEAN] No bugs detected.")
            time.sleep(cfg.check_interval)
            continue

        print(f"[BUGS FOUND] {len(issues_before)} issues detected.")
        for issue in issues_before:
            patch = codex_patch(issue, cfg)
            if patch:
                apply_patch_text(cfg.project_path, patch)
                append_patch_log(cfg.project_path, issue, patch)

        committed = commit_changes(cfg.project_path)
        if committed:
            after = run_tests(cfg.project_path)
            issues_after = analyze_output(after.stdout, after.stderr)
            if len(issues_after) > len(issues_before):
                print("[ROLLBACK TRIGGERED] Failures increased after patch.")
                rollback_last_commit(cfg.project_path)
            else:
                print("[PATCH SUCCESS] Failures improved or remained stable.")

        time.sleep(cfg.check_interval)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Automated bug finder and patch loop.")
    parser.add_argument("--project-path", default=str(Path.cwd()), help="Absolute path to project root.")
    parser.add_argument("--check-interval", type=int, default=300, help="Seconds between loop iterations.")
    parser.add_argument("--max-iterations", type=int, default=50, help="Max loop iterations.")
    parser.add_argument("--model", default="gpt-4.1-mini", help="OpenAI model name.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cfg = Config(
        project_path=Path(args.project_path).resolve(),
        check_interval=args.check_interval,
        max_iterations=args.max_iterations,
        model=args.model,
    )
    if not cfg.project_path.exists():
        raise SystemExit(f"Project path does not exist: {cfg.project_path}")
    main_loop(cfg)


if __name__ == "__main__":
    main()
