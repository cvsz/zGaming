# 🧨 PENETRATION TEST CHECKLIST — zGaming

## 🎯 GOAL

Simulate real attackers targeting:

- money flows
- wallet integrity
- API security

## 💸 WALLET ATTACKS

### Double Spend
- send 10 concurrent debit requests
- verify balance never goes negative

### Replay Attack
- reuse same `ref_id`
- expect rejection

### Race Condition
- parallel credits/debits
- verify consistency

## 🔐 AUTH ATTACKS

### JWT Forgery
- modify payload
- test signature validation

### Expired Token
- replay expired token

## 🔁 WEBHOOK ATTACKS

### Replay
- resend same callback

### Signature Bypass
- modify payload without updating signature

### Timestamp Attack
- send old request (>5 min)

## 🎲 RNG ATTACKS

### Predictability
- attempt to derive `server_seed`

### Manipulation
- alter `client_seed`

## 🧾 LEDGER INTEGRITY

### Tampering
- modify DB row manually
- run audit verification

Expected:

- hash mismatch detected

## 🔄 SETTLEMENT QUEUE

### Duplicate Execution
- crash worker mid-process
- ensure no double processing

## 🌍 INFRA ATTACKS

### Open Ports
- scan exposed services

### DB Exposure
- ensure MySQL not public

## 🚨 DOS TEST

- flood API with requests
- verify rate limiting and stability

## 🧠 FRAUD TESTS

- rapid deposits/withdrawals
- large abnormal bets

Expected:

- AML flag triggered

## ✅ PASS CRITERIA

System must:

- never lose money
- never allow duplicate transactions
- detect tampering
- reject invalid auth
- survive concurrency
