#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 20] AUTH – Login / JWT / Role Based Access"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND="$ROOT/backend"

mkdir -p "$BACKEND"/{auth,api,db}

# ============================================================
# 1. User / Role Schema
# ============================================================

cat > "$BACKEND/db/auth.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS users (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('player','admin') NOT NULL DEFAULT 'player',
  status ENUM('active','disabled') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auth_audit (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT,
  event VARCHAR(64),
  ip VARCHAR(64),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

# ============================================================
# 2. JWT Utility (HMAC-SHA256)
# ============================================================

cat > "$BACKEND/auth/JWT.php" <<'PHP'
<?php
final class JWT {

  private static function b64(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
  }

  private static function ub64(string $data): string {
    return base64_decode(strtr($data, '-_', '+/'));
  }

  public static function encode(array $payload, string $secret, int $ttl): string {
    $header = self::b64(json_encode(['alg'=>'HS256','typ'=>'JWT']));
    $payload['exp'] = time() + $ttl;
    $body = self::b64(json_encode($payload));
    $sig = self::b64(hash_hmac('sha256', "$header.$body", $secret, true));
    return "$header.$body.$sig";
  }

  public static function decode(string $jwt, string $secret): array {
    [$h,$b,$s] = explode('.', $jwt);
    $valid = self::b64(hash_hmac('sha256', "$h.$b", $secret, true));
    if (!hash_equals($valid, $s)) {
      throw new RuntimeException('invalid_jwt');
    }
    $payload = json_decode(self::ub64($b), true);
    if (($payload['exp'] ?? 0) < time()) {
      throw new RuntimeException('jwt_expired');
    }
    return $payload;
  }
}
PHP

# ============================================================
# 3. Auth Guard (Require Login / Role)
# ============================================================

cat > "$BACKEND/auth/Auth.php" <<'PHP'
<?php
final class Auth {

  public static function user(): array {
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!str_starts_with($hdr, 'Bearer ')) {
      throw new RuntimeException('missing_token');
    }
    $jwt = substr($hdr, 7);
    return JWT::decode($jwt, getenv('JWT_SECRET'));
  }

  public static function requireRole(string $role): array {
    $u = self::user();
    if (($u['role'] ?? '') !== $role) {
      http_response_code(403);
      echo json_encode(['error'=>'forbidden']);
      exit;
    }
    return $u;
  }
}
PHP

# ============================================================
# 4. Login API
# ============================================================

cat > "$BACKEND/api/login.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';
require_once __DIR__ . '/../auth/JWT.php';

Security::requireJson();

$data = json_decode(file_get_contents('php://input'), true);
$email = $data['email'] ?? '';
$pass  = $data['password'] ?? '';

$db = Database::conn();
$stmt = $db->prepare("SELECT * FROM users WHERE email=? AND status='active'");
$stmt->execute([$email]);
$user = $stmt->fetch();

if (!$user || !password_verify($pass, $user['password_hash'])) {
  http_response_code(401);
  echo json_encode(['error'=>'invalid_credentials']);
  exit;
}

$token = JWT::encode(
  ['uid'=>$user['id'], 'role'=>$user['role']],
  getenv('JWT_SECRET'),
  3600
);

$db->prepare(
  "INSERT INTO auth_audit (user_id,event,ip) VALUES (?,?,?)"
)->execute([$user['id'],'login',$_SERVER['REMOTE_ADDR'] ?? '']);

echo json_encode(['token'=>$token]);
PHP

# ============================================================
# 5. Admin-only API Example
# ============================================================

cat > "$BACKEND/api/admin/users.php" <<'PHP'
<?php
require_once __DIR__ . '/../../core/Bootstrap.php';
require_once __DIR__ . '/../../auth/Auth.php';

Auth::requireRole('admin');

$db = Database::conn();
$rows = $db->query("SELECT id,email,role,status FROM users")->fetchAll();
echo json_encode($rows);
PHP

# ============================================================
# 6. Seed Admin User (one-time)
# ============================================================

cat > "$BACKEND/auth/seed-admin.php" <<'PHP'
<?php
require_once __DIR__ . '/../core/Bootstrap.php';

$db = Database::conn();
$hash = password_hash('admin123', PASSWORD_BCRYPT);

$db->prepare(
  "INSERT IGNORE INTO users (email,password_hash,role)
   VALUES ('admin@casino.local', ?, 'admin')"
)->execute([$hash]);

echo "admin seeded\n";
PHP

# ============================================================
# 7. Documentation
# ============================================================

cat > "$BACKEND/auth/README.md" <<'MD'
# Authentication System

## Flow
POST /api/login
 -> JWT (HS256)
 -> Authorization: Bearer <token>

## Roles
- player
- admin

## Security
- bcrypt password
- exp claim
- audit log
MD

echo "✅ PHASE 20 COMPLETE – Auth / JWT / Role ready"