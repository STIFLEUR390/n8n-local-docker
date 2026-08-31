# n8n Local — Docker Compose

Stack n8n en local (ou VPS via Dokploy) avec **AI Assistant** (OpenRouter), **sandbox** Docker-in-Docker, **Task Runners externes** (isolation du code JS/Python), **SearXNG** pour le web search, et **PostgreSQL 17 Alpine**.

> **Aucune API externe** sauf **OpenRouter** pour les fonctions AI.
> Le web search utilise SearXNG bundlé (100% local).

---

## Composants

| Service              | Description                                                               |
| -------------------- | ------------------------------------------------------------------------- |
| **n8n**              | Workflow editor, AI Assistant — `http://localhost:5678`                   |
| **task-runners**     | Exécution isolée du code JS/Python (external mode) — `n8nio/runners`     |
| **sandbox-certs**    | Génère les certificats TLS mTLS pour le sandbox (run once)               |
| **sandbox-api**      | API de contrôle du sandbox (exécution de code par l'AI Assistant)        |
| **sandbox-runner-1** | Runner DinD (Docker-in-Docker) — exécution isolée du code AI             |
| **postgres**         | PostgreSQL 17 Alpine — base de données de n8n                             |
| **searxng-init**     | Init container : crée le `settings.yml` de SearXNG (API JSON activée)    |
| **searxng**          | Moteur de recherche web local pour l'AI Assistant                        |

---

## Prérequis

- Docker Engine + Docker Compose v2 (`docker compose version`)
- ≥ 4 Go RAM, ≥ 2 vCPUs
- Clé API [OpenRouter](https://openrouter.ai/keys) (pour les fonctions AI)

---

## Démarrage rapide

```bash
git clone https://github.com/STIFLEUR390/n8n-local-docker.git
cd n8n-local-docker

# 1. Édite le fichier .env avec tes propres valeurs
cp .env.example .env
nano .env

# 2. Lance le stack
./start.sh
```

Ou manuellement :

```bash
cp .env.example .env
# ... édite .env ...
docker compose up -d
docker compose ps   # attendre sandbox-api + postgres healthy
```

n8n est disponible sur **http://localhost:5678**.

---

## Configuration

### Variables d'environnement

Toutes les variables sont modifiables dans **`.env`** (local) ou l'onglet **Environment** de Dokploy.

```env
# Sandbox n8n (génère tes propres valeurs)
SANDBOX_API_KEYS=<hex>
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=<hex>
SANDBOX_API_RUNNER_API_KEY=<hex>
N8N_SANDBOX_SERVICE_API_KEY=<doit correspondre à SANDBOX_API_KEYS>

# SearXNG
SEARXNG_SECRET=<hex>
N8N_INSTANCE_AI_SEARXNG_URL=http://searxng:8080

# Task Runners (external mode)
N8N_RUNNERS_AUTH_TOKEN=<partagé avec le service task-runners>

# AI — OpenRouter
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx
N8N_ENABLED_MODULES=instance-ai
N8N_INSTANCE_AI_MODEL=openrouter/anthropic/claude-3.7-sonnet
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_IMAGE=ghcr.io/n8n-io/n8n-sandbox-service-sandbox:latest
N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080
```

> **Astuce** : Génère des secrets robustes avec `openssl rand -hex 32`.

### AI — OpenRouter (par défaut)

```env
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx
N8N_INSTANCE_AI_MODEL=openrouter/anthropic/claude-3.7-sonnet
```

Modèles disponibles :
- `openrouter/anthropic/claude-3.7-sonnet`
- `openrouter/openai/gpt-4o`
- `openrouter/deepseek/deepseek-chat`

### AI — Endpoint OpenAI-like (optionnel)

Pour un service local compatible OpenAI (Ollama, LM Studio, vLLM…) :

```env
N8N_INSTANCE_AI_MODEL=openai/gpt-4o
N8N_INSTANCE_AI_MODEL_URL=http://host.docker.internal:1234/v1
N8N_INSTANCE_AI_MODEL_API_KEY=sk-no-key
```

### PostgreSQL

Les credentials sont **hardcodés** dans le compose pour éviter les erreurs de config :

| Variable | Valeur |
|---|---|
| `POSTGRES_USER` / `DB_POSTGRESDB_USER` | `n8n` |
| `POSTGRES_PASSWORD` / `DB_POSTGRESDB_PASSWORD` | `a3f8b2c1d4e5f6a7b8c9d0e1f2a3b4c5` |
| `POSTGRES_DB` / `DB_POSTGRESDB_DATABASE` | `n8n` |

> Pour changer les credentials : modifie les deux services (postgres ET n8n) dans le compose, puis supprime le volume `db-storage` avant de redéployer.

n8n migre automatiquement de SQLite vers PostgreSQL au premier démarrage.

### Task Runners (external mode)

Le service `task-runners` (`n8nio/runners`) exécute le code JS/Python des nœuds Code dans un **processus isolé**, séparé de n8n. C'est la configuration recommandée pour la production.

| Variable | Description |
|---|---|
| `N8N_RUNNERS_MODE` | `external` — mode externe (isolé) |
| `N8N_RUNNERS_BROKER_LISTEN_ADDRESS` | `0.0.0.0` — accepte les connexions du runner |
| `N8N_RUNNERS_AUTH_TOKEN` | Secret partagé entre n8n et task-runners |
| `N8N_RUNNERS_TASK_BROKER_URI` | `http://n8n:5679` — adresse du broker côté runners |

> L'image `n8nio/runners` doit matcher la version de `n8nio/n8n`. Les deux utilisent `latest` par défaut.

---

## Déploiement sur Dokploy

Un compose dédié (`docker-compose.dokploy.yml`) est fourni pour le déploiement sur VPS via [Dokploy](https://dokploy.com).

| | Local (`docker-compose.yml`) | Dokploy (`docker-compose.dokploy.yml`) |
|---|---|---|
| Ports | `5678:5678` exposé | Aucun (Traefik routing) |
| Variables | `env_file: .env` + `${...}` | `${...}` uniquement (UI Dokploy) |
| SearXNG | `./searxng-settings.yml` | Auto (conteneur init) |
| Restart | non défini | `unless-stopped` |
| Domaine | `localhost:5678` | Via l'onglet Domains de Dokploy |

**Déploiement rapide** :
1. Créer un service Compose dans Dokploy (source GitHub, path `./docker-compose.dokploy.yml`)
2. Ajouter les variables dans l'onglet **Environment** (voir `.env.example`)
3. Configurer le domaine (onglet **Domains** → host, port `5678`)
4. **Deploy**

> Guide complet : **[docs/dokploy.md](docs/dokploy.md)**

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  docker-compose.yml / docker-compose.dokploy.yml                 │
│                                                                   │
│  n8n ───── HTTP ─────► sandbox-api ── gRPC ──► sandbox-runner-1  │
│   │                         │                        │           │
│   │                         │                   sandbox containers│
│   │                         │                                     │
│   ├── TCP :5679 ──────► task-runners                              │
│   │                    ├─ JS Runner (isolé)                       │
│   │                    └─ Python Runner (isolé)                   │
│   │                                                               │
│   ├── depends_on: sandbox-api (healthy)                           │
│   ├── depends_on: postgres (healthy)                              │
│   │                                                               │
│   └── searxng ◄── searxng-init (crée settings.yml)               │
│                                                                   │
│  postgres:17-alpine ← volume db-storage                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## Commandes

```bash
# Démarrer
./start.sh
# ou
docker compose up -d

# Logs
docker compose logs -f n8n
docker compose logs -f task-runners
docker compose logs -f sandbox-api
docker compose logs -f postgres

# Arrêter
docker compose down

# Arrêter + supprimer les volumes (réinitialise tout)
docker compose down -v

# Vérifier la santé des services
docker compose ps

# Shell dans un conteneur
docker compose exec n8n sh
docker compose exec postgres psql -U n8n -d n8n
```

---

## Sécurité

- **Task Runners** : code JS/Python exécuté dans un processus isolé (`n8nio/runners`), pas dans n8n.
- **Sandbox** : code AI exécuté dans des conteneurs DinD isolés (`sandbox-runner-1`).
- `.env` est dans `.gitignore` — ne jamais le committer.
- Seul le port `5678` de n8n est exposé.
- `sandbox-runner-1` tourne en `privileged: true` — jamais exposé à l'extérieur.
- Les certificats mTLS (`sandbox-tls`) restent internes au réseau Docker.
- Les secrets sandbox ne sont transmis qu'aux conteneurs sandbox-api et runner.
- Credentials Postgres hardcodés — pas de risque de mismatch.

---

## Prérequis techniques

- **RAM** : ≥ 4 Go (sandbox DinD + task runners)
- **CPU** : ≥ 2 vCPUs
- **OS** : Linux, macOS, ou WSL2 (Windows)
- **Docker** : Engine 24+ / Compose v2

---

## License

MIT
