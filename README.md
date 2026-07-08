# avoca-local-dev

A local development database for **avoca-next** — a schema-accurate mirror of prod that
holds **no prod data / no PII**, so you can run the app, iterate on migrations, and test
against your own synthetic fixtures without touching production.

One command flips a worktree between the local DB and prod, and one command starts a
seamless local dev loop. Prod is only ever **read** (a schema dump); it is never written.

## Why

- **Iterate on migrations locally** — `db:up` runs your unmerged migrations against a copy
  of prod's schema, and you can regenerate Supabase types from local.
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
```

`setup` is one-time (idempotent; safe to re-run — it skips the load if the schema is already there).

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
| `avoca-dev setup` | Stand up local Supabase, load prod's schema (schema-only), grant the Supabase roles, seed the migration ledger. |
| `avoca-dev seed` | Load synthetic fixtures (`seed/*.sql`) + a login user, and (idempotent, best-effort) provision a Twilio subaccount per seeded team. |
| `avoca-dev db setdev [wt]` | Point a worktree's env (apps/web + apps/dashboard) at the **local** DB. |
| `avoca-dev db setprod [wt]` | Revert it to **prod** (strips the local overrides). |
| `avoca-dev db status [wt]` | Show which DB each app is on. |
| `avoca-dev up [wt]` | `setdev` + drop any prod-baked `.next` + `pnpm dev`, in one shot. |
| `avoca-dev oauth <id> <secret>` | Wire Google sign-in on the local stack (needs a stack restart). |
| `avoca-dev trim` | Cut the Supabase stack to the ~7 containers the app uses. |
| `avoca-dev twilio provision [team]` | Provision a subaccount for one team, or (no arg) every seeded team lacking one. Idempotent. |
| `avoca-dev twilio deprovision [team]` | Reclaim one team, or (no arg) **all** local subaccounts — release numbers, close the subaccount, clean rows. Tag-gated: only ever closes subaccounts tagged `avoca-dev-local`, so it can never touch a real customer's. |
| `avoca-dev twilio status` | Audit the subaccounts we provisioned. |
| `avoca-dev status` | Show the stack, the DB, and which worktrees point where. |

**Telephony lifecycle.** `seed` idempotently provisions a real Twilio subaccount per seeded team (best-effort — skipped if ISV creds aren't present), so number-buying works out of the box. These are real actions on Avoca's ISV Twilio account (subaccounts; any numbers you buy are real, ~$1/mo). Every subaccount is tagged `avoca-dev-local …` in its FriendlyName, and `deprovision` is **tag-gated** — it can only ever close subaccounts carrying that tag, never a real customer's. **When you close a plan/worktree, run `avoca-dev twilio deprovision`** (no arg) to reclaim everything, so nothing lingers on Avoca's account. If you create extra test teams via the UI, name them with `avoca-dev-local` so their subaccounts are reclaimable too.

## Google sign-in (optional, nicer than password)

1. Google Cloud Console → create an OAuth **Web** client. Authorized redirect URI:
   `http://127.0.0.1:54321/auth/v1/callback`. Add yourself as a test user.
2. `./avoca-dev oauth <client-id> <client-secret>`
3. Restart the stack: `(cd "$LOCAL_DB_DIR" && supabase stop && supabase start)` — preserves data.
4. Browse the app at **http://127.0.0.1:3000** (matches the local `site_url`; cookies need one host).

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
