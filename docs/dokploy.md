# Guide Dokploy — Déploiement et mise à jour de n8n

Ce guide explique comment déployer et maintenir le stack n8n sur [Dokploy](https://dokploy.com) (VPS avec Docker).

> **Deux fichiers compose au choix** :
>
> | Fichier | Contenu | Env example |
> |---|---|---|
> | `docker-compose.dokploy.yml` | **Avec IA** : sandbox n8n + SearXNG + Assistant OpenRouter | `docker-compose.dokploy.env.example` |
> | `docker-compose.dokploy.no-ia.yml` | **Sans IA** : n8n + PostgreSQL + task runners uniquement | `docker-compose.dokploy.no-ia.env.example` |
>
> (Ni le `docker-compose.yml` ni `.env.example` à la racine, qui sont la config locale.)

---

## Prérequis

- Un VPS avec Dokploy installé (Docker Engine + Docker Compose v2)
- ≥ 4 Go RAM, ≥ 2 vCPUs (sandbox DinD + task runners en mode IA)
- Une clé API [OpenRouter](https://openrouter.ai/keys) (mode IA uniquement)
- Un domaine DNS avec un enregistrement A pointant vers l'IP du VPS

---

## 1. Créer l'application dans Dokploy

1. **Créer un projet** dans Dokploy (ex. `n8n`).
2. **Créer un service Compose** :
   - Type : `Docker Compose`
   - Source : GitHub ou Git
   - Repository : `STIFLEUR390/n8n-local-docker` (ou ton fork)
   - Branch : `main`
   - **Compose Path** : `./docker-compose.dokploy.yml` (avec IA)
     ou `./docker-compose.dokploy.no-ia.yml` (sans IA)
3. **Enregistrer**.

---

## 2. Choisir le fichier : avec IA ou sans IA

Le choix du mode se fait **au niveau du Compose Path** (section 1), pas avec des variables :

| | `docker-compose.dokploy.yml` (avec IA) | `docker-compose.dokploy.no-ia.yml` (sans IA) |
|---|---|---|
| Services | n8n, postgres, task-runners, **sandbox-certs, sandbox-api, sandbox-runner-1, searxng-init, searxng** | n8n, postgres, task-runners |
| Volumes | `db-storage`, `n8n-storage`, `sandbox-tls`, `searxng-data` | `db-storage`, `n8n-storage` |
| Assistant n8n | actif (OpenRouter, sandbox) | **déchargé** (`N8N_DISABLED_MODULES=instance-ai`) |
| Variables requises | secrets sandbox + clé OpenRouter | **aucune** |
| RAM | ≥ 4 Go (DinD sandbox) | ~2 Go |

- **Avec IA** : la sandbox et SearXNG démarrent toujours ; n8n est configuré pour OpenRouter.
- **Sans IA** : aucun service sandbox/SearXNG n'est défini dans le fichier, et le module `instance-ai` est déchargé au démarrage de n8n.

> Pour changer de mode plus tard : change le Compose Path dans l'UI Dokploy puis redéploie. Un changement de fichier recrée le conteneur n8n — le volume `n8n-storage` (clé d'encryption) est justement là pour que cela ne casse rien.

---

## 3. Configurer les variables d'environnement

Dans l'onglet **Environment** du service Compose, colle le contenu du fichier env example correspondant à ton choix de compose.

### Version avec IA — `docker-compose.dokploy.env.example`

```
# Sandbox n8n (génère tes propres valeurs)
SANDBOX_API_KEYS=<hex>
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=<hex>
SANDBOX_API_RUNNER_API_KEY=<hex>
N8N_SANDBOX_SERVICE_API_KEY=<doit correspondre à SANDBOX_API_KEYS>

# SearXNG (web search de l'assistant)
SEARXNG_SECRET=<hex>

# AI — OpenRouter (https://openrouter.ai/keys)
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx
```

### Version sans IA — `docker-compose.dokploy.no-ia.env.example`

Aucune variable obligatoire : PostgreSQL a ses défauts dans le compose, aucune clé API n'est nécessaire.

### Variables IA optionnelles (version avec IA)

| Variable | Défaut dans le compose | Rôle |
|---|---|---|
| `N8N_INSTANCE_AI_MODEL` | `openrouter/anthropic/claude-3.7-sonnet` | modèle OpenRouter (`openrouter/<provider>/<model>`) |
| `N8N_INSTANCE_AI_SANDBOX_ENABLED` | `true` | sandbox activée côté n8n |
| `N8N_INSTANCE_AI_SANDBOX_IMAGE` | `ghcr.io/n8n-io/n8n-sandbox-service-sandbox:latest` | image des sandboxes |
| `N8N_SANDBOX_SERVICE_URL` | `http://sandbox-api:8080` | URL du sandbox API |
| `N8N_INSTANCE_AI_SEARXNG_URL` | `http://searxng:8080` | web search local |
| `N8N_ENABLED_MODULES` | `instance-ai` | module Assistant (chargé par défaut par n8n) |

Modèles OpenRouter exemples : `openrouter/anthropic/claude-3.7-sonnet`, `openrouter/deepseek/deepseek-chat`, `openrouter/openai/gpt-4o`.

> **Variables `DB_POSTGRESDB_*`** : ne rien déclarer — défauts cohérents dans le compose ; `DB_POSTGRESDB_USER` et `DB_POSTGRESDB_PASSWORD` sont hardcodés.

> **Astuce** : Génère des secrets robustes avec `openssl rand -hex 32`.

---

## 4. SearXNG — configuration automatique

> Présent uniquement dans `docker-compose.dokploy.yml` (avec IA) — le fichier `no-ia` ne contient pas SearXNG.

Le compose utilise un **conteneur init** (`searxng-init`, busybox) qui crée automatiquement le fichier `settings.yml` avec l'API JSON activée dans un volume named `searxng-data`. **Aucune action manuelle n'est nécessaire.**

Pour personnaliser la config SearXNG :
- **Option A** : Modifier le `command` du service `searxng-init` dans le compose
- **Option B** : Monter un fichier via **Advanced → Mounts** dans l'UI Dokploy (File Mount, path `/etc/searxng/settings.yml`, service `searxng`)

---

## 5. Task Runners (external mode)

Le service `task-runners` (`n8nio/runners`) est inclus dans le compose. Il exécute le code JS/Python des nœuds Code dans un **processus isolé**, séparé de n8n.

| Variable | Valeur (hardcodée) |
|---|---|
| `N8N_RUNNERS_MODE` | `external` |
| `N8N_RUNNERS_AUTH_TOKEN` | `n8n-runners-auth-token-a3f8b2c1d4e5f6a7b8c9d0e1f2a3b4c5` |
| `N8N_RUNNERS_TASK_BROKER_URI` | `http://n8n:5679` |

> L'image `n8nio/runners` doit matcher la version de `n8nio/n8n`. Les deux utilisent `latest`.

---

## 6. Configurer le domaine

### Méthode 1 — Dokploy Domains (recommandé)

1. Onglet **Domains** → **Add Domain**
2. Host : `n8n.tondomaine.com`
3. Container Port : `5678`
4. Entrypoint : `websecure` (+ Let's Encrypt pour HTTPS)

### Méthode 2 — Labels manuels

Décommente le bloc `labels` dans `docker-compose.dokploy.yml` et remplace `n8n.tondomaine.com` par ton domaine.

---

## 7. Déployer

Clique sur **Deploy** dans l'UI Dokploy.

### Vérifier

```bash
docker compose -p <app-name> ps
docker compose -p <app-name> logs task-runners   # "connected to broker"
docker compose -p <app-name> logs postgres        # "ready to accept connections"
docker compose -p <app-name> logs n8n             # pas d'erreur DB
# Version avec IA uniquement :
docker compose -p <app-name> logs searxng-init   # "settings.yml created"
```

---

## 8. Mettre à jour

> Dans les commandes ci-dessous, `-f docker-compose.dokploy.yml` = **ton** fichier compose (remplace par `docker-compose.dokploy.no-ia.yml` si tu utilises la version sans IA).

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

## 9. Sauvegardes (Volume Backups)

1. Onglet **Volume Backups** → **Add Backup**
2. Sélectionne le volume `db-storage` (données PostgreSQL)
3. Configure la destination S3
4. Planifie (ex. quotidien)

> ⚠️ Sauvegarde aussi le volume `n8n-storage` : il contient la **clé d'encryption** de l'instance. Restaurer `db-storage` sans `n8n-storage` rend les données chiffrées illisibles (n8n crash-loop avec `cannot be read with this instance encryption key`).

> `sandbox-tls` contient des certificats générés automatiquement — pas besoin de les sauvegarder.

---

## 10. Monitoring

- Onglet **Monitoring** : CPU, mémoire, réseau par conteneur
- Onglet **Logs** : logs en temps réel de chaque service

---

## 11. Architecture Dokploy

> Vue complète du fichier **avec IA** (`docker-compose.dokploy.yml`). Le fichier `no-ia` ne contient que task-runners, postgres et n8n (sans sandbox-tls ni searxng-data).

```
Dokploy UI
    │
    ▼
docker-compose.dokploy.yml
    │
    ├─► sandbox-certs (runs once → TLS certs)   ┐ docker-compose.dokploy.yml
    ├─► sandbox-api (control plane, healthcheck) │ (avec IA uniquement)
    ├─► sandbox-runner-1 (privileged DinD)      ┘
    ├─► task-runners (n8nio/runners — code JS/Python isolé)
    ├─► searxng-init (busybox → crée settings.yml) ──► searxng
    ├─► postgres:17-alpine (volume db-storage, credentials hardcodés)
    └─► n8n (via Traefik → ton domaine)
         └─ volume n8n-storage (/home/node/.n8n — clé d'encryption, binary data)
```

---

## 12. Points d'attention

| Sujet | Détail |
|---|---|
| **Task Runners** | `n8nio/runners` exécute le code JS/Python en mode externe (isolé). Version à matcher avec `n8nio/n8n`. |
| **Sandbox (DinD)** | `sandbox-runner-1` tourne en `privileged: true`. Le VPS doit l'autoriser. |
| **RAM** | ≥ 4 Go avec IA (sandbox DinD + task runners) ; ~2 Go en version `no-ia`. |
| **SearXNG** | Settings.yml créé automatiquement par `searxng-init` (fichier avec IA). Aucune action manuelle. |
| **Credentials Postgres** | Hardcodés dans le compose. Pour les changer : modifier le compose + supprimer `db-storage`. |
| **Clé d'encryption n8n** | Persistée dans le volume `n8n-storage` (`/home/node/.n8n`). Ne jamais supprimer ce volume — n8n ne pourrait plus lire ses données chiffrées. |
| **Variables d'environnement** | L'UI Dokploy écrit dans `.env` mais **n'injecte pas** automatiquement dans les conteneurs. Le compose utilise `${...}`. |
| **Ports** | Ne jamais exposer de ports — Traefik gère le routing. |

---

## 13. Dépannage

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

### sandbox-api ne devient pas healthy (mode IA)

> Présent uniquement dans `docker-compose.dokploy.yml` (avec IA) — le fichier `no-ia` ne contient pas ces services.

```bash
docker compose -p <app-name> logs sandbox-certs   # certificats générés ?
docker compose -p <app-name> ps sandbox-certs     # doit montrer "exited (0)"
docker compose -p <app-name> logs sandbox-api
```

### "cannot be read with this instance encryption key"

n8n ne reconnaît plus la clé d'encryption de ses données. Cause classique : le volume `n8n-storage` a été supprimé/recréé (le conteneur a généré une nouvelle clé, les données en DB restent chiffrées avec l'ancienne).

- **Restaure** le volume `n8n-storage` depuis une sauvegarde (ou la copie du volume d'origine).
- Si tu n'as aucune sauvegarde : la clé est perdue — il faut réinitialiser les données chiffrées (seau `db-storage` + `n8n-storage` à réinitialiser, perte de données).

> Le compose persiste `~/.n8n` dans `n8n-storage` précisément pour éviter cela à chaque recréation de conteneur (changement de fichier, redeploy, update d'image).

### role "-d" does not exist (healthcheck Postgres)

Le healthcheck utilise des credentials hardcodés. Si cette erreur apparaît, vérifie que le compose contient bien `pg_isready -h localhost -U n8n -d n8n` (pas de `${...}`).
