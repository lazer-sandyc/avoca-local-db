# avoca-local-dev

A local development database for **avoca-next** — a schema-accurate mirror of prod that
holds **no prod data / no PII**, so you can run the app, iterate on migrations, and test
against your own synthetic fixtures without touching production.

One command flips a worktree between the local DB and prod, and one command starts a
seamless local dev loop. Prod is only ever **read** (a schema dump); it is never written.

## Why

- **Iterate on migrations locally** — `avoca-dev migrate` runs your unmerged migrations against a
  copy of prod's schema and `avoca-dev types` regenerates Supabase types from it, so you find the
  right migration shape cheaply before it's merged. See [Migrations: cheap local loop → PR](#migrations-cheap-local-loop--pr).
- **Test the real app end-to-end** — auth, `supabase.from()` queries, admin, everything —
  against synthetic teams/agents you control, not real customer data.
- **No PII risk** — the mirror is schema-only; the only rows are the fixtures you seed.

## Prerequisites

- **A Docker engine** — Docker Desktop, OrbStack, colima, Rancher Desktop, any of them. This is
  required by the Supabase CLI: `supabase start` runs the stack (Postgres + GoTrue auth +
  PostgREST + Kong gateway + …) as containers; there is no non-Docker mode. We use the Supabase
  stack rather than a bare Postgres because the app needs auth (GoTrue) and every
  `supabase.from()` query (PostgREST), and the prod schema dump assumes the Supabase base
  (the `auth` schema + the `anon`/`authenticated`/`service_role` roles).
- The Supabase CLI, plus `psql` + `pg_dump` (Postgres 15+ client).
- An avoca-next clone with a working dev env (`vercel env pull` done in `apps/web`), so the
  tool can read the prod DB url for the **schema** dump (read-only).

## Setup

```sh
cp config.example.sh config.sh      # edit paths for your machine (or use env overrides)
./avoca-dev setup                   # stand up the local Supabase stack + load prod's schema
./avoca-dev seed                    # synthetic enterprise/teams/agents + a login user
./avoca-dev db setdev <worktree>    # point your avoca-next worktree's env at the LOCAL db
```

