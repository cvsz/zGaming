#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 36] LIVE FX FEED – ECB / FIXER"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{fx,cron}

# ============================================================
# 1. FX Provider Config
# ============================================================

cat > "$BACKEND/fx/providers.php" <<'PHP'
<?php
return [
  'ecb' => [
    'url' => 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
    'base' => 'EUR'
  ],
  'fixer' => [
    'url' => 'https://data.fixer.io/api/latest',
    'base' => 'EUR',
    'key'  => getenv('FIXER_API_KEY')
  ]
];
PHP

# ============================================================
# 2. FX Fetcher (ECB + Fixer)
# ============================================================

cat > "$BACKEND/fx/fetch.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

$providers = require __DIR__ . '/providers.php';
$db = Database::conn();

function insertRate($base,$quote,$rate,$source) {
  global $db;
  $db->prepare(
    "INSERT INTO fx_rates (base,quote,rate,source)
     VALUES (?,?,?,?)"
  )->execute([$base,$quote,$rate,$source]);
}

/* ================= ECB ================= */
$xml = @simplexml_load_file($providers['ecb']['url']);
if ($xml) {
  foreach ($xml->Cube->Cube->Cube as $c) {
    $quote = (string)$c['currency'];
    $rate  = (float)$c['rate'];
    insertRate('EUR',$quote,$rate,'ecb');
  }
}

/* ================= FIXER ================= */
$key = $providers['fixer']['key'];
if ($key) {
  $json = @file_get_contents(
    $providers['fixer']['url']."?access_key=$key"
  );
  if ($json) {
    $data = json_decode($json,true);
    foreach ($data['rates'] ?? [] as $quote=>$rate) {
      insertRate('EUR',$quote,$rate,'fixer');
    }
  }
}

echo "FX fetch complete\n";
PHP

# ============================================================
# 3. FX Normalizer (Convert EUR → BASE_CURRENCY)
# ============================================================

cat > "$BACKEND/fx/normalize.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

$base = getenv('BASE_CURRENCY') ?: 'USD';
$db = Database::conn();

/*
  Strategy:
  - All feeds come as EUR/XXX
  - Convert to BASE/XXX using EUR/BASE
*/

$eurBase = $db->query(
  "SELECT rate FROM fx_rates
   WHERE base='EUR' AND quote='$base'
   ORDER BY valid_from DESC LIMIT 1"
)->fetchColumn();

if (!$eurBase) {
  throw new RuntimeException("Missing EUR/$base rate");
}

$rows = $db->query(
  "SELECT quote,rate FROM fx_rates
   WHERE base='EUR'
   ORDER BY valid_from DESC"
)->fetchAll();

foreach ($rows as $r) {
  $rate = $r['rate'] / $eurBase;
  $db->prepare(
    "INSERT INTO fx_rates (base,quote,rate,source)
     VALUES (?,?,?,'normalized')"
  )->execute([$base,$r['quote'],$rate]);
}

echo "FX normalized to $base\n";
PHP

# ============================================================
# 4. FX Sanity Check (Outlier Detection)
# ============================================================

cat > "$BACKEND/fx/validate.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

$db = Database::conn();

$rows = $db->query(
  "SELECT base,quote,rate FROM fx_rates
   ORDER BY valid_from DESC LIMIT 50"
)->fetchAll();

foreach ($rows as $r) {
  if ($r['rate'] <= 0 || $r['rate'] > 1000000) {
    throw new RuntimeException("FX outlier detected");
  }
}

echo "FX validation OK\n";
PHP

# ============================================================
# 5. Cron Job (Ops Controlled)
# ============================================================

cat > "$BACKEND/cron/fx-cron.sh" <<'BASH'
#!/usr/bin/env bash
set -e

php fx/fetch.php
php fx/normalize.php
php fx/validate.php
BASH

chmod +x "$BACKEND/cron/fx-cron.sh"

# ============================================================
# 6. Documentation
# ============================================================

cat > "$BACKEND/fx/LIVE.md" <<'MD'
# Live FX Feed

## Sources
- ECB (official)
- Fixer (backup / commercial)

## Rules
- No real-time FX in wallet credit
- Always snapshot latest valid rate
- Normalize to BASE_CURRENCY
- Validate before use

## Failure
- FX feed down → system still runs
- Old rates remain valid
MD

echo "✅ PHASE 36 COMPLETE – Live FX feed operational"