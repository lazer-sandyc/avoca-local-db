# config.example.sh — copy to config.sh and edit for your machine.
#   cp config.example.sh config.sh
# Values use conditional assignment (: "${VAR:=…}"), so precedence is
# env override > config.sh > default — e.g. `SOURCE_DB=production avoca-dev …`
# wins over the SOURCE_DB set here. config.sh is gitignored (per-machine).

# ── Paths: SET THESE to your machine. The values below are only examples — there is no
#    standard location, so point them at wherever YOUR repos actually live. ──

# Your avoca-next clone. avoca-dev reads its origin/main to seed the migration ledger.
: "${AVOCA_NEXT_DIR:=$HOME/code/avoca-next}"

# Where your avoca-next worktrees live (avoca-dev resolves a <slug> under here).
: "${WORKTREES_DIR:=$HOME/code/avoca-next.worktrees}"

# The local Supabase stack lives in THIS repo by default (LOCAL_DB_DIR = the avoca-local-db
# dir). No need to set it — uncomment only to keep the stack somewhere else:
# : "${LOCAL_DB_DIR:=$HOME/some/other/dir}"

# Schemas mirrored/snapshotted from the source (comma-separated).
: "${APP_SCHEMAS:=public,crm_service_titan,twilio}"

# Global config synced from prod so local matches production (voices, llm_models,
# transcribers, feature_flags, …). The core list lives in avoca-dev (`SYNC_CORE`) and
# GROWS there as prod-only settings bite us. REFERENCE_TABLES adds per-machine EXTRAS
# on top; REFERENCE_SOURCE is where to pull them from (prod — staging is sparse on these).
: "${REFERENCE_TABLES:=}"
: "${REFERENCE_SOURCE:=production}"

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
: "${LOGIN_EMAIL:=avoca-user@avoca.ai}"
: "${LOGIN_PASSWORD:=avoca-pass}"
: "${LOGIN_NAME:=Local Dev}"
