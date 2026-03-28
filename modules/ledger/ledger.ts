import { createHash } from "node:crypto";
import type { Pool, PoolClient } from "pg";

export interface LedgerTransferInput {
  userId: string;
  amount: string;
  currency: string;
  idempotencyKey: string;
  providerRef?: string;
  callbackPayloadHash?: string;
}

export interface LedgerTransferResult {
  status: "applied" | "duplicate";
  ledgerHash: string;
}

export async function transferWithIdempotency(
  pool: Pool,
  input: LedgerTransferInput,
): Promise<LedgerTransferResult> {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");
    await ensureSerializable(client);

    const existed = await client.query(
      "SELECT immutable_hash FROM ledger WHERE idempotency_key = $1 LIMIT 1",
      [input.idempotencyKey],
    );

    if (existed.rowCount && existed.rowCount > 0) {
      await client.query("COMMIT");
      return {
        status: "duplicate",
        ledgerHash: String(existed.rows[0].immutable_hash),
      };
    }

    const immutableHash = computeImmutableHash(input);

    await client.query(
      `INSERT INTO ledger (user_id, amount, currency, type, idempotency_key, provider_ref, callback_payload_hash, immutable_hash)
       VALUES ($1, $2, $3, 'debit', $4, $5, $6, $7)`,
      [
        input.userId,
        input.amount,
        input.currency,
        input.idempotencyKey,
        input.providerRef ?? null,
        input.callbackPayloadHash ?? null,
        immutableHash,
      ],
    );

    await client.query(
      `INSERT INTO ledger_audit_log (idempotency_key, event_type, event_payload)
       VALUES ($1, 'ledger_transfer_applied', $2::jsonb)`,
      [
        input.idempotencyKey,
        JSON.stringify({
          userId: input.userId,
          amount: input.amount,
          currency: input.currency,
          providerRef: input.providerRef ?? null,
          immutableHash,
        }),
      ],
    );

    await client.query("COMMIT");
    return {
      status: "applied",
      ledgerHash: immutableHash,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export function computeImmutableHash(input: LedgerTransferInput): string {
  const canonical = [
    "ledger-v1",
    input.userId,
    input.amount,
    input.currency,
    input.idempotencyKey,
    input.providerRef ?? "",
    input.callbackPayloadHash ?? "",
  ].join("|");

  return createHash("sha256").update(canonical).digest("hex");
}

async function ensureSerializable(client: PoolClient): Promise<void> {
  await client.query("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
}
