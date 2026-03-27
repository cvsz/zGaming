# Changelog

## 2026-03-27

### Added
- Added `installer/zgaming-ultra-installer.sh` as a deterministic clean installer with quick/full/diagnostics/audit/menu workflows.
- Added repository-wide metadata hashing manifest generation and structured JSONL installer logging.
- Added compliance baseline report generation and SPDX-lite SBOM artifact generation.
- Added `docs/clean-installer-ultra-meta-2026.md` documenting architecture, pseudo-code workflow, and CI/CD integration.

### Changed
- Updated `generator/meta-master.sh` with a `clean-installer` command to execute the new installer in integrated mode.
- Updated `README.md` with clean installer usage, outputs, and pseudo-workflow.
