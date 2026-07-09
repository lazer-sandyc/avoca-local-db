# config.example.sh — copy to config.sh and edit for your machine.
#   cp config.example.sh config.sh
# Every value here can also be overridden by an env var of the same name.
# config.sh is gitignored (it's per-machine), so it's safe to keep local paths here.

# Your canonical avoca-next clone. Used to read the PROD db url for the schema
# dump (read-only) and to seed the migration ledger from origin/main.
AVOCA_NEXT_DIR="$HOME/code/lazer/avoca/avoca-next"

# Where your avoca-next worktrees live (the tool resolves a <slug> under here).
WORKTREES_DIR="$HOME/code/lazer/avoca/avoca-next.worktrees"

# Where the local Supabase stack is kept (a dedicated, stable dir).
LOCAL_DB_DIR="$HOME/code/lazer/avoca/avoca-local-db"

# Schemas mirrored from prod (comma-separated).
APP_SCHEMAS="public,crm_service_titan,twilio"

# Global lookup/reference tables the app needs to function (voice list, LLM
# models, transcribers, …). Copied data-only from prod (READ-ONLY, no PII —
# they're not team-scoped) by `setup` / `avoca-dev reference`. Add any other
# global reference table your flow needs here.
REFERENCE_TABLES="voices,llm_models,transcribers"

# Prod Supabase project ref — used to detect a prod URL baked into a stale
# .next bundle (the compile-time NEXT_PUBLIC split-brain).
PROD_PROJECT_REF="wmizcewjcybhvkpwpmim"

# File holding the PROD db url (POSTGRES_URL=…). `setup` reads it READ-ONLY to
# dump the schema. Typically the app's dev env — run `vercel env pull` there first.
PROD_ENV_FILE="$AVOCA_NEXT_DIR/apps/web/.env.local"

# Supabase personal access token (starts `sbp_`). The SANCTIONED prod-read path:
# the Management API (api.supabase.com/v1/projects/<ref>/database/query) — the
# same API the Supabase MCP wraps — instead of a raw pooler connection that trips
# the authenticator alert. Mint one at supabase.com/dashboard/account/tokens
# (needs Avoca-org access). `export` it so the spawned `supabase` CLI inherits it
# too (no `supabase login` needed). Lives in config.sh (gitignored) — never commit it.
# export SUPABASE_ACCESS_TOKEN="sbp_..."

# Seeded password login (an @avoca.ai address gets system admin). With Google
# OAuth wired (avoca-dev oauth) you can ignore this and just sign in with Google.
LOGIN_EMAIL="dev@avoca.ai"
LOGIN_PASSWORD="avoca-local-dev"
LOGIN_NAME="Local Dev"
