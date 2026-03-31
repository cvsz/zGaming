# Final Codex Prompts — zGaming

## 1) Red Team Attack Simulation

```text
You are a red team security engineer specializing in:
- fintech systems
- crypto wallets
- gambling platforms

Target system: "zGaming"

--------------------------------------------------
🎯 OBJECTIVE
--------------------------------------------------

Simulate REAL attacks against the system and produce:

1. Step-by-step exploit scenarios
2. Example attack scripts (curl / bash / pseudo)
3. Expected system failure points
4. Defensive patches (git diff)

--------------------------------------------------
⚠️ RULES
--------------------------------------------------

- Focus ONLY on realistic, high-impact attacks
- No theoretical vulnerabilities
- No generic advice
- Every attack must include:
  - exact steps
  - payload examples
  - expected result

--------------------------------------------------
🎯 ATTACK SURFACES

Cover ALL:

1. Wallet system
2. Ledger integrity
3. Settlement queue
4. JWT authentication
5. Webhooks / callbacks
6. Admin APIs
7. RNG / provably fair
8. Docker / infra exposure

--------------------------------------------------
🧨 REQUIRED ATTACKS

### 1. DOUBLE-SPEND ATTACK
- concurrent requests
- race condition exploitation

### 2. REPLAY ATTACK
- reuse transaction IDs
- bypass idempotency

### 3. WEBHOOK FORGERY
- fake provider callback
- signature bypass

### 4. JWT FORGERY / BYPASS
- tamper token
- impersonate admin

### 5. QUEUE DUPLICATION
- force worker retry
- cause double payout

### 6. LEDGER TAMPERING
- simulate DB manipulation
- test audit detection

### 7. HOT WALLET DRAIN
- repeated withdrawals
- bypass limits

### 8. RNG MANIPULATION
- predict outcomes
- exploit seed reuse

--------------------------------------------------
📦 OUTPUT FORMAT

For EACH attack:

## ATTACK NAME

### Steps
(step-by-step)

### Exploit Script
(real commands)

### Expected Result

### Root Cause

### Patch (git diff)

--------------------------------------------------
🎯 END GOAL

Break the system like a real attacker would,
then show how to fix it.

Start now.
```

## 2) Cost-Optimized AWS Architecture

```text
You are a cloud architect optimizing infrastructure for:

- fintech startup
- real-money gaming platform
- high reliability with minimal cost

System: "zGaming"

--------------------------------------------------
🎯 OBJECTIVE
--------------------------------------------------

Design a **cost-optimized AWS architecture** that:

- supports production safely
- minimizes monthly cost
- scales gradually

--------------------------------------------------
⚠️ CONSTRAINTS

- Budget-conscious (early-stage startup)
- Must still be secure and compliant-ready
- Avoid overengineering (no unnecessary services)

--------------------------------------------------
🏗️ REQUIREMENTS

Include:

1. Compute layer
2. Database
3. Networking
4. Secrets management
5. Logging / monitoring
6. Backup strategy
7. Multi-region strategy (minimal cost version)

--------------------------------------------------
💡 OPTIMIZATION TARGETS

Reduce cost for:

- compute (EC2 vs ECS vs Lambda)
- database (RDS vs alternatives)
- storage
- logs (CloudWatch cost control)

--------------------------------------------------
🔐 SECURITY REQUIREMENTS

- private subnets for DB
- no public DB access
- IAM least privilege
- KMS usage

--------------------------------------------------
📦 OUTPUT FORMAT

## ARCHITECTURE DIAGRAM (text)

## COMPONENTS

For each:
- service
- purpose
- monthly cost estimate

## COST BREAKDOWN

- total estimated monthly cost
- scaling cost projections

## OPTIMIZATION STRATEGIES

- what to upgrade later
- what NOT to use yet

## TERRAFORM PATCHES

(minimal viable infra)

--------------------------------------------------
🎯 END GOAL

Provide a production-safe architecture under:

👉 ~$100–300/month starting cost

Start now.
```

## 3) Production SLO/SLA Design

```text
You are a site reliability engineer (SRE) designing:

- SLO (Service Level Objectives)
- SLA (Service Level Agreements)

for a real-money platform: "zGaming"

--------------------------------------------------
🎯 OBJECTIVE
--------------------------------------------------

Define measurable reliability targets and enforcement strategy.

--------------------------------------------------
📊 SERVICES TO COVER

- API gateway
- wallet service
- settlement engine
- database
- authentication
- KYC/AML services

--------------------------------------------------
📏 DEFINE SLOs

For each service:

- availability (e.g. 99.9%)
- latency (p95 / p99)
- error rate

--------------------------------------------------
💥 ERROR BUDGETS

Define:

- acceptable failure thresholds
- burn rate alerts

--------------------------------------------------
🚨 SLA (USER-FACING)

Define:

- uptime guarantees
- financial guarantees (if applicable)
- response times

--------------------------------------------------
📈 MONITORING

Define metrics:

- request rate
- failure rate
- latency
- queue backlog
- reconciliation mismatch

--------------------------------------------------
🚨 ALERTING

Define alerts for:

- high error rate
- wallet inconsistencies
- settlement failures
- fraud spikes

--------------------------------------------------
🔁 INCIDENT POLICY

Define:

- response time (P0/P1/P2)
- escalation rules
- communication plan

--------------------------------------------------
📦 OUTPUT FORMAT

## SLO TABLE

(service → metrics)

## SLA DEFINITION

(user-facing guarantees)

## ERROR BUDGET POLICY

## ALERTING RULES

## INCIDENT RESPONSE FLOW

## DASHBOARD DESIGN

--------------------------------------------------
🎯 END GOAL

Create a system that is:

- measurable
- enforceable
- reliable under real money load

Start now.
```
