#!/usr/bin/env bash
# setup.sh — one-command onboarding for avoca-local-db.
#
# Stands up a local Avoca dev database as a SNAPSHOT of staging (schema + data),
# so you can run the app and iterate on migrations without touching prod or the
# shared staging DB. Checks prerequisites, wires config, verifies your staging
# creds, then builds the local DB. Safe to re-run.
set -euo pipefail
INVOKED_FROM="$PWD"   # capture BEFORE the cd below — the natural WORKTREES_DIR default
                      # for a workbench-shaped checkout (worktrees live where you invoked this from)
cd "$(dirname "${BASH_SOURCE[0]}")"
SELF_REAL_DIR="$(pwd -P)"   # symlink-resolved: avoca-local-db's real, non-workbench location

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
[ -f config.sh ] || { cp config.example.sh config.sh; ok "created config.sh (gitignored, per-machine)"; }
# shellcheck disable=SC1091
. ./config.sh 2>/dev/null || true

# Two paths are genuinely per-machine and can't ship with a working default:
#   AVOCA_NEXT_DIR  — your avoca-next clone (needs packages/db/migrations)
#   WORKTREES_DIR   — where your worktrees live (so `db setdev <slug>` can find one)
# Ask for them interactively instead of erroring out and making you edit a file +
# re-run. Each prompt offers an auto-detected guess — press Enter to accept it.

_persist() {  # _persist VAR value — replace an existing override or append.
  local var="$1" val="$2"
  if grep -qE "^${var}=" config.sh 2>/dev/null; then
    sed -i '' -E "s#^${var}=.*#${var}=\"${val}\"#" config.sh
  elif grep -qE '^: "\$\{'"${var}"':=' config.sh 2>/dev/null; then
    # Replace the templated `: "${VAR:=default}"` line IN PLACE rather than
    # appending a new override at the bottom of the file. Sourcing runs
    # top-to-bottom, so an override appended after this point arrives too late
    # for any OTHER config.sh default computed via `:=` from this var earlier
    # in the file (e.g. PROD_ENV_FILE derives from AVOCA_NEXT_DIR) — that
    # default would lock in the template's stale value before the real
    # override ever took effect.
    sed -i '' -E 's#^: "\$\{'"${var}"':=.*#'"${var}"'="'"${val}"'"#' config.sh
  else
    printf '\n%s="%s"\n' "$var" "$val" >> config.sh
  fi
}
# `read` does NOT perform tilde expansion — a typed "~/code/..." stays a literal
# tilde character, so a later `[ -d "$val/..." ]` check fails against a path
# that doesn't exist. Expand it ourselves before validating/using the answer.
_expand_tilde() {
  case "$1" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

if [ ! -d "${AVOCA_NEXT_DIR:-}/packages/db/migrations" ]; then
  # avoca-local-db and avoca-next are conventionally siblings under one parent
  # (…/avoca/avoca-next-workbench, …/avoca/avoca-next, …/avoca/avoca-local-db) —
  # so check the sibling of THIS script's own real location first.
  GUESS="$(dirname "$SELF_REAL_DIR")/avoca-next"
  [ -d "$GUESS/packages/db/migrations" ] || GUESS="${AVOCA_NEXT_DIR:-$HOME/code/avoca-next}"
  if [ -t 0 ]; then
    printf '  Where is your avoca-next clone? [%s]: ' "$GUESS" >&2
    read -r ans
    ans="$(_expand_tilde "$ans")"
    AVOCA_NEXT_DIR="${ans:-$GUESS}"
    [ -d "$AVOCA_NEXT_DIR/packages/db/migrations" ] \
      || die "still not an avoca-next clone (no packages/db/migrations) at $AVOCA_NEXT_DIR"
    _persist AVOCA_NEXT_DIR "$AVOCA_NEXT_DIR"
  elif [ -d "$GUESS/packages/db/migrations" ]; then
    # No TTY to confirm with (e.g. piped/non-interactive), but the sibling
    # auto-detect itself already found a valid clone — use it rather than
    # dying on a guess that was actually correct.
    AVOCA_NEXT_DIR="$GUESS"
    _persist AVOCA_NEXT_DIR "$AVOCA_NEXT_DIR"
  else
    die "AVOCA_NEXT_DIR ($GUESS) isn't an avoca-next clone (no packages/db/migrations) — set it in config.sh and re-run (no TTY to prompt on)"
  fi
fi
ok "avoca-next: $AVOCA_NEXT_DIR"

if [ -z "${WORKTREES_DIR:-}" ] || [ ! -d "${WORKTREES_DIR:-}" ]; then
  # NOT just an emptiness check: config.example.sh's own conditional default
  # (: "${WORKTREES_DIR:=$HOME/code/avoca-next.worktrees}") already fills this
  # in as non-empty the moment config.sh is sourced — a bare -z check trivially
  # passes and the prompt never fires, even though that default path doesn't
  # exist on a workbench-shaped machine. Also require the directory to exist.
  #
  # The natural default for a workbench-shaped checkout: wherever you invoked
  # this script from is where your worktrees live as siblings.
  GUESS="$INVOKED_FROM"
  if [ -t 0 ]; then
    printf '  Where do your worktrees live? [%s]: ' "$GUESS" >&2
    read -r ans
    ans="$(_expand_tilde "$ans")"
    WORKTREES_DIR="${ans:-$GUESS}"
    _persist WORKTREES_DIR "$WORKTREES_DIR"
  else
    WORKTREES_DIR="$GUESS"
  fi
fi
ok "worktrees: $WORKTREES_DIR"

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
