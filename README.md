# 🎰 Meta-Master Casino Platform

**Production-grade Casino Platform Generator**
Built with **Bash + PHP + React + Docker + Kubernetes**

> ไม่ใช่แค่ deploy ได้
> แต่ **สร้างซ้ำได้ / audit ได้ / คุมเงินจริงได้**

---

## 📌 High-Level Overview

Meta-Master คือ **Platform Generator**
ไม่ใช่ repo ธรรมดา

มันทำหน้าที่:

* สร้าง backend / frontend / infra
* บังคับโครงสร้าง production
* ป้องกันเงินจริงพังจาก callback / retry / fraud
* แพ็ก release พร้อม checksum + signature

---

## 🧱 Architecture (Logical)

```
┌─────────────┐
│  Frontend   │  React (Player / Admin)
└─────┬───────┘
      │ JWT
┌─────▼───────┐
│   Backend   │  PHP (Wallet / Auth / Providers)
└─────┬───────┘
      │ Atomic TX
┌─────▼───────┐
│   Database  │  MySQL (Ledger / Audit)
└─────┬───────┘
      │ Callback
┌─────▼───────┐
│ Game Provider│ Pragmatic / PG Soft
└─────────────┘
```

Infra:

* Docker / Docker Compose
* NGINX reverse proxy
* Cloudflare (HTTPS / WAF)
* Kubernetes (Helm / multi-env)

---

## 📂 Repository Structure

```
zGaming/
├── backend/              # PHP backend (wallet, auth, callbacks)
├── frontend-player/      # React player UI
├── frontend-admin/       # React admin UI
├── nginx/                # NGINX reverse proxy
├── k8s/                  # Kubernetes manifests (Helm / Kustomize)
├── generator/
│   ├── meta-master.sh    # Master controller
│   ├── phases/           # Phase-by-phase generators
│   └── lib/assert.sh     # Environment guard
├── docker-compose.yml
└── README.md
```

---

## 🧠 Meta-Master Concept

ทุกอย่างถูกแบ่งเป็น **Phase**
แต่ละ phase:

* deterministic (รันซ้ำได้)
* fail-fast
* audit-friendly

### Phase Map

| Phase | Description                     |
| ----- | ------------------------------- |
| 00    | Guard / Env validation          |
| 10    | Backend core                    |
| 20    | Auth / JWT / Roles              |
| 30    | Wallet / Ledger                 |
| 40    | Provider launch                 |
| 50    | Provider callbacks (idempotent) |
| 60    | Frontend (Player / Admin)       |
| 70    | NGINX reverse proxy             |
| 80    | Security hardening              |
| 90    | Cloudflare / HTTPS              |
| 95    | Kubernetes (Helm, multi-env)    |
| 99    | Final release / signing         |

---

## ⚙️ Requirements

ขั้นต่ำ:

* Linux / WSL2 (Ubuntu 22.04+)
* Docker ≥ 25
* Docker Compose v2
* OpenSSL
* Bash ≥ 5

ตรวจสอบ environment:

```bash
./generator/meta-master.sh doctor
```

โหมดการรันหลัก:

```bash
./generator/meta-master.sh all
./generator/meta-master.sh final   # alias ของ all
./generator/meta-master.sh installer
./generator/meta-master.sh upgrade
./generator/meta-master.sh test    # run phase 110 (go-live test/report)
./generator/meta-master.sh list
./generator/meta-master.sh status
./generator/meta-master.sh phase 60-frontend.sh
```
รองรับการ run แบบช่วง phase (resume/retry-safe):

```bash
MM_FROM_PHASE=60-frontend.sh ./generator/meta-master.sh upgrade
MM_FROM_PHASE=90-cloudflare.sh MM_TO_PHASE=99-release.sh ./generator/meta-master.sh all
```

---

## 🚀 Quick Start (From Zero)

```bash
git clone <repo>
cd zGaming

chmod +x generator/meta-master.sh
./generator/meta-master.sh all
```

สิ่งที่เกิดขึ้น:

* Generate code ทุกส่วน
* Build frontend / backend
* เตรียม infra
* Pack release

---

## ▶️ Development Run (Docker)

```bash
docker compose up -d --build
```

Access:

* Player UI → [http://localhost/](http://localhost/)
* Admin UI → [http://localhost/admin](http://localhost/admin)
* API → [http://localhost/api/](http://localhost/api/)

---

## 🔐 Authentication

* JWT (HMAC-SHA256)
* Roles: `player`, `admin`
* Audit log ทุก login

Login API:

```
POST /api/login.php
```

Header:

```
Authorization: Bearer <JWT>
```

---

## 💰 Wallet System

* Atomic DB transaction
* Ledger-based (ไม่ update balance ตรง)
* Idempotent provider callbacks
* Double callback safe

> เงินไม่หาย แม้ provider ยิงซ้ำ

---

## 🎮 Provider Integration

รองรับ:

* Pragmatic Play
* PG Soft

คุณสมบัติ:

* Signature verification
* Unique transaction guard
* Retry / timeout safe
* Provider-specific response mapping

---

## 🌐 Frontend

### Player

* Login
* Lobby
* Game launcher (iframe)

### Admin

* User list
* Wallet overview
* Audit-ready

Build ด้วย:

* React 18
* Vite
* Static serving via NGINX

---

## 🛡 Security

* OWASP baseline
* Rate limiting (NGINX)
* JWT validation
* Secret validation (assert)
* Cloudflare WAF ready

---

## ☁️ Cloudflare

รองรับ:

* HTTPS (Full / Strict)
* Origin IP allowlist
* WAF rules
* Rate limiting

Config:

```
cloudflare/
```

---

## ☸ Kubernetes (Production)

* Helm chart
* Multi-env (`dev / staging / prod`)
* ConfigMap / Secret separation
* Health check + readiness

Deploy ตัวอย่าง:

```bash
helm install casino k8s/helm/casino -f values-prod.yaml
```

---

## 📦 Release Process (Phase 99)

Phase 99 จะ:

* Build immutable artifacts
* Export Docker images
* Create source archive
* Generate `SHA256SUMS`
* Sign release
* Pack ZIP สำหรับ handover

Verify:

```bash
openssl dgst -sha256 \
  -verify release.pub \
  -signature SHA256SUMS.sig \
  SHA256SUMS
```

---

## 🧾 Compliance & Audit

รองรับ:

* Auth audit
* Wallet ledger
* Provider callback log
* Traceable transaction ID

เหมาะกับ:

* Regulator
* Investor due-diligence
* Internal audit

---

## 🧪 Chaos / Failure Handling

ออกแบบให้รับมือ:

* Double callback
* Retry storm
* Provider latency
* Partial failure

(Phase Chaos สามารถเพิ่มได้)

---

## 🏁 Philosophy

> Casino system **ไม่พังเพราะ code สวย**
> แต่พังเพราะ **state + money + callback**

Meta-Master ถูกออกแบบมาเพื่อ:

* คุม state
* คุมเงินจริง
* คุมความซับซ้อน

---

## 📬 Next Extensions

ถ้าต้องการ:

* Multi-currency / FX
* Live reconciliation
* DR / backup / restore
* ISO27001 / PCI mapping
* Chaos testing phase

สามารถต่อ phase เพิ่มได้ทันที

---

**Meta-Master Casino Platform**
Built to survive production, not demos.
