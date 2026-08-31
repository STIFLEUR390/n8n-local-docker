#!/usr/bin/env bash
# ============================================================================
# start.sh — Lance le stack n8n local et corrige les permissions.
# Usage : ./start.sh
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_ID="$(id -u)"
GROUP_ID="$(id -g)"

# --- Couleurs ---
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[1;31m%s\033[0m\n" "$*"; }

# --- Vérification des prérequis ---
for cmd in docker; do
  if ! command -v "$cmd" &>/dev/null; then
    red "✗ '$cmd' introuvable. Installe Docker Engine + Docker Compose v2."
    exit 1
  fi
done

if ! docker compose version &>/dev/null; then
  red "✗ 'docker compose' (v2) indisponible."
  exit 1
fi

# --- Fichiers requis ---
cd "$PROJECT_DIR"

if [ ! -f .env ]; then
  yellow "▶ .env absent — création depuis .env.example"
  cp .env.example .env
  yellow "  Édite .env maintenant : nano .env"
fi

if [ ! -f searxng-settings.yml ]; then
  yellow "▶ searxng-settings.yml absent — création avec les valeurs par défaut"
  cat > searxng-settings.yml <<'EOF'
use_default_settings: true
search:
  formats:
    - html
    - json
EOF
fi

# --- Lancement du stack ---
green "▶ docker compose up -d …"
docker compose up -d

# --- Attente que les services critiques soient healthy ---
green "▶ Attente de sandbox-api (health check) …"
WAIT=0
TIMEOUT=120
until docker compose ps sandbox-api 2>/dev/null | grep -q "healthy"; do
  sleep 2
  WAIT=$((WAIT + 2))
  if [ "$WAIT" -ge "$TIMEOUT" ]; then
    red "✗ sandbox-api n'est pas devenue healthy en ${TIMEOUT}s"
    docker compose logs --tail=30 sandbox-api
    exit 1
  fi
done
green "  ✓ sandbox-api healthy (${WAIT}s)"

green "▶ Attente de postgres (health check) …"
WAIT=0
until docker compose ps postgres 2>/dev/null | grep -q "healthy"; do
  sleep 2
  WAIT=$((WAIT + 2))
  if [ "$WAIT" -ge "$TIMEOUT" ]; then
    red "✗ postgres n'est pas devenue healthy en ${TIMEOUT}s"
    docker compose logs --tail=30 postgres
    exit 1
  fi
done
green "  ✓ postgres healthy (${WAIT}s)"

# --- Correction des permissions ---
green "▶ Correction des permissions (owner → ${USER_ID}:${GROUP_ID}) …"

# Fichiers du projet
chown -R "${USER_ID}:${GROUP_ID}" "$PROJECT_DIR"
chmod 600 "$PROJECT_DIR/.env"

# Docker volumes nommés (owned by Docker, on ne peut pas chown depuis l'hôte)
# mais on s'assure que les conteneurs tournent avec les bons droits.
# Si tu utilises des bind-mounts à la place, ajuste ici :
#   chown -R "${USER_ID}:${GROUP_ID}" /chemin/vers/tes/bind/mounts

green "  ✓ Permissions corrigées"

# --- Statut final ---
green "════════════════════════════════════════"
green "  n8n prêt → http://localhost:5678"
green "════════════════════════════════════════"
echo ""
docker compose ps
echo ""
green "Commandes utiles :"
yellow "  docker compose logs -f n8n       # suivre les logs n8n"
yellow "  docker compose logs -f sandbox-api  # suivre les logs sandbox"
yellow "  docker compose down             # arrêter le stack"
yellow "  docker compose down -v          # arrêter + supprimer les volumes"
