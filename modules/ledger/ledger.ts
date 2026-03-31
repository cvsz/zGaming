import { createHash } from "node:crypto";
import type { Pool, PoolClient } from "pg";

export interface LedgerTransferInput {
  userId: string;
  amount: string;
  currency: string;
  idempotencyKey: string;
  providerRef?: string;
  callbackPayloadHash?: string;
  maxAmount?: string;
}

export interface LedgerTransferResult {
  status: "applied" | "duplicate";
  ledgerHash: string;
}

export interface LedgerIntegrityIssue {
  userId: string;
  sequenceId: number;
  reason: "sequence_gap" | "prev_hash_mismatch" | "hash_mismatch";
}

const DEFAULT_MAX_TX_AMOUNT = "1000000.000000";
const SCALE = 6;

export async function transferWithIdempotency(
  pool: Pool,
  input: LedgerTransferInput,
): Promise<LedgerTransferResult> {
  const client = await pool.connect();

  try {
    await ensureCoreTables(client);

    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        return await transferOnce(client, input);
      } catch (error: any) {
        await safeRollback(client);
        if (isRetryableSerializationError(error) && attempt < 3) {
          continue;
        }
        throw error;
      }
    }

    throw new Error("ledger_transaction_retries_exhausted");
  } finally {
    client.release();
  }
}

export async function verifyLedgerIntegrity(pool: Pool, userId?: string): Promise<LedgerIntegrityIssue[]> {
  const client = await pool.connect();
  try {
    const query = userId
      ? `SELECT user_id, sequence_id, amount, ref_id, created_at, prev_hash, hash
           FROM ledger
          WHERE user_id = $1
          ORDER BY user_id, sequence_id`
      : `SELECT user_id, sequence_id, amount, ref_id, created_at, prev_hash, hash
           FROM ledger
          ORDER BY user_id, sequence_id`;

    const rows = (await client.query(query, userId ? [userId] : [])).rows;
    const issues: LedgerIntegrityIssue[] = [];

    let currentUser = "";
    let expectedSequence = 1;
    let lastHash = "0".repeat(64);

    for (const row of rows) {
      if (row.user_id !== currentUser) {
        currentUser = String(row.user_id);
        expectedSequence = 1;
        lastHash = "0".repeat(64);
      }

      if (Number(row.sequence_id) !== expectedSequence) {
        issues.push({
          userId: String(row.user_id),
          sequenceId: Number(row.sequence_id),
          reason: "sequence_gap",
        });
      }

      if (String(row.prev_hash) !== lastHash) {
        issues.push({
          userId: String(row.user_id),
          sequenceId: Number(row.sequence_id),
          reason: "prev_hash_mismatch",
        });
      }

      const expectedHash = computeLedgerChainHash({
        prevHash: String(row.prev_hash),
        userId: String(row.user_id),
        amount: String(row.amount),
        refId: String(row.ref_id),
        timestamp: new Date(row.created_at).toISOString(),
      });

      if (String(row.hash) !== expectedHash) {
        issues.push({
          userId: String(row.user_id),
          sequenceId: Number(row.sequence_id),
          reason: "hash_mismatch",
        });
      }

      lastHash = String(row.hash);
      expectedSequence = Number(row.sequence_id) + 1;
    }

    return issues;
  } finally {
    client.release();
  }
}

export async function getDerivedBalance(pool: Pool, userId: string): Promise<string> {
  const result = await pool.query(
    `SELECT COALESCE(SUM(CASE WHEN type='credit' THEN amount ELSE -amount END), 0)::text AS balance
       FROM ledger
      WHERE user_id = $1`,
    [userId],
  );

  return String(result.rows[0]?.balance ?? "0");
}

export function computeImmutableHash(input: LedgerTransferInput): string {
  const canonical = [
    "ledger-v2",
    input.userId,
    input.amount,
    input.currency,
    input.idempotencyKey,
    input.providerRef ?? "",
    input.callbackPayloadHash ?? "",
  ].join("|");

  return createHash("sha256").update(canonical).digest("hex");
}

function computeLedgerChainHash(input: {
  prevHash: string;
  userId: string;
  amount: string;
  refId: string;
  timestamp: string;
}): string {
  return createHash("sha256")
    .update(`${input.prevHash}${input.userId}${input.amount}${input.refId}${input.timestamp}`)
    .digest("hex");
}

