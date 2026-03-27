# zGaming Clean Installer + Ultra Meta Integration (2026)

## Objective
Deliver a deterministic, reproducible, compliance-oriented installer workflow that combines the existing phase-based Meta-Master platform with an operator-friendly one-click installer.

## Architecture

1. **Installer Control Layer**
   - `installer/zgaming-ultra-installer.sh`
   - Entry modes: `quick`, `full`, `diagnostics`, `audit`, `menu`
2. **Platform Execution Layer**
   - `generator/meta-master.sh`
   - Reused from existing phase orchestrator
3. **Evidence Layer**
   - `installer/artifacts/repo-manifest.sha256`
   - `installer/artifacts/sbom-lite.spdx.json`
   - `installer/reports/compliance-report.json`
   - JSONL structured logs in `installer/reports/`

## Pseudo-code

```text
main(command):
  print banner
  dispatch by mode

run_quick():
  require core binaries
  validate runtime and repository shape
  run meta-master doctor
  hash all repository files into manifest
  execute baseline compliance checks
  create SPDX-lite SBOM

run_full():
  run_quick
  run meta-master installer pipeline
  run container/network diagnostics

run_audit():
  manifest + compliance + SBOM only
```

## Security and Compliance Controls

- Strict shell safety (`set -Eeuo pipefail`, safe IFS)
- Deterministic hashing of repository files for auditability
- Structured JSONL logs for ingestion by SIEM/GRC tools
- Baseline checks for strict shell usage and critical platform files
- SBOM-lite generation (SPDX-2.3 JSON schema style)

## Operational Commands

```bash
# Baseline + artifacts
./installer/zgaming-ultra-installer.sh quick

# Full platform install + diagnostics
./installer/zgaming-ultra-installer.sh full

# Integrate through existing meta-master command
./generator/meta-master.sh clean-installer full
```

## Release Artifacts Produced

- `installer/artifacts/repo-manifest.sha256`
- `installer/artifacts/sbom-lite.spdx.json`
- `installer/reports/compliance-report.json`
- `installer/reports/install-<timestamp>.jsonl`

## CI/CD Integration Notes

Recommended pipeline stages:
1. `bash -n installer/zgaming-ultra-installer.sh`
2. `./installer/zgaming-ultra-installer.sh audit`
3. Upload artifacts (`manifest`, `SBOM`, `compliance`) as immutable build evidence.
