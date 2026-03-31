<?php

declare(strict_types=1);

require_once __DIR__ . '/../backend/lib/Database.php';

$db = Database::conn();
$sql = "SELECT w.user_id, w.balance AS wallet_balance, COALESCE(SUM(CASE WHEN i.tx_type='deposit' THEN i.amount WHEN i.tx_type='payout' THEN i.amount WHEN i.tx_type='withdrawal' THEN -i.amount WHEN i.tx_type='bet' THEN -i.amount ELSE 0 END),0) AS ledger_balance_delta FROM wallets w LEFT JOIN internal_transactions i ON i.user_id = w.user_id GROUP BY w.user_id HAVING wallet_balance <> ledger_balance_delta";
$rows = $db->query($sql)->fetchAll();
if ($rows === []) {
    echo "reconciliation_status=pass mismatches=0\n";
    exit(0);
}

echo json_encode(['reconciliation_status' => 'fail', 'mismatches' => count($rows), 'rows' => $rows], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR) . "\n";
exit(2);