async function transferOnce(client: PoolClient, input: LedgerTransferInput): Promise<LedgerTransferResult> {
  validateAmount(input.amount, input.maxAmount ?? DEFAULT_MAX_TX_AMOUNT);

  await client.query("BEGIN");
  await ensureSerializable(client);

  const immutableHash = computeImmutableHash(input);

  const existing = await client.query(
    `SELECT status, response_hash
       FROM idempotency_keys
      WHERE idempotency_key = $1
      FOR UPDATE`,
    [input.idempotencyKey],
  );

  if ((existing.rowCount ?? 0) > 0) {
    const status = String(existing.rows[0].status);
    if (status === "complete") {
      await client.query("COMMIT");
      return { status: "duplicate", ledgerHash: String(existing.rows[0].response_hash) };
    }
    throw new Error("idempotency_key_in_pending_state");
  }

  await client.query(
    `INSERT INTO idempotency_keys (idempotency_key, status)
     VALUES ($1, 'pending')`,
    [input.idempotencyKey],
  );

  const chainRow = await client.query(
    `SELECT COALESCE(MAX(sequence_id), 0) AS max_sequence,
            COALESCE((ARRAY_AGG(hash ORDER BY sequence_id DESC))[1], $2) AS last_hash
       FROM ledger
      WHERE user_id = $1
      FOR UPDATE`,
    [input.userId, "0".repeat(64)],
  );

  const sequenceId = Number(chainRow.rows[0].max_sequence) + 1;
  const prevHash = String(chainRow.rows[0].last_hash);
  const createdAt = new Date().toISOString();
  const chainHash = computeLedgerChainHash({
    prevHash,
    userId: input.userId,
    amount: input.amount,
    refId: input.providerRef ?? input.idempotencyKey,
    timestamp: createdAt,
  });

  const insertResult = await client.query(
    `INSERT INTO ledger (
       user_id, amount, currency, type, idempotency_key, provider_ref,
       callback_payload_hash, immutable_hash, sequence_id, prev_hash, hash, created_at
     )
     VALUES ($1, $2, $3, 'debit', $4, $5, $6, $7, $8, $9, $10, $11::timestamptz)
     RETURNING hash`,
    [
      input.userId,
      input.amount,
      input.currency,
      input.idempotencyKey,
      input.providerRef ?? null,
      input.callbackPayloadHash ?? null,
      immutableHash,
      sequenceId,
      prevHash,
      chainHash,
      createdAt,
    ],
  );

  const ledgerHash = String(insertResult.rows[0].hash);

  await client.query(
    `UPDATE idempotency_keys
        SET status = 'complete',
            response_hash = $2,
            updated_at = NOW()
      WHERE idempotency_key = $1`,
    [input.idempotencyKey, ledgerHash],
  );

  await client.query(
    `INSERT INTO audit_log (actor, action, payload_hash)
     VALUES ($1, $2, $3)`,
    [
      input.userId,
      "wallet_ledger_append",
      createHash("sha256")
        .update(JSON.stringify({
          userId: input.userId,
          amount: input.amount,
          currency: input.currency,
          idempotencyKey: input.idempotencyKey,
          sequenceId,
          hash: ledgerHash,
        }))
        .digest("hex"),
    ],
  );

  await client.query("COMMIT");
  return {
    status: "applied",
    ledgerHash,
  };
}

function validateAmount(amount: string, maxAmount: string): void {
  const parsed = Number(amount);
  const parsedMax = Number(maxAmount);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error("invalid_amount_non_positive");
  }
  if (parsed > parsedMax) {
    throw new Error("max_transaction_amount_exceeded");
  }
  if (decimalPlaces(amount) > SCALE) {
    throw new Error("invalid_amount_precision");
  }
}

function decimalPlaces(value: string): number {
  const idx = value.indexOf(".");
  return idx >= 0 ? value.length - idx - 1 : 0;
}

async function ensureCoreTables(client: PoolClient): Promise<void> {
  await client.query(`
    CREATE TABLE IF NOT EXISTS idempotency_keys (
      idempotency_key TEXT PRIMARY KEY,
      status TEXT NOT NULL CHECK (status IN ('pending','complete')),
      response_hash CHAR(64),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query(`
    CREATE TABLE IF NOT EXISTS audit_log (
      id BIGSERIAL PRIMARY KEY,
      actor TEXT NOT NULL,
      action TEXT NOT NULL,
      payload_hash CHAR(64) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await client.query("ALTER TABLE ledger ADD COLUMN IF NOT EXISTS sequence_id BIGINT");
  await client.query("ALTER TABLE ledger ADD COLUMN IF NOT EXISTS prev_hash CHAR(64)");
  await client.query("ALTER TABLE ledger ADD COLUMN IF NOT EXISTS hash CHAR(64)");
  await client.query("ALTER TABLE ledger ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()");
  await client.query("CREATE UNIQUE INDEX IF NOT EXISTS ledger_user_sequence_uniq ON ledger (user_id, sequence_id)");

  await client.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
          FROM pg_trigger
         WHERE tgname = 'ledger_immutable_update'
      ) THEN
        CREATE FUNCTION prevent_ledger_mutation() RETURNS trigger AS $fn$
        BEGIN
          RAISE EXCEPTION 'ledger is append-only';
        END;
        $fn$ LANGUAGE plpgsql;

        CREATE TRIGGER ledger_immutable_update BEFORE UPDATE ON ledger
        FOR EACH ROW EXECUTE FUNCTION prevent_ledger_mutation();
      END IF;

      IF NOT EXISTS (
        SELECT 1
          FROM pg_trigger
         WHERE tgname = 'ledger_immutable_delete'
      ) THEN
        CREATE TRIGGER ledger_immutable_delete BEFORE DELETE ON ledger
        FOR EACH ROW EXECUTE FUNCTION prevent_ledger_mutation();
      END IF;
    END;
    $$;
  `);
}

async function ensureSerializable(client: PoolClient): Promise<void> {
  await client.query("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
}

async function safeRollback(client: PoolClient): Promise<void> {
  try {
    await client.query("ROLLBACK");
  } catch {
    // no-op
  }
}

function isRetryableSerializationError(error: any): boolean {
  const code = String(error?.code ?? "");
  return code === "40001" || code === "40P01";
}
