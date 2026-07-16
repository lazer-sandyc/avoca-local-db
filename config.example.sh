# config.example.sh — copy to config.sh and edit for your machine.
#   cp config.example.sh config.sh
# Values use conditional assignment (: "${VAR:=…}"), so precedence is
# env override > config.sh > default — e.g. `SOURCE_DB=production avoca-dev …`
# wins over the SOURCE_DB set here. config.sh is gitignored (per-machine).

# Your canonical avoca-next clone. Used to read the migration files + seed the
# umzug ledger from origin/main.
: "${AVOCA_NEXT_DIR:=$HOME/code/lazer/avoca/avoca-next}"

# Where your avoca-next worktrees live (the tool resolves a <slug> under here).
: "${WORKTREES_DIR:=$HOME/code/lazer/avoca/avoca-next.worktrees}"

# Where the local Supabase stack is kept (a dedicated, stable dir).
: "${LOCAL_DB_DIR:=$HOME/code/lazer/avoca/avoca-local-db}"

# Schemas mirrored/snapshotted from the source (comma-separated).
: "${APP_SCHEMAS:=public,crm_service_titan,twilio}"

# Global lookup/reference tables (voice list, LLM models, transcribers, …). Staging
# has these empty; `SOURCE_DB=production avoca-dev reference` fills them from prod.
: "${REFERENCE_TABLES:=voices,llm_models,transcribers}"

# Prod Supabase project ref — used to detect a prod URL baked into a stale .next
# bundle (the compile-time NEXT_PUBLIC split-brain).
: "${PROD_PROJECT_REF:=wmizcewjcybhvkpwpmim}"

# Which upstream avoca-dev READS to mirror schema / reference data / configs:
#   staging (default) — never touches prod for everyday setup
#   production        — only when you need prod-only config (e.g. an EAS team not on staging)
# Override per-command: `SOURCE_DB=production avoca-dev duplicate-team <id>`.
: "${SOURCE_DB:=staging}"

# Containers to skip on 'supabase start' (the analytics stack is flaky on a cold
# start and unneeded for dev). Widen if other services fail to come up healthy.
: "${SUPABASE_EXCLUDE:=logflare,vector}"

# Avoca's personal Postgres creds (Jackson's 1Password share): a file holding
# STAGING_POSTGRES_URL=… and PROD_POSTGRES_URL=…. `_source_url` reads the one that
# matches SOURCE_DB. chmod 600. Preferred source for both staging and prod.
: "${AVOCA_CREDS_FILE:=$HOME/.avoca/postgres.env}"

# Legacy fallback for the PROD url only (used when AVOCA_CREDS_FILE isn't set up and
# SOURCE_DB=production). The app's Vercel-pulled dev env — run `vercel env pull` there.
: "${PROD_ENV_FILE:=$AVOCA_NEXT_DIR/apps/web/.env.local}"

# Supabase personal access token (starts `sbp_`). Optional — only for the Management
# API prod-read path (api.supabase.com/v1/projects/<ref>/database/query, the same API
# the Supabase MCP wraps). Mint one at supabase.com/dashboard/account/tokens.
# `export` it so the spawned `supabase` CLI inherits it. Never commit it.
# export SUPABASE_ACCESS_TOKEN="sbp_..."

# Seeded password login (an @avoca.ai address gets system admin). With Google OAuth
# wired (avoca-dev oauth) you can ignore this and just sign in with Google.
: "${LOGIN_EMAIL:=dev@avoca.ai}"
: "${LOGIN_PASSWORD:=avoca-local-dev}"
: "${LOGIN_NAME:=Local Dev}"
