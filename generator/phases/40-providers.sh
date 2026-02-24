#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 40] PROVIDERS – Game Launch & Abstraction (Pragmatic / PG Soft)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND/providers" "$BACKEND/api"

# ============================================================
# 1. Provider Interface (Contract)
# ============================================================

cat > "$BACKEND/providers/ProviderInterface.php" <<'PHP'
<?php
interface ProviderInterface {
  public function launch(array $ctx): array;
}
PHP

# ============================================================
# 2. Pragmatic Play Provider
# ============================================================

cat > "$BACKEND/providers/Pragmatic.php" <<'PHP'
<?php
final class Pragmatic implements ProviderInterface {

  public function launch(array $ctx): array {
    $params = [
      'game'      => $ctx['game_code'],
      'playerId'  => $ctx['user_id'],
      'currency'  => $ctx['currency'],
      'lang'      => $ctx['lang'],
      'token'     => $ctx['session_token'],
      'cashierUrl'=> $ctx['cashier_url'],
      'lobbyUrl'  => $ctx['lobby_url'],
    ];

    $query = http_build_query($params);
    $base  = getenv('PRAGMATIC_LAUNCH_URL');

    return [
      'url' => $base . '?' . $query
    ];
  }
}
PHP

# ============================================================
# 3. PG Soft Provider
# ============================================================

cat > "$BACKEND/providers/PGSoft.php" <<'PHP'
<?php
final class PGSoft implements ProviderInterface {

  public function launch(array $ctx): array {
    $payload = [
      'operatorToken' => getenv('PGSOFT_OPERATOR_TOKEN'),
      'userId'        => $ctx['user_id'],
      'gameCode'      => $ctx['game_code'],
      'currency'      => $ctx['currency'],
      'language'      => $ctx['lang'],
      'sessionToken'  => $ctx['session_token']
    ];

    $ch = curl_init(getenv('PGSOFT_LAUNCH_ENDPOINT'));
    curl_setopt_array($ch, [
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_POST           => true,
      CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
      CURLOPT_POSTFIELDS     => json_encode($payload),
      CURLOPT_TIMEOUT        => 10
    ]);

    $res = curl_exec($ch);
    if ($res === false) {
      throw new RuntimeException('PGSoft launch failed');
    }

    $json = json_decode($res, true);
    return ['url' => $json['launchUrl']];
  }
}
PHP

# ============================================================
# 4. Provider Factory / Resolver
# ============================================================

cat > "$BACKEND/providers/ProviderFactory.php" <<'PHP'
<?php
final class ProviderFactory {

  public static function make(string $provider): ProviderInterface {
    return match ($provider) {
      'pragmatic' => new Pragmatic(),
      'pgsoft'    => new PGSoft(),
      default     => throw new RuntimeException('Unsupported provider')
    };
  }
}
PHP

# ============================================================
# 5. Game Catalog (static example, replaceable)
# ============================================================

cat > "$BACKEND/providers/GameCatalog.php" <<'PHP'
<?php
final class GameCatalog {

  public static function all(): array {
    return [
      [
        'code' => 'PP_SWEETBONANZA',
        'name' => 'Sweet Bonanza',
        'provider' => 'pragmatic'
      ],
      [
        'code' => 'PG_MAHJONG',
        'name' => 'Mahjong Ways',
        'provider' => 'pgsoft'
      ]
    ];
  }

  public static function find(string $code): array {
    foreach (self::all() as $g) {
      if ($g['code'] === $code) {
        return $g;
      }
    }
    throw new RuntimeException('Game not found');
  }
}
PHP

# ============================================================
# 6. API: List Games
# ============================================================

cat > "$BACKEND/api/games.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';
require_once __DIR__ . '/../providers/GameCatalog.php';

echo json_encode(GameCatalog::all());
PHP

# ============================================================
# 7. API: Launch Game
# ============================================================

cat > "$BACKEND/api/launch.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

require_once __DIR__ . '/../providers/ProviderInterface.php';
require_once __DIR__ . '/../providers/Pragmatic.php';
require_once __DIR__ . '/../providers/PGSoft.php';
require_once __DIR__ . '/../providers/ProviderFactory.php';
require_once __DIR__ . '/../providers/GameCatalog.php';

Security::secureHeaders();

$input = json_decode(file_get_contents('php://input'), true);
$gameCode = $input['game'] ?? null;

if (!$gameCode) {
  http_response_code(400);
  echo json_encode(['error' => 'missing_game']);
  exit;
}

$game = GameCatalog::find($gameCode);

$ctx = [
  'user_id'        => 123, // injected from JWT later (Phase 20)
  'game_code'      => $game['code'],
  'currency'       => 'USD',
  'lang'           => 'en',
  'session_token'  => bin2hex(random_bytes(16)),
  'cashier_url'    => getenv('CASHIER_URL'),
  'lobby_url'      => getenv('LOBBY_URL')
];

$provider = ProviderFactory::make($game['provider']);
$result = $provider->launch($ctx);

echo json_encode($result);
PHP

# ============================================================
# 8. Documentation
# ============================================================

cat > "$BACKEND/providers/README.md" <<'MD'
# Providers

## Supported
- Pragmatic Play (URL-based launch)
- PG Soft (API-based launch)

## Flow
Player -> /api/launch
 -> ProviderFactory
 -> Provider::launch
 -> return iframe URL

Wallet debit / credit handled via callbacks (Phase 50).
MD

echo "✅ PHASE 40 COMPLETE – Providers ready"