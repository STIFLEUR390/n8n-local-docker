# n8n Local — Docker Compose (OpenRouter + Postgres Alpine)

Stack n8n en local avec **AI Assistant** (OpenRouter), **sandbox** Docker-in-Docker intégrée, **SearXNG** pour le web search, et **PostgreSQL 17 Alpine** comme base de données.

> **Aucune API externe** n'est appelée sauf **OpenRouter** pour les fonctions AI.
> Le web search utilise SearXNG bundlé (100% local).

---

## Composants

| Service            | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| **n8n**            | Workflow editor, AI Assistant — `http://localhost:5678`                  |
| **sandbox-certs**  | Génère les certificats TLS mTLS pour le sandbox (run once)              |
| **sandbox-api**    | API de contrôle du sandbox (exécution de code par l'AI Assistant)       |
| **sandbox-runner-1** | Runner DinD (Docker-in-Docker) — exécution isolée du code              |
| **postgres**       | PostgreSQL 17 Alpine — base de données de n8n                            |
| **searxng**        | Moteur de recherche web local pour l'AI Assistant                       |

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

# 2. Lance le stack (démarre tout + corrige les permissions)
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

Toutes les valeurs sont modifiables dans **`.env`** (source unique de vérité).

### AI — OpenRouter (par défaut)

```env
N8N_INSTANCE_AI_MODEL_API_KEY=sk-or-xxx          # ta clé OpenRouter
N8N_INSTANCE_AI_MODEL=openrouter/anthropic/claude-3.7-sonnet
```

Modèles disponibles via OpenRouter :
- `openrouter/anthropic/claude-3.7-sonnet`
- `openrouter/openai/gpt-4o`
- `openrouter/deepseek/deepseek-chat`

### AI — Endpoint OpenAI-like (optionnel)

Pour utiliser un service local compatible OpenAI (Ollama, LM Studio, vLLM…) sans clé externe, décommente dans `.env` :

```env
N8N_INSTANCE_AI_MODEL=openai/gpt-4o
N8N_INSTANCE_AI_MODEL_URL=http://host.docker.internal:1234/v1
N8N_INSTANCE_AI_MODEL_API_KEY=sk-no-key   # souvent optionnel en local
```

### PostgreSQL

```env
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=change-me-postgres-password
```

n8n migre automatiquement de SQLite vers PostgreSQL au premier démarrage.

---

## Déploiement sur Dokploy

Un compose dédié (`docker-compose.dokploy.yml`) est fourni pour le déploiement sur un VPS via [Dokploy](https://dokploy.com).

| | Local (`docker-compose.yml`) | Dokploy (`docker-compose.dokploy.yml`) |
|---|---|---|
| Ports | `5678:5678` exposé | Aucun (Traefik routing) |
| Variables | `env_file: .env` + `${...}` | `${...}` uniquement (UI Dokploy) |
| SearXNG config | `./searxng-settings.yml` | `../files/searxng-settings.yml` |
| Restart | non défini | `unless-stopped` |
| Domaine | `localhost:5678` | Via l'onglet Domains de Dokploy |

**Déploiement rapide** :
1. Créer un service Compose dans Dokploy (source GitHub, path `./docker-compose.dokploy.yml`)
2. Ajouter les variables dans l'onglet **Environment** (voir `.env.example`)
3. Monter `searxng-settings.yml` via `../files/` ou File Mounts
4. Configurer le domaine (onglet **Domains** → host, port `5678`)
5. **Deploy**

> Guide complet (mise à jour, sauvegardes, rollback) : **[docs/dokploy.md](docs/dokploy.md)**

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  docker-compose.yml                                      │
│                                                          │
│  n8n ──────── HTTP ──────► sandbox-api ── gRPC ──► runner-1
│   │                           │                        │
│   │                           │                   sandbox containers
│   │                           │
│   ├── env_file (.env)         └── healthcheck
│   │
│   ├── depends_on: sandbox-api (healthy)
│   ├── depends_on: postgres (healthy)
│   │
│   └── searxng (web search local)
│
│  postgres:17-alpine ← db-storage volume
└─────────────────────────────────────────────────────────┘
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

- `.env` est dans `.gitignore` — ne jamais le committer.
- Seul le port `5678` de n8n est exposé.
- `sandbox-runner-1` tourne en `privileged: true` (Docker-in-Docker) — jamais exposé à l'extérieur.
- Les certificats mTLS (`sandbox-tls`) sont générés au démarrage et restent internes au réseau Docker.
- Les secrets sandbox (`SANDBOX_API_KEYS`, etc.) ne sont transmis qu'aux conteneurs sandbox-api et runner.
- Le mot de passe PostgreSQL et la clé API sont dans `.env` uniquement.

---

## Prérequis techniques

- **RAM** : ≥ 4 Go (le sandbox DinD nécessite de la marge)
- **CPU** : ≥ 2 vCPUs
- **OS** : Linux, macOS, ou WSL2 (Windows)
- **Docker** : Engine 24+ / Compose v2

---

## License

MIT
