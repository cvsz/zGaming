import type { Pool, PoolClient } from "pg";

export interface LedgerTransferInput {
  userId: string;
  amount: string;
  currency: string;
  idempotencyKey: string;
}

export async function transferWithIdempotency(pool: Pool, input: LedgerTransferInput): Promise<void> {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");
    await ensureSerializable(client);

    const existed = await client.query("SELECT 1 FROM ledger WHERE idempotency_key = $1", [input.idempotencyKey]);
    if (existed.rowCount && existed.rowCount > 0) {
      await client.query("ROLLBACK");
      return;
    }

    await client.query(
      `INSERT INTO ledger (user_id, amount, currency, type, idempotency_key)
       VALUES ($1, $2, $3, 'debit', $4)`,
      [input.userId, input.amount, input.currency, input.idempotencyKey],
    );

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function ensureSerializable(client: PoolClient): Promise<void> {
  await client.query("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
}
