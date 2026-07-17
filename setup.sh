#!/usr/bin/env bash
# setup.sh — one-command onboarding for avoca-local-db.
#
# Stands up a local Avoca dev database as a SNAPSHOT of staging (schema + data),
# so you can run the app and iterate on migrations without touching prod or the
# shared staging DB. Checks prerequisites, wires config, verifies your staging
# creds, then builds the local DB. Safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

say()  { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { echo "  ✓ $*"; }
die()  { echo "setup: $*" >&2; exit 1; }

say "1/4  prerequisites"
for c in docker supabase psql pg_dump; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else
    case "$c" in
      docker)       die "missing 'docker' — install a Docker engine (Docker Desktop, OrbStack, or colima).";;
      supabase)     die "missing the 'supabase' CLI — brew install supabase/tap/supabase";;
      psql|pg_dump) die "missing '$c' (Postgres client) — 'brew install libpq && brew link --force libpq', or any postgresql@NN formula / Postgres.app";;
    esac
  fi
done

say "2/4  config"
if [ -f config.sh ]; then ok "config.sh present"
else cp config.example.sh config.sh; ok "created config.sh from the example (edit paths if your layout differs)"; fi
# shellcheck disable=SC1091
. ./config.sh 2>/dev/null || true

say "3/4  staging credentials"
CREDS="${AVOCA_CREDS_FILE:-$HOME/.avoca/postgres.env}"
if [ -f "$CREDS" ] && grep -q '^STAGING_POSTGRES_URL=' "$CREDS"; then
  ok "$CREDS has STAGING_POSTGRES_URL"
else
  cat >&2 <<EOF
  ✗ $CREDS is missing STAGING_POSTGRES_URL.

    Get your personal Postgres creds from Jackson's 1Password share, then:
      mkdir -p ~/.avoca && chmod 700 ~/.avoca
      # write these two lines into ~/.avoca/postgres.env:
      #   STAGING_POSTGRES_URL=postgres://...
      #   PROD_POSTGRES_URL=postgres://...
      chmod 600 ~/.avoca/postgres.env

    Then re-run ./setup.sh
EOF
  exit 1
fi

say "4/4  build the local DB (staging snapshot + login user)"
./avoca-dev setup

LOGIN="$(grep -E '^LOGIN_EMAIL=' config.sh 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
cat <<EOF

Done — your local DB is a snapshot of staging, with a login user.
  • start the app:   ./avoca-dev up <worktree>
  • sign in:         ${LOGIN:-your @avoca.ai seed user} at /signin?auth=password  (@avoca.ai = admin)
  • test teams:      ./avoca-dev seed        (optional — English/Spanish agents for transfer tests)
  • fill dropdowns:  SOURCE_DB=production ./avoca-dev reference   (staging has no voices/llm_models)
EOF
