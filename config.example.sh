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

# Prod Supabase project ref — used to detect a prod URL baked into a stale
# .next bundle (the compile-time NEXT_PUBLIC split-brain).
PROD_PROJECT_REF="wmizcewjcybhvkpwpmim"

# File holding the PROD db url (POSTGRES_URL=…). `setup` reads it READ-ONLY to
# dump the schema. Typically the app's dev env — run `vercel env pull` there first.
PROD_ENV_FILE="$AVOCA_NEXT_DIR/apps/web/.env.local"

# Seeded password login (an @avoca.ai address gets system admin). With Google
# OAuth wired (avoca-dev oauth) you can ignore this and just sign in with Google.
LOGIN_EMAIL="dev@avoca.ai"
LOGIN_PASSWORD="avoca-local-dev"
LOGIN_NAME="Local Dev"
