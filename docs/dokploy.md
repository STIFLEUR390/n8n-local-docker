# Guide Dokploy — Déploiement et mise à jour de n8n

Ce guide explique comment déployer et maintenir le stack n8n sur [Dokploy](https://dokploy.com) (VPS avec Docker).

> **Fichier utilisé** : `docker-compose.dokploy.yml` (pas le `docker-compose.yml` local).

---

## Prérequis

- Un VPS avec Dokploy installé (Docker Engine + Docker Compose v2)
- ≥ 4 Go RAM, ≥ 2 vCPUs (sandbox DinD + task runners)
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

Dans l'onglet **Environment** du service Compose, ajoute les variables ci-dessous.

> **⚠️ Ne PAS ajouter les variables `DB_POSTGRESDB_*`** — les credentials Postgres sont hardcodés dans le compose pour éviter les erreurs de config.

```
# Sandbox n8n (génère tes propres valeurs)
SANDBOX_API_KEYS=<hex>
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=<hex>
SANDBOX_API_RUNNER_API_KEY=<hex>
N8N_SANDBOX_SERVICE_API_KEY=<doit correspondre à SANDBOX_API_KEYS>

# SearXNG
SEARXNG_SECRET=<hex>
N8N_INSTANCE_AI_SEARXNG_URL=http://searxng:8080

# AI — OpenRouter
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx
N8N_ENABLED_MODULES=instance-ai
N8N_INSTANCE_AI_MODEL=openrouter/deepseek/deepseek-chat
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_IMAGE=ghcr.io/n8n-io/n8n-sandbox-service-sandbox:latest
N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080
```

> **Astuce** : Génère des secrets robustes avec `openssl rand -hex 32`.

---

## 3. SearXNG — configuration automatique

Le compose utilise un **conteneur init** (`searxng-init`, busybox) qui crée automatiquement le fichier `settings.yml` avec l'API JSON activée dans un volume named `searxng-data`. **Aucune action manuelle n'est nécessaire.**

Pour personnaliser la config SearXNG :
- **Option A** : Modifier le `command` du service `searxng-init` dans le compose
- **Option B** : Monter un fichier via **Advanced → Mounts** dans l'UI Dokploy (File Mount, path `/etc/searxng/settings.yml`, service `searxng`)

---

## 4. Task Runners (external mode)

Le service `task-runners` (`n8nio/runners`) est inclus dans le compose. Il exécute le code JS/Python des nœuds Code dans un **processus isolé**, séparé de n8n.

| Variable | Valeur (hardcodée) |
|---|---|
| `N8N_RUNNERS_MODE` | `external` |
| `N8N_RUNNERS_AUTH_TOKEN` | `n8n-runners-auth-token-a3f8b2c1d4e5f6a7b8c9d0e1f2a3b4c5` |
| `N8N_RUNNERS_TASK_BROKER_URI` | `http://n8n:5679` |

> L'image `n8nio/runners` doit matcher la version de `n8nio/n8n`. Les deux utilisent `latest`.

---

## 5. Configurer le domaine

### Méthode 1 — Dokploy Domains (recommandé)

1. Onglet **Domains** → **Add Domain**
2. Host : `n8n.tondomaine.com`
3. Container Port : `5678`
4. Entrypoint : `websecure` (+ Let's Encrypt pour HTTPS)

### Méthode 2 — Labels manuels

Décommente le bloc `labels` dans `docker-compose.dokploy.yml` et remplace `n8n.tondomaine.com` par ton domaine.

---

## 6. Déployer

Clique sur **Deploy** dans l'UI Dokploy.

### Vérifier

```bash
docker compose -p <app-name> ps
docker compose -p <app-name> logs task-runners   # "connected to broker"
docker compose -p <app-name> logs searxng-init   # "settings.yml created"
docker compose -p <app-name> logs postgres        # "ready to accept connections"
docker compose -p <app-name> logs n8n             # pas d'erreur DB
```

---

## 7. Mettre à jour

### Depuis l'UI Dokploy

1. **Pull** les changements (bouton Git Pull ou AutoDeploy)
2. **Deploy**

### Depuis la CLI (SSH sur le VPS)

```bash
cd /var/lib/dokploy/applications/<app-name>
git pull origin main
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d
```

### Mettre à jour uniquement n8n

```bash
docker compose -p <app-name> -f docker-compose.dokploy.yml pull n8n task-runners
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d n8n task-runners
```

### Mettre à jour Postgres

> ⚠️ **Upgrade majeur (16→17, 17→18)** : Postgres ne peut pas ouvrir un répertoire de données d'une autre version majeure.

```bash
# 1. Sauvegarder
docker compose -p <app-name> exec postgres pg_dumpall -U n8n > backup.sql

# 2. Sauvegarder le volume
docker run --rm -v <app-name>_db-storage:/data -v $(pwd):/backup alpine \
  tar czf /backup/db-storage-backup.tar.gz -C /data .

# 3. Arrêter, supprimer le volume, redéployer
docker compose -p <app-name> down
docker volume rm <app-name>_db-storage
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d
```

### Rollback

```bash
# Dokploy garde les 10 derniers déploiements
# OU restaurer manuellement :
git log --oneline -5
git checkout <commit-hash> -- docker-compose.dokploy.yml
docker compose -p <app-name> up -d
```

---

## 8. Sauvegardes (Volume Backups)

1. Onglet **Volume Backups** → **Add Backup**
2. Sélectionne le volume `db-storage` (données PostgreSQL)
3. Configure la destination S3
4. Planifie (ex. quotidien)

> `sandbox-tls` contient des certificats générés automatiquement — pas besoin de les sauvegarder.

---

## 9. Monitoring

- Onglet **Monitoring** : CPU, mémoire, réseau par conteneur
- Onglet **Logs** : logs en temps réel de chaque service

---

## 10. Architecture Dokploy

```
Dokploy UI
    │
    ▼
docker-compose.dokploy.yml
    │
    ├─► sandbox-certs (runs once → TLS certs)
    ├─► sandbox-api (control plane, healthcheck)
    ├─► sandbox-runner-1 (privileged DinD)
    ├─► task-runners (n8nio/runners — code JS/Python isolé)
    ├─► searxng-init (busybox → crée settings.yml) ──► searxng
    ├─► postgres:17-alpine (volume db-storage, credentials hardcodés)
    └─► n8n (via Traefik → ton domaine)
```

---

## 11. Points d'attention

| Sujet | Détail |
|---|---|
| **Task Runners** | `n8nio/runners` exécute le code JS/Python en mode externe (isolé). Version à matcher avec `n8nio/n8n`. |
| **Sandbox (DinD)** | `sandbox-runner-1` tourne en `privileged: true`. Le VPS doit l'autoriser. |
| **RAM** | ≥ 4 Go (sandbox DinD + task runners consomment plus). |
| **SearXNG** | Settings.yml créé automatiquement par `searxng-init`. Aucune action manuelle. |
| **Credentials Postgres** | Hardcodés dans le compose. Pour les changer : modifier le compose + supprimer `db-storage`. |
| **Variables d'environnement** | L'UI Dokploy écrit dans `.env` mais **n'injecte pas** automatiquement dans les conteneurs. Le compose utilise `${...}`. |
| **Ports** | Ne jamais exposer de ports — Traefik gère le routing. |

---

## 12. Dépannage

### Postgres : "password authentication failed for user n8n"

Les credentials sont maintenant hardcodés dans le compose. Si l'erreur persiste, c'est que le volume `db-storage` contient des données initialisées avec un ancien mot de passe.

```bash
# Reset complet
docker compose -p <app-name> down
docker volume rm <app-name>_db-storage
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d
```

### SearXNG : "settings.yml is not a valid file"

Le compose utilise un conteneur init + volume named. Si l'erreur persiste :

```bash
docker compose -p <app-name> logs searxng-init
docker compose -p <app-name> down
docker volume rm <app-name>_searxng-data
docker compose -p <app-name> -f docker-compose.dokploy.yml up -d
```

### Task Runners ne se connectent pas

```bash
docker compose -p <app-name> logs task-runners
docker compose -p <app-name> logs n8n | grep -i runner
```

Vérifie que `N8N_RUNNERS_AUTH_TOKEN` est identique côté n8n et task-runners (hardcodé dans le compose).

### sandbox-api ne devient pas healthy

```bash
docker compose -p <app-name> logs sandbox-certs   # certificats générés ?
docker compose -p <app-name> ps sandbox-certs     # doit montrer "exited (0)"
docker compose -p <app-name> logs sandbox-api
```

### role "-d" does not exist (healthcheck Postgres)

Le healthcheck utilise des credentials hardcodés. Si cette erreur apparaît, vérifie que le compose contient bien `pg_isready -h localhost -U n8n -d n8n` (pas de `${...}`).
