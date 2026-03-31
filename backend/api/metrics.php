<?php

declare(strict_types=1);

require_once __DIR__ . '/../lib/Database.php';

header('Content-Type: text/plain; version=0.0.4; charset=utf-8');

$db = Database::conn();
$pendingSettlements = (int)($db->query("SELECT COUNT(*) FROM settlement_queue WHERE status='pending'")->fetchColumn() ?: 0);
$failedSettlements = (int)($db->query("SELECT COUNT(*) FROM settlement_queue WHERE status='failed'")->fetchColumn() ?: 0);
$pendingWithdrawals = (int)($db->query("SELECT COUNT(*) FROM withdrawal_queue WHERE status IN ('pending','processing')")->fetchColumn() ?: 0);
$amlOpenFlags = (int)($db->query("SELECT COUNT(*) FROM aml_flags WHERE created_at >= UTC_TIMESTAMP() - INTERVAL 24 HOUR")->fetchColumn() ?: 0);
$reconOpen = (int)($db->query("SELECT COUNT(*) FROM reconciliation_report WHERE status='open'")->fetchColumn() ?: 0);

echo "# HELP zgaming_settlement_pending Settlement queue pending jobs\n";
echo "# TYPE zgaming_settlement_pending gauge\n";
echo "zgaming_settlement_pending {$pendingSettlements}\n";
echo "# HELP zgaming_settlement_failed Settlement queue failed jobs\n";
echo "# TYPE zgaming_settlement_failed gauge\n";
echo "zgaming_settlement_failed {$failedSettlements}\n";
echo "# HELP zgaming_withdrawal_pending Pending/processing withdrawals\n";
echo "# TYPE zgaming_withdrawal_pending gauge\n";
echo "zgaming_withdrawal_pending {$pendingWithdrawals}\n";
echo "# HELP zgaming_aml_flags_24h AML flags in last 24h\n";
echo "# TYPE zgaming_aml_flags_24h gauge\n";
echo "zgaming_aml_flags_24h {$amlOpenFlags}\n";
echo "# HELP zgaming_reconciliation_open Open reconciliation mismatches\n";
echo "# TYPE zgaming_reconciliation_open gauge\n";
echo "zgaming_reconciliation_open {$reconOpen}\n";
