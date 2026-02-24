#!/usr/bin/env bash
set -euo pipefail

echo "[PHASE 95] KUBERNETES – Helm / Kustomize / Multi-Env"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K8S="$ROOT/k8s"

mkdir -p "$K8S"/{base,overlays/{dev,staging,prod},helm/casino}

# ============================================================
# 1. Base Kubernetes Manifests (Kustomize)
# ============================================================

cat > "$K8S/base/namespace.yaml" <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: casino
YAML

# ------------------------------------------------------------
# Backend Deployment
# ------------------------------------------------------------
cat > "$K8S/base/backend-deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: casino-backend
  namespace: casino
spec:
  replicas: 2
  selector:
    matchLabels:
      app: casino-backend
  template:
    metadata:
      labels:
        app: casino-backend
    spec:
      containers:
        - name: backend
          image: casino-platform-backend:latest
          ports:
            - containerPort: 9000
          envFrom:
            - secretRef:
                name: casino-secrets
          readinessProbe:
            httpGet:
              path: /api/healthz.php
              port: 9000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /api/healthz.php
              port: 9000
            initialDelaySeconds: 30
            periodSeconds: 30
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
YAML

cat > "$K8S/base/backend-service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: casino-backend
  namespace: casino
spec:
  selector:
    app: casino-backend
  ports:
    - port: 9000
      targetPort: 9000
YAML

# ------------------------------------------------------------
# NGINX Deployment
# ------------------------------------------------------------
cat > "$K8S/base/nginx-deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: casino-nginx
  namespace: casino
spec:
  replicas: 2
  selector:
    matchLabels:
      app: casino-nginx
  template:
    metadata:
      labels:
        app: casino-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
      volumes:
        - name: nginx-config
          configMap:
            name: casino-nginx-config
YAML

cat > "$K8S/base/nginx-service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: casino-nginx
  namespace: casino
spec:
  selector:
    app: casino-nginx
  ports:
    - port: 80
      targetPort: 80
YAML

# ------------------------------------------------------------
# ConfigMap / Secrets
# ------------------------------------------------------------
cat > "$K8S/base/nginx-configmap.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: casino-nginx-config
  namespace: casino
data:
  nginx.conf: |
    # injected from build / CI
YAML

cat > "$K8S/base/secret.yaml" <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: casino-secrets
  namespace: casino
type: Opaque
stringData:
  APP_ENV: production
  JWT_SECRET: change-me
  PRAGMATIC_SECRET: change-me
  PGSOFT_SECRET: change-me
YAML

# ------------------------------------------------------------
# Kustomization base
# ------------------------------------------------------------
cat > "$K8S/base/kustomization.yaml" <<'YAML'
resources:
  - namespace.yaml
  - backend-deployment.yaml
  - backend-service.yaml
  - nginx-deployment.yaml
  - nginx-service.yaml
  - nginx-configmap.yaml
  - secret.yaml
YAML

# ============================================================
# 2. Overlays (dev / staging / prod)
# ============================================================

for ENV in dev staging prod; do
cat > "$K8S/overlays/$ENV/kustomization.yaml" <<YAML
resources:
  - ../../base

patches:
  - target:
      kind: Deployment
      name: casino-backend
    patch: |-
      - op: replace
        path: /spec/replicas
        value: $( [[ "$ENV" == "prod" ]] && echo 4 || echo 1 )
YAML
done

# ============================================================
# 3. Helm Chart (Production-grade)
# ============================================================

cat > "$K8S/helm/casino/Chart.yaml" <<'YAML'
apiVersion: v2
name: casino-platform
description: Casino Platform – Production Helm Chart
type: application
version: 1.0.0
appVersion: "1.0.0"
YAML

cat > "$K8S/helm/casino/values.yaml" <<'YAML'
backend:
  replicas: 2
  image: casino-platform-backend:latest

nginx:
  image: nginx:alpine

resources:
  backend:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
YAML

cat > "$K8S/helm/casino/templates/backend.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "casino-platform.fullname" . }}-backend
spec:
  replicas: {{ .Values.backend.replicas }}
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: {{ .Values.backend.image }}
          ports:
            - containerPort: 9000
YAML

# ============================================================
# 4. Documentation
# ============================================================

cat > "$K8S/README.md" <<'MD'
# Kubernetes Deployment

## Options
- Kustomize (recommended for GitOps)
- Helm (recommended for platform teams)

## Environments
- dev
- staging
- prod

## Health
- /healthz
- /api/healthz.php

## Security
- Secrets via K8s Secret
- TLS via Cloudflare Ingress
MD

echo "✅ PHASE 95 COMPLETE – Kubernetes ready (Helm + Kustomize)"