# Codex Master Meta Fully Advanced Professional Prompt Template (2026)

> เอกสารนี้เป็น Prompt Template มาตรฐานสำหรับงานสร้างระบบแบบ production-grade ในปี 2026 โดยเน้น deterministic delivery, security-first architecture และ compliance-ready execution.

## 1) Context

ระบุข้อมูลพื้นฐานของงานให้ครบก่อนเริ่ม implement:

- ประเภทงาน (platform, automation, data pipeline, DevSecOps, AI integration)
- เทคโนโลยีหลัก (เช่น Bash/Python/Go/Rust + Docker/Kubernetes)
- บริบทการทำงาน (local, on-prem, hybrid cloud, multi-cloud)
- เป้าหมายเชิงธุรกิจ (time-to-market, reliability, auditability, margin)
- ข้อจำกัด compliance/security (GDPR, Zero Trust, internal policy)

แนวทางปี 2026:

- AI-driven automation
- Cloud-native orchestration
- Compliance-ready workflows (ISO/IEC-aligned control sets, GDPR update-ready)

---

## 2) Objective

สร้างโค้ด/สคริปต์/ระบบที่:

1. deterministic, reproducible, production-ready
2. รองรับ cross-platform automation (Linux, Windows, macOS, cloud-native)
3. รวม infrastructure hardening (VPN, DNS, firewall, NTP, Zero Trust, compliance checks)
4. เชื่อม source control workflows (Git/GitHub/Gitea) พร้อม robust error handling, autoheal, rollback
5. มี installer system แบบ one-click + menu-driven automation
6. รองรับ modular packaging และ versioning (changelog, README, release tags, reproducible builds, zip)
7. integrate AI/ML modules (transformers, deep learning, analytics optimization, generative automation)
8. มี structured reporting และ metadata extraction สำหรับ audit
9. deploy ผ่าน CI/CD ที่ scale ได้ (Docker, Kubernetes, Cloudflare, serverless)
10. สอดคล้อง 2026 best practices: secure supply chain, SBOM, automated compliance validation

---

## 3) Requirements

- ใช้ภาษาหลัก: `[ระบุภาษา]` (สามารถผสมภาษาอื่นเพื่อ integration ได้)
- มี structured logging และ metadata extraction
- มี stepwise diagnostics ครอบคลุม container/cloud/network stack
- มี pseudo-code workflow ก่อน implement จริง
- ออกแบบให้ compliance-ready สำหรับ business workflows
- ใช้ security-first approach (input validation, error handling, data protection)
- modularized architecture ที่ refactor/extend ได้ง่าย
- รองรับ DevSecOps 2026 และ automated vulnerability scanning

---

## 4) Deliverables

1. **Code Implementation**: สคริปต์หลัก + โมดูลเสริม
2. **Documentation**: README + stepwise guide + architecture notes
3. **Release Artifacts**: changelog, version tags, reproducible builds, zip package
4. **Validation Scripts**: reproducibility test, autoheal test, compliance checks, SBOM validation
5. **Diagram/Workflow**: architecture, data flow, CI/CD integration
6. **Audit Report**: structured metadata extraction สำหรับ compliance/reproducibility
7. **Security Checklist**: hardening controls + vulnerability scanning coverage

---

## 5) Style & Constraints

- โค้ดต้อง production-grade, scalable, compliance-ready
- ใช้ modular functions + naming convention ที่ชัดเจน
- ต้องมี comprehensive error handling ทุก critical step
- ต้องมี documentation และ release process ที่ reproducible
- ต้องมี security hardening + compliance validation โดยอัตโนมัติ
- รองรับการ extend/refactor โดยไม่กระทบระบบหลัก
- สอดคล้องมาตรฐานปี 2026: AI ethics, secure supply chain, automated compliance

---

## 6) Pseudo-Code Workflow (Template)

```text
INPUT: project_context, objective, constraints, target_platforms
OUTPUT: production-grade implementation + evidence artifacts

1) Validate Context
   - parse business goals
   - parse compliance/security requirements
   - define deterministic acceptance criteria

2) Design Architecture
   - define modules, interfaces, and trust boundaries
   - map CI/CD + release controls + rollback strategy
   - map observability (logs, metrics, traces, metadata)

3) Plan Security & Compliance
   - create control matrix (input validation, IAM, encryption, secrets, audit logs)
   - generate SBOM and vulnerability gates
   - define policy-as-code checks

4) Implement in Phases
   - scaffold core modules
   - add diagnostics and structured logging
   - add installer + platform-specific adapters
   - add resilience patterns (retry, idempotency, circuit breaker)

5) Verify Determinism
   - run reproducibility tests
   - run integration and failure-injection checks
   - verify rollback and autoheal flows

6) Package & Release
   - generate changelog/version tags/artifacts
   - sign and checksum release bundle
   - publish audit report + compliance evidence

7) Operate & Improve
   - monitor production signals
   - feed analytics/AI optimization loop
   - iterate with controlled change management
```

---

## 7) Ready-to-Use Prompt Block

```text
[Context]
<ใส่บริบทโปรเจกต์/ทีม/ข้อจำกัด>

[Objective]
ออกแบบและ implement ระบบให้ deterministic, reproducible, production-ready
พร้อมรองรับ cross-platform automation, infrastructure hardening,
source control integration, installer automation, modular packaging,
AI/ML integration, structured reporting, CI/CD orchestration,
และ 2026 best practices (secure supply chain, SBOM, compliance automation)

[Requirements]
- Primary language: <Bash|Python|Go|Rust>
- Structured logging + metadata extraction
- Stepwise diagnostics (container/cloud/network)
- Pseudo-code workflow before implementation
- Compliance-ready + security-first design
- Refactor-friendly modular architecture
- DevSecOps 2026 + automated vulnerability scanning

[Deliverables]
1) Code implementation
2) README + architecture docs
3) Release artifacts (changelog/tags/reproducible builds/zip)
4) Validation scripts (reproducibility, autoheal, compliance, SBOM)
5) Diagram/workflow (architecture + CI/CD)
6) Audit report (structured metadata)
7) Security checklist

[Style & Constraints]
- Production-grade, scalable, compliance-ready
- Explicit error handling and secure defaults
- Deterministic release process
- Easy extension/refactoring
```

---

## 8) Example Task Prompts

- สร้าง installer ที่ตรวจสอบ OS, ติดตั้ง dependencies, ตั้งค่า firewall และ deploy container stack
- สร้าง AI/ML module สำหรับ intent recognition และ analytics-driven optimization
- ออกแบบ workflow diagram เชื่อม source control → CI/CD → deployment environment
- สร้าง validation scripts สำหรับ autoheal, reproducibility, และ SBOM compliance
- สร้าง structured reporting สำหรับ metadata extraction และ compliance audit
- ออกแบบ secure DevOps pipeline ที่บังคับ vulnerability scanning และ Zero Trust controls
