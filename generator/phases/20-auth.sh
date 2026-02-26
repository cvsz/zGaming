#!/usr/bin/env bash
ZG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ZG_ROOT/lib/bash_guard.sh"

set -Eeuo pipefail
IFS=$'
	'

#!/usr/bin/env bash
# ============================================================
# PHASE 20 – AUTH / JWT / ROLE MANAGEMENT
# ============================================================

set -euo pipefail

echo "[PHASE 20] AUTH – JWT / Role-based Authentication"

# ------------------------------------------------------------
# Resolve ROOT safely
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKEND="$ROOT/backend"

cd "$BACKEND"

# ------------------------------------------------------------
# Ensure directories
# ------------------------------------------------------------
mkdir -p \
  auth \
  middleware \
  api/auth \
  modules/user

# ------------------------------------------------------------
# JWT Config (append if missing)
# ------------------------------------------------------------
if ! grep -q "^JWT_SECRET=" .env; then
  echo "🔐 Adding JWT config to backend .env"
  cat >> .env <<'EOF'

# JWT CONFIG
JWT_SECRET=change-me-super-secret
JWT_ISSUER=casino-platform
JWT_AUDIENCE=casino-clients
JWT_TTL=3600
EOF
fi

# ------------------------------------------------------------
# Auth Service (JWT)
# ------------------------------------------------------------
cat > auth/JwtService.php <<'EOF'
<?php
declare(strict_types=1);

namespace App\Auth;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

final class JwtService
{
    public static function generate(array $claims): string
    {
        $now = time();

        $payload = array_merge($claims, [
            'iss' => getenv('JWT_ISSUER'),
            'aud' => getenv('JWT_AUDIENCE'),
            'iat' => $now,
            'exp' => $now + (int)getenv('JWT_TTL'),
        ]);

        return JWT::encode($payload, getenv('JWT_SECRET'), 'HS256');
    }

    public static function verify(string $token): array
    {
        return (array) JWT::decode(
            $token,
            new Key(getenv('JWT_SECRET'), 'HS256')
        );
    }
}
EOF

# ------------------------------------------------------------
# Password Hasher
# ------------------------------------------------------------
cat > auth/Password.php <<'EOF'
<?php
declare(strict_types=1);

namespace App\Auth;

final class Password
{
    public static function hash(string $plain): string
    {
        return password_hash($plain, PASSWORD_BCRYPT);
    }

    public static function verify(string $plain, string $hash): bool
    {
        return password_verify($plain, $hash);
    }
}
EOF

# ------------------------------------------------------------
# Auth Middleware (JWT + Role)
# ------------------------------------------------------------
cat > middleware/AuthMiddleware.php <<'EOF'
<?php
declare(strict_types=1);

namespace App\Middleware;

use App\Auth\JwtService;

final class AuthMiddleware
{
    public static function require(array $roles = []): array
    {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';

        if (!str_starts_with($header, 'Bearer ')) {
            http_response_code(401);
            exit(json_encode(['error' => 'missing_token']));
        }

        $token = substr($header, 7);

        try {
            $claims = JwtService::verify($token);
        } catch (\Throwable $e) {
            http_response_code(401);
            exit(json_encode(['error' => 'invalid_token']));
        }

        if ($roles && !in_array($claims['role'] ?? null, $roles, true)) {
            http_response_code(403);
            exit(json_encode(['error' => 'forbidden']));
        }

        return $claims;
    }
}
EOF

# ------------------------------------------------------------
# User Repository
# ------------------------------------------------------------
cat > modules/user/UserRepository.php <<'EOF'
<?php
declare(strict_types=1);

namespace App\Modules\User;

use App\Database;
use Ramsey\Uuid\Uuid;

final class UserRepository
{
    public static function findByEmail(string $email): ?array
    {
        $db = Database::connect();
        $stmt = $db->prepare("SELECT * FROM users WHERE email = ?");
        $stmt->execute([$email]);
        return $stmt->fetch() ?: null;
    }

    public static function create(string $email, string $hash, string $role): string
    {
        $db = Database::connect();
        $id = Uuid::uuid4()->toString();

        $stmt = $db->prepare(
            "INSERT INTO users (id, email, password_hash, role) VALUES (?, ?, ?, ?)"
        );
        $stmt->execute([$id, $email, $hash, $role]);

        return $id;
    }
}
EOF

# ------------------------------------------------------------
# Login API
# ------------------------------------------------------------
cat > api/auth/login.php <<'EOF'
<?php
declare(strict_types=1);

use App\Auth\JwtService;
use App\Auth\Password;
use App\Modules\User\UserRepository;

require __DIR__ . '/../../core/Bootstrap.php';

$data = json_decode(file_get_contents('php://input'), true);

$email = $data['email'] ?? '';
$password = $data['password'] ?? '';

$user = UserRepository::findByEmail($email);

if (!$user || !Password::verify($password, $user['password_hash'])) {
    http_response_code(401);
    exit(json_encode(['error' => 'invalid_credentials']));
}

$token = JwtService::generate([
    'sub' => $user['id'],
    'role' => $user['role'],
]);

echo json_encode(['token' => $token]);
EOF

# ------------------------------------------------------------
# Register API (admin only use)
# ------------------------------------------------------------
cat > api/auth/register.php <<'EOF'
<?php
declare(strict_types=1);

use App\Auth\Password;
use App\Auth\JwtService;
use App\Modules\User\UserRepository;
use App\Middleware\AuthMiddleware;

require __DIR__ . '/../../core/Bootstrap.php';

AuthMiddleware::require(['admin']);

$data = json_decode(file_get_contents('php://input'), true);

$email = $data['email'] ?? '';
$password = $data['password'] ?? '';
$role = $data['role'] ?? 'player';

$hash = Password::hash($password);
$id = UserRepository::create($email, $hash, $role);

echo json_encode(['id' => $id]);
EOF

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo "✅ Auth system (JWT / Role) generated"
echo "[PHASE 20] AUTH COMPLETE"