`setup` is one-time (idempotent; safe to re-run — it skips the schema load if it's already there). It also
loads **reference data** — the global lookup tables the app needs to work (`voices`, `llm_models`,
`transcribers`; the `REFERENCE_TABLES` list), copied data-only from prod (READ-ONLY, no PII). Add more tables
to that list as you hit empty dropdowns, then re-run `avoca-dev reference`.

## Daily use

```sh
./avoca-dev up <worktree>           # point that worktree local + drop stale bundle + pnpm dev
```

`<worktree>` is a slug under your worktrees dir, an absolute path, or empty for the canonical clone.
Open the app at **http://localhost:3000** (or 127.0.0.1 — but pick one host and stick to it; see Gotchas).

Log in with the seeded user (`LOGIN_EMAIL` / `LOGIN_PASSWORD`, an `@avoca.ai` address = admin) at
`/signin?auth=password`, or wire Google (below) and just click Sign in with Google.

## Commands

| Command | What it does |
|---|---|
| `avoca-dev setup` | Stand up local Supabase, load prod's schema (schema-only), grant the Supabase roles, seed the migration ledger, load reference data. |
| `avoca-dev reference` | (Re)load global lookup data the app needs — `voices`, `llm_models`, `transcribers` (the `REFERENCE_TABLES` list) — data-only from prod (READ-ONLY, no PII). Idempotent. |
| `avoca-dev seed` | Load synthetic fixtures (`seed/*.sql`) + a login user. (No Twilio — provision on demand.) |
| `avoca-dev duplicate-bp <id>` | Copy a modular blueprint (row + versions + assistant variables) from prod (READ-ONLY) so the builder / clone-from-template works. Idempotent. |
| `avoca-dev duplicate-team <id>` | Copy a real prod team's **config** into local — agents, voice assistants, transfer destinations, variables, and any blueprints they use. **Not** its runtime data (calls/CRM/analytics); phone numbers are dropped. Also provisions a local Twilio **subaccount** (best-effort) so the team is testable — you still buy a test number manually in the UI. See safety notes below. |
| `avoca-dev delete-team <id>` | Inverse of `duplicate-team` — releases the team's local Twilio subaccount (tag-gated) then purges its config from local. The DB is shared across all worktrees, so remove a test team when you're done with it (not per-worktree). |
| `avoca-dev db setdev [wt]` | Point a worktree's env (apps/web + apps/dashboard) at the **local** DB. |
| `avoca-dev db setprod [wt]` | Revert it to **prod** (strips the local overrides). |
| `avoca-dev db status [wt]` | Show which DB each app is on. |
| `avoca-dev migrate [up\|pending\|executed\|down] [wt]` | Run the worktree's **unmerged** migrations against the LOCAL DB (default `up`). Wraps `pnpm db:up`, exporting the local `POSTGRES_*` umzug needs — and hard-pins the target to local, so it can never touch prod. |
| `avoca-dev types [wt]` | Regenerate `packages/db/src/generated/supabase.generated.ts` from the **local** schema (the repo's own `gen-supabase-types` types against prod). Run it after `migrate` so your types reflect the migration you just applied, before it's merged. |
| `avoca-dev up [wt]` | `setdev` + drop any prod-baked `.next` + `pnpm dev`, in one shot. |
| `avoca-dev oauth <id> <secret>` | Wire Google sign-in on the local stack (needs a stack restart). |
| `avoca-dev trim` | Cut the Supabase stack to the ~7 containers the app uses. |
| `avoca-dev twilio provision [team]` | Provision a subaccount for one team, or (no arg) every seeded team lacking one. Idempotent. |
| `avoca-dev twilio deprovision [team]` | Reclaim one team, or (no arg) **all** local subaccounts — release numbers, close the subaccount, clean rows. Tag-gated: only ever closes subaccounts tagged `avoca-dev-local`, so it can never touch a real customer's. |
| `avoca-dev twilio status` | Audit the subaccounts we provisioned. |
| `avoca-dev status` | Show the stack, the DB, and which worktrees point where. |

**Telephony lifecycle.** Twilio is **not** touched by `seed`. You provision a subaccount and buy numbers **from the app UI**, when you actually need them — these are real actions on Avoca's ISV Twilio account (subaccounts; any numbers you buy are real, ~$1/mo). The CLI's role is only **teardown + audit**: `avoca-dev twilio deprovision` reclaims subaccounts and `avoca-dev twilio status` audits them. `deprovision` is **tag-gated** — it can only ever close subaccounts whose FriendlyName carries the `avoca-dev-local` tag, never a real customer's. **When you close a plan/worktree, run `avoca-dev twilio deprovision`** (no arg) to reclaim everything, so nothing lingers on Avoca's account. So the UI-provisioned subaccounts are reclaimable, name any test teams you create with `avoca-dev-local`. (There's still an `avoca-dev twilio provision` fallback if you ever need to seed a subaccount without the UI.)

## Migrations: pull prod → local, push local → PR

Local is a **point-in-time** mirror: `setup` dumps prod's schema once and seeds the umzug ledger from `origin/main`. Two flows keep it useful — one to stay current with prod, one to ship your own changes.

### Pull: keep local current with prod

As prod merges PRs, new migrations land on `main` and local drifts behind. The ledger was seeded from `origin/main` **at setup**, so anything merged *after* is "pending" locally — `migrate up` runs exactly those.

```sh
# incremental — preserves your fixtures + duplicated teams
cd <worktree> && git fetch origin main && git merge origin/main   # bring in the new migration files
avoca-dev migrate up <worktree>                                    # umzug runs only the ones that merged after setup
```

Or, when you want local to exactly match prod HEAD (or an incremental run hits a non-idempotent migration):

```sh
# full re-mirror — clean slate, drops fixtures / duplicated teams
avoca-dev reset          # supabase db reset + re-dump CURRENT prod schema + reseed the ledger
avoca-dev seed           # re-add fixtures (+ re-`duplicate-team` any you need)
```

Each pulled migration gets recorded in the local ledger, so a repeat `migrate up` is a clean no-op. This session's own example: merging `main` brought 4 newly-merged prod migrations that `migrate up` applied to local in one pass.

### Push: author a migration → PR

The other direction — a migration is **cheap to iterate while it's unmerged** and only becomes immutable once it deploys. The loop:

```sh
# 1. write / edit the migration
$EDITOR <worktree>/packages/db/migrations/<ts>_<name>.sql

# 2. apply it to LOCAL (only the unmerged ones run — the ledger is seeded from origin/main)
avoca-dev migrate up <worktree>

# 3. regen types from the LOCAL schema, so code sees the new columns before it's merged
avoca-dev types <worktree>

# 4. test against local (app, data-path tests). Not happy with the migration?
#    while it's unmerged you just EDIT THE FILE and reapply from a clean slate:
avoca-dev reset                 # rebuild schema from prod + reseed the ledger from origin/main
avoca-dev migrate up <worktree> # your edited migration runs fresh
avoca-dev seed                  # re-add fixtures
```

**Reapplying an edited migration.** Once a migration is in the local ledger, `migrate up` won't re-run it — `reset` is the clean reapply (it rebuilds the schema and reseeds the ledger from `origin/main`, so every unmerged migration, including your edited one, runs fresh). That's the whole reason to iterate locally: you can rewrite the *same* migration file as many times as review demands.

**Convert to a PR.**

1. Lint it: `pnpm --filter @avoca/db db:lint` (squawk).
2. Commit the migration **and** the locally-regenerated `supabase.generated.ts` together.
3. Open the PR. **While it's unmerged the migration file is still yours to edit** — respond to review by amending it in new commits (never rewrite history). This is exactly how `#13061` evolved: review moved it from `customer_phone` + `consumed_at` to `caller_id` + `received_call_id` + `source_call_id`, all in the same file, before merge.
4. **The boundary:** once the PR **merges and deploys to prod**, that migration is frozen. Any further schema change is a *new* migration, never an edit to the old one — prod has already run it, and the ledger is append-only.

So: mutate freely on local and in the open PR; append-only after deploy. The local DB lets you find the right shape before you cross that line.

## Copying real config from prod (`duplicate-bp` / `duplicate-team`)

When a synthetic team isn't enough — you want a real team's agents/blueprints to reproduce something — pull a **config-only** copy from prod. How it stays safe:

- **Prod is READ-ONLY.** Rows are read with `pg_dump`/`COPY` and written only to your local DB.
- **Config, not runtime.** `duplicate-team` copies a curated allowlist (`teams`, `voice_assistants`, `assistant_configs` + versions, `phone_numbers`, `transfer_destinations` + assistants, `assistant_variables` + versions) and auto-pulls any blueprints those agents reference. It does **not** copy calls, transcripts, CRM, analytics, or logs.
- **No owner PII.** The copied team is re-attached to the synthetic seed owner + enterprise (`SEED_OWNER_ID` / `SEED_ENTERPRISE_ID`); real `auth.users`/`profiles` are never copied. (Run `seed` first.)
- **Agent provider handles are scrubbed.** `assistant_configs.vapi_assistant_id` (and any other external identifier) is NULLed on the way in, so no local edit can push to the real Vapi/ElevenLabs assistant.
- **Phone numbers are dropped entirely, not copied.** The app's phone actions (*Set custom testing domain*, *Swap*, *provider-agnostic routing*) act on the real Twilio number — by its stored SID, or by **identifying it in Twilio via its E.164** when the SID is missing. Once you have Avoca ISV creds locally (required to test telephony — see Telephony), that lookup authenticates to the ISV master, which owns the real number, and could **repoint it and hijack production inbound calls.** Keeping the numbers as any kind of config is a standing risk, so `duplicate-team` deletes them and clears the referencing columns (`voice_assistants.*_inbound_call_phone_id`, matching `transfer_destinations.number`). Zero real digits land in any table.
- **This forces the correct flow anyway:** to test telephony you provision a fresh *local* number, which you'd have to do regardless — so nothing of value is lost by dropping prod's. `duplicate-team` auto-creates the local tagged **subaccount** for you (best-effort, if ISV creds are present); you then buy a fresh number on it in the UI + point a tunnel at `localhost`.

Both commands are idempotent (they drop any prior copy first). Extend the team allowlist in `cmd_duplicate_team` as you find config that doesn't come across.

**Lifecycle / teardown.** The local DB is one stack shared by every worktree, so a duplicated team lives until *you* remove it — teardown is per-team, not per-worktree. When you're done with a test team, `avoca-dev delete-team <id>` releases its local Twilio subaccount (tag-gated) and purges its rows. Blueprints are left in place (they're global and may be shared by other teams).

## Google sign-in (optional, nicer than password)

1. Google Cloud Console → create an OAuth **Web** client. Authorized redirect URI:
   `http://127.0.0.1:54321/auth/v1/callback`. Add yourself as a test user.
2. `./avoca-dev oauth <client-id> <client-secret>`
3. Restart the stack: `(cd "$LOCAL_DB_DIR" && supabase stop && supabase start)` — preserves data.
4. Browse the app at **http://127.0.0.1:3000** (matches the local `site_url`; cookies need one host).

## Prod-read safety

`avoca-dev` only ever **reads** prod, and every read is hardened so it cannot slow down or take down prod — and so it's attributable. All verified live against the Avoca project.

- **Read-only, server-enforced.** Every `psql` prod read injects `SET default_transaction_read_only=on`; a write errors out (`cannot execute UPDATE in a read-only transaction`). It's the Postgres server refusing, not a promise in our code.
- **Time-bounded + lock-yielding.** `statement_timeout=60s` (no query runs long), `lock_timeout=3s` (never *waits* on a lock — can't block or be blocked), `idle_in_transaction_session_timeout=120s` (a stalled session can't sit on locks). Plus a client-side `timeout` kill (needs coreutils `timeout`/`gtimeout`).
- **Name-tagged.** `SET application_name='avoca-dev-local'` — every `psql` connection is identifiable in `pg_stat_activity` / Supabase logs, so during an incident it's filterable and instantly dismissable.
- **Session endpoint (`:5432`).** The url is rewritten from the transaction pooler (`:6543`) to session mode. The transaction pooler **strips** libpq startup options (so `PGOPTIONS`/startup `application_name` silently don't apply — verified); session mode honors the `SET`s above.
- **Audit log.** Every prod read appends to `~/.avoca-dev/prod-reads.log` (timestamp + operation, url redacted) — your own independent record of exactly what ran and when.

**One honest limitation:** the `pg_dump` reads (the one-time schema mirror + the tiny reference tables) can't be server-tagged — `pg_dump` takes no `SET` and the pooler strips a startup `application_name`, so they surface as `Supavisor` in `pg_stat_activity`. They're still read-only **by nature** (`pg_dump` only issues `SELECT` + `ACCESS SHARE` locks), bounded by `--lock-wait-timeout=3000` + the client timeout, and captured in the audit log. Only the `psql` config reads (`duplicate-team`/`-bp`) get the full server-side tag.

Net: a read-only, time-bounded, lock-yielding client that can't write or run long, self-identifying for `psql` reads, with your own audit trail for all of them. "Was it you?" → *filter `application_name=avoca-dev-local`, and here's my read log.*

## Gotchas (learned the hard way)

- **`NEXT_PUBLIC_*` is compile-time.** The browser's Supabase URL is baked into the bundle when
  `pnpm dev` starts. If you change the DB pointer while dev is running, the *browser* keeps calling
  the old DB until you restart **and** clear `.next`. `avoca-dev up` does both for you — use it.
- **Two DB surfaces.** `POSTGRES_*` (migrations/type-gen) *and* the Supabase client
  (`NEXT_PUBLIC_SUPABASE_URL` + keys, used by auth and every `supabase.from()`). This tool points
  **both**; pointing only `POSTGRES_*` leaves the running app on prod.
- **Grants.** A `pg_dump --no-privileges` mirror has no grants for `anon`/`authenticated`/`service_role`,
  so PostgREST returns `permission denied for schema public`. `setup` (and `avoca-dev grants`) fix this.
- **One host.** `localhost` and `127.0.0.1` are different cookie origins. Pick one for login + browsing.

## Sharing

This is Avoca-tuned but path-parameterized (`config.sh`). To share: this repo + each person copies
`config.example.sh → config.sh`. The eventual home is a kit inside avoca-next (`scripts/local-db/`),
but it lives standalone first so it can be tried without shipping anything into the client repo.
