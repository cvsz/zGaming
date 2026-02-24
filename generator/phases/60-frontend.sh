#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 60] FRONTEND – Player + Admin (React + JWT)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FP="$ROOT/frontend-player"
FA="$ROOT/frontend-admin"

mkdir -p "$FP"/src "$FA"/src

# ============================================================
# 1. Shared Auth Helper
# ============================================================

cat > "$FP/src/auth.js" <<'JS'
export function getToken() {
  return localStorage.getItem("jwt");
}

export function authFetch(url, opts = {}) {
  return fetch(url, {
    ...opts,
    headers: {
      ...(opts.headers || {}),
      Authorization: "Bearer " + getToken(),
      "Content-Type": "application/json"
    }
  });
}
JS

cp "$FP/src/auth.js" "$FA/src/auth.js"

# ============================================================
# 2. Player App (Login + Game Launcher)
# ============================================================

cat > "$FP/src/App.jsx" <<'JSX'
import { useState } from "react";
import { authFetch } from "./auth";

export default function App() {
  const [email,setEmail] = useState("");
  const [password,setPassword] = useState("");
  const [token,setToken] = useState(localStorage.getItem("jwt"));
  const [game,setGame] = useState(null);

  async function login() {
    const r = await fetch("/api/login.php", {
      method:"POST",
      body: JSON.stringify({email,password})
    });
    const j = await r.json();
    localStorage.setItem("jwt", j.token);
    setToken(j.token);
  }

  async function launch() {
    const r = await authFetch("/api/launch/pragmatic.php");
    const j = await r.json();
    setGame(j.url);
  }

  if (!token) {
    return (
      <div className="login">
        <h2>Player Login</h2>
        <input onChange={e=>setEmail(e.target.value)} placeholder="email"/>
        <input type="password" onChange={e=>setPassword(e.target.value)} />
        <button onClick={login}>Login</button>
      </div>
    );
  }

  if (game) {
    return <iframe src={game} style={{width:"100%",height:"100vh"}} />;
  }

  return (
    <div>
      <h1>Casino Lobby</h1>
      <button onClick={launch}>Play Pragmatic</button>
    </div>
  );
}
JSX

# ============================================================
# 3. Admin App (User + Wallet View)
# ============================================================

cat > "$FA/src/App.jsx" <<'JSX'
import { useEffect, useState } from "react";
import { authFetch } from "./auth";

export default function App() {
  const [users,setUsers] = useState([]);

  useEffect(()=>{
    authFetch("/api/admin/users.php")
      .then(r=>r.json())
      .then(setUsers);
  },[]);

  return (
    <div>
      <h1>Admin Panel</h1>
      <table>
        <thead>
          <tr><th>ID</th><th>Email</th><th>Role</th></tr>
        </thead>
        <tbody>
          {users.map(u=>(
            <tr key={u.id}>
              <td>{u.id}</td>
              <td>{u.email}</td>
              <td>{u.role}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
JSX

# ============================================================
# 4. Entry Points
# ============================================================

cat > "$FP/src/main.jsx" <<'JSX'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
JSX

cp "$FP/src/main.jsx" "$FA/src/main.jsx"

# ============================================================
# 5. index.html
# ============================================================

cat > "$FP/index.html" <<'HTML'
<!DOCTYPE html>
<html>
<head><title>Casino Player</title></head>
<body><div id="root"></div></body>
</html>
HTML

cp "$FP/index.html" "$FA/index.html"

# ============================================================
# 6. Vite Config
# ============================================================

cat > "$FP/vite.config.js" <<'JS'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins:[react()], base:"/" });
JS

cp "$FP/vite.config.js" "$FA/vite.config.js"

# ============================================================
# 7. Package.json
# ============================================================

cat > "$FP/package.json" <<'JSON'
{
  "name":"player-ui",
  "private":true,
  "scripts":{"build":"vite build"},
  "dependencies":{
    "react":"^18.2.0",
    "react-dom":"^18.2.0"
  },
  "devDependencies":{
    "vite":"^5.0.0",
    "@vitejs/plugin-react":"^4.0.0"
  }
}
JSON

cp "$FP/package.json" "$FA/package.json"

echo "✅ PHASE 60 COMPLETE – Player + Admin UI ready"