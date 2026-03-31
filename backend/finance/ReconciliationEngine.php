<?php

declare(strict_types=1);

final class ReconciliationEngine
{
    public function __construct(private readonly PDO $db)
    {
    }

    public function runForDate(string $date): void
    {
        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'missing_internal', p.external_id, p.provider,
              JSON_OBJECT('psp_amount', p.amount, 'tx_timestamp', p.tx_timestamp)
            FROM psp_transactions p
            LEFT JOIN internal_transactions i ON i.external_id = p.external_id
            WHERE DATE(p.tx_timestamp)=? AND i.id IS NULL")
            ->execute([$date, $date]);

        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'amount_mismatch', p.external_id, p.provider,
              JSON_OBJECT('psp_amount', p.amount, 'internal_amount', i.amount)
            FROM psp_transactions p
            JOIN internal_transactions i ON i.external_id = p.external_id
            WHERE DATE(p.tx_timestamp)=? AND i.amount <> p.amount")
            ->execute([$date, $date]);

        $this->db->prepare("INSERT INTO reconciliation_report (report_date, mismatch_type, external_id, provider, details)
            SELECT ?, 'duplicate', external_id, provider,
              JSON_OBJECT('duplicate_count', COUNT(*))
            FROM psp_transactions
            WHERE DATE(tx_timestamp)=?
            GROUP BY external_id, provider
            HAVING COUNT(*) > 1")
            ->execute([$date, $date]);
    }
}
