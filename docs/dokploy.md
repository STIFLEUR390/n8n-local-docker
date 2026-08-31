# Guide Dokploy — Déploiement et mise à jour de n8n

Ce guide explique comment déployer et maintenir le stack n8n sur [Dokploy](https://dokploy.com) (VPS avec Docker).

> **Fichier utilisé** : `docker-compose.dokploy.yml` (pas le `docker-compose.yml` local).

---

## Prérequis

- Un VPS avec Dokploy installé (Docker Engine + Docker Compose v2)
- ≥ 4 Go RAM, ≥ 2 vCPUs (le sandbox DinD nécessite de la marge)
- Une clé API [OpenRouter](https://openrouter.ai/keys)
- Un domaine DNS avec un enregistrement A pointant vers l'IP du VPS

---

## 1. Créer l'application dans Dokploy

1. **Créer un projet** dans Dokploy (ex. `n8n`).
2. **Créer un service Compose** :
   - Type : `Docker Compose`
   - Source : GitHub ou Git
   - Repository : `STIFLEUR390/n8n-local-docker` (ou ton fork)
   - Branch : `main`
   - **Compose Path** : `./docker-compose.dokploy.yml`
3. **Enregistrer**.

---

## 2. Configurer les variables d'environnement

Dans l'onglet **Environment** du service Compose, ajoute **toutes** les variables (Dokploy les écrit dans `.env` ; le compose les référence via `${...}`) :

```
# Sandbox n8n
SANDBOX_API_KEYS=<génère-une-valeur-complexe>
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=<génère-une-valeur-complexe>
SANDBOX_API_RUNNER_API_KEY=<génère-une-valeur-complexe>
N8N_SANDBOX_SERVICE_API_KEY=<doit correspondre à SANDBOX_API_KEYS>

# SearXNG
SEARXNG_SECRET=<génère-une-valeur-complexe>
N8N_INSTANCE_AI_SEARXNG_URL=http://searxng:8080

# AI — OpenRouter
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx
N8N_ENABLED_MODULES=instance-ai
N8N_INSTANCE_AI_MODEL=openrouter/anthropic/claude-3.7-sonnet
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_IMAGE=ghcr.io/n8n-io/n8n-sandbox-service-sandbox:latest
N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080

# PostgreSQL
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=<mot-de-passe-fort>
DB_POSTGRESDB_SCHEMA=public
```

> **Astuce** : Génère des secrets robustes avec `openssl rand -hex 32`.

---

## 3. Monter la configuration SearXNG

Dokploy nettoie le répertoire du repo à chaque déploiement (`git clone`). Les montages type `./searxng-settings.yml` ne survivent pas.

### Option A — Dossier `../files` (recommandé)

Crée le fichier dans le dossier `files` de Dokploy (persistant entre déploiements) :

```bash
# Sur le VPS, dans le répertoire de Dokploy pour ton app :
mkdir -p ../files
cat > ../files/searxng-settings.yml <<'EOF'
use_default_settings: true
search:
  formats:
    - html
    - json
EOF
```

> Le montage dans `docker-compose.dokploy.yml` est déjà configuré :
> `../files/searxng-settings.yml:/etc/searxng/settings.yml:ro`

### Option B — File Mounts (UI Dokploy)

1. Advanced → **Mounts** → Add Mount
2. Type : File
3. Contenu : le YAML ci-dessus
4. Container Path : `/etc/searxng/settings.yml`
5. Service : `searxng`

---

## 4. Configurer le domaine

### Méthode 1 — Dokploy Domains (recommandé)

1. Onglet **Domains** → **Add Domain**
2. Host : `n8n.tondomaine.com`
3. Container Port : `5678`
4. Entrypoint : `websecure` (+ Let's Encrypt pour HTTPS)

Dokploy ajoute automatiquement les labels Traefik et le réseau.

### Méthode 2 — Labels manuels

Décommente le bloc `labels` dans `docker-compose.dokploy.yml` et remplace `n8n.tondomaine.com` par ton domaine.

---

## 5. Déployer

Clique sur **Deploy** dans l'UI Dokploy.

### Vérifier

```bash
# Depuis l'UI Dokploy → Logs, ou via SSH :
docker compose -p <app-name> ps
docker compose -p <app-name> logs sandbox-api | grep -i runner
```

Attends que `sandbox-api` et `postgres` soient **healthy**.

---

## 6. Mettre à jour

### Depuis l'UI Dokploy

1. **Pull** les changements (bouton Git Pull ou AutoDeploy si branch suivie)
2. **Deploy** — Dokploy relance `docker compose up -d`

### Depuis la CLI (SSH sur le VPS)

```bash
# Aller dans le répertoire Dokploy de l'app
cd /var/lib/dokploy/applications/<app-name>

# Pull les changements
git pull origin main

# Redéployer
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d
```

### Mettre à jour uniquement n8n (pas le reste du stack)

```bash
docker compose -p <app-name> -f docker-compose.dokploy.yml pull n8n
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d n8n
```

### Mettre à jour Postgres

> ⚠️ **Postgres 16 → 17 ou 17 → 18 est un upgrade majeur.** Postgres ne peut pas ouvrir un répertoire de données écrit par une version majeure différente.

```bash
# 1. Sauvegarder
docker compose -p <app-name> exec postgres pg_dumpall -U n8n > backup.sql

# 2. Arrêter n8n (garder postgres pour le dump)
docker compose -p <app-name> stop n8n

# 3. Sauvegarder le volume
docker run --rm -v <app-name>_db-storage:/data -v $(pwd):/backup alpine \
  tar czf /backup/db-storage-backup.tar.gz -C /data .

# 4. Mettre à jour le tag image dans le compose si besoin, puis redeploy
docker compose -p <app-name> up -d

# 5. Vérifier que tout fonctionne, puis supprimer la backup
```

### Rollback

Si quelque chose casse après un déploiement :

```bash
# Dokploy garde les 10 derniers déploiements — re-sélectionner un ancien commit
# OU restaurer manuellement :
git log --oneline -5          # trouver le commit précédent
git checkout <commit-hash> -- docker-compose.dokploy.yml
docker compose -p <app-name> up -d
```

---

## 7. Sauvegardes (Volume Backups)

Les volumes nommés `db-storage` et `sandbox-tls` sont gérés par Docker. Dokploy supporte les **Volume Backups** (backup automatique vers S3) sur les volumes nommés.

1. Onglet **Volume Backups** → **Add Backup**
2. Sélectionne le volume `db-storage` (données PostgreSQL)
3. Configure la destination S3
4. Planifie (ex. quotidien)

> `sandbox-tls` contient des certificats générés automatiquement — pas besoin de les sauvegarder.

---

## 8. Monitoring

Dokploy offre un monitoring natif par service :

- Onglet **Monitoring** : CPU, mémoire, réseau par conteneur
- Onglet **Logs** : logs en temps réel de chaque service

---

## 9. Stack complet — Architecture Dokploy

```
Dokploy UI
    │
    ▼
docker-compose.dokploy.yml
    │
    ├─► sandbox-certs (runs once → TLS certs)
    ├─► sandbox-api (control plane, healthcheck)
    ├─► sandbox-runner-1 (privileged DinD)
    ├─► searxng (web search local)
    ├─► postgres:17-alpine (volume db-storage)
    └─► n8n (via Traefik → ton domaine)
```

---

## 10. Point d'attention

| Sujet | Détail |
|---|---|
| **Docker-in-Docker (sandbox-runner-1)** | Le runner tourne en `privileged: true`. Le VPS doit autoriser le mode privileged (cas standard sur un VPS dédié). Si tu utilises un hébergement restreint (ex. runners CI), cela ne fonctionnera pas. |
| **RAM** | Le sandbox DinD consomme plus qu'un conteneur classique. Prévoir ≥ 4 Go. |
| **searxng-settings.yml** | Monter via `../files/` ou File Mounts — JAMAIS via `./` (git clone nettoie le répertoire). |
| **Variables d'environnement** | Les variables de l'UI Dokploy sont écrites dans `.env` mais **ne sont pas injectées** automatiquement dans les conteneurs. Le compose les récupère via `${...}`. |
| **Ports** | Ne jamais exposer de ports dans le compose Dokploy — Traefik gère le routing. |
| **Postgres** | Migration SQLite → PostgreSQL : automatique au premier démarrage. Migration majeure Postgres (16→17) : nécessite `pg_dumpall` + volume neuf. |
