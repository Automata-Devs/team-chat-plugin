# Team Chat backend

A Discord-style persistence and messaging backend for Team Chat:
accounts, workspaces with channels and roles, DMs and group DMs, messages
with replies, mentions, reactions, pins and files, bots, search,
notifications and a real-time event stream. It lives in [`backend/`](../../backend).

| | |
|---|---|
| [SCHEMA.md](SCHEMA.md) | Tables, ER diagram, indexes, retention and cascade rules |
| [API.md](API.md) | Every endpoint, authentication, errors, pagination, rate limits, live events |
| [MESSAGES.md](MESSAGES.md) | Snowflake IDs, pagination, and how message storage scales |
| [BOTS.md](BOTS.md) | Bot accounts, tokens, signed events, commands |
| [OPERATIONS.md](OPERATIONS.md) | Deploying, environment variables, migrations, backups, monitoring |
| [PLUGIN.md](PLUGIN.md) | Connecting Team Chat: what's stored, signing in, restoring |

## Architecture

```text
 Roblox Studio plugin ──HTTPS──▶ ┌─────────────────────────────┐ ──▶ PostgreSQL  (all data)
 bots (REST + Bot token)         │  API instance(s)            │ ──▶ Redis       (cache, rate limits,
                                 │  Fastify · zod · Drizzle    │                  events, worker ids)
 browser (Roblox sign-in) ──────▶│  modules: auth, users, …    │ ──▶ S3 storage  (attachment bytes)
                                 │  job worker (in-process)    │
 clients ◀── SSE /gateway ───────└─────────────────────────────┘ ──▶ bot event URLs (signed POSTs)
```

- **Stateless instances.** Every instance serves the API and runs background
  jobs. With `REDIS_URL` set, any number can run behind a load balancer;
  without it, run one.
- **PostgreSQL holds everything durable.** Redis holds only short-lived
  state, so losing it costs rate-limit counters and open sign-ins, never data.
- **Files never pass through the API.** Clients upload and download with
  short-lived signed S3 URLs; Postgres keeps the metadata.
- **Background work is a Postgres job queue** (`jobs`), filled in the same
  transaction as the change it follows: notifications, bot events, purges.
  A crash can't lose a job, or run one for a change that rolled back.

### Code layout (`backend/src`)

| | |
|---|---|
| `main.ts`, `bootstrap.ts`, `app.ts` | Start-up, wiring, the HTTP app (hooks, errors, modules) |
| `config.ts` | Environment variables, validated at start |
| `db/` | `schema.ts` (Drizzle), the connection pool, migrations |
| `infra/` | Cache (Redis or memory), event bus, S3 storage, job queue, worker-id lease |
| `http/` | Authentication, rate limits, route types |
| `lib/` | Snowflakes, permissions, crypto, validation, URL safety |
| `modules/<area>/` | One folder per API area: `routes.ts` (HTTP and validation), `service.ts` (logic) |
| `modules/access.ts` | Every permission decision |
| `jobs.ts` | Background job handlers: fan-out, bot events, purges, clean-up |

## Run it

```bash
cd backend
cp .env.example .env        # set ENCRYPTION_KEY, POSTGRES_PASSWORD and the S3 keys
docker compose up -d --build
curl localhost:8080/health/ready
```

Without Docker: PostgreSQL 15+ (UTF8) and Node 20+, then `npm ci`,
`npm run build` and `npm start` with `DATABASE_URL` and `ENCRYPTION_KEY`
set. Migrations run on start.

`npm test` runs the tests against a real PostgreSQL it starts itself
(embedded-postgres: no Docker or install needed).

## Security model

The plugin is treated as an untrusted client:

- Identity comes from a password (scrypt) or a verified Roblox OAuth sign-in,
  never from a user id the client sends.
- Every request carries a session token (`Bearer`) or a bot token (`Bot`).
  Both are stored as SHA-256 hashes only, and revoking one works at once.
- Authors, ids, timestamps, permissions and mentions are decided by the
  server. Bodies with unknown fields are refused.
- Every channel, conversation and workspace route goes through
  `modules/access.ts`. What you can't see answers 404, so its existence doesn't leak.
- Bot signing secrets are encrypted at rest (AES-256-GCM), and bot event URLs
  must be public HTTPS (no requests into the server's own network).
- Rate limits per user, bot and IP; slowmode per channel; an audit log of
  security-relevant actions, per user and per workspace.

## The plugin

Team Chat stores every place's chat on the backend by itself, one workspace
per place holding its team chat, DMs and groups, once people have signed in
with Roblox: [PLUGIN.md](PLUGIN.md). Chat
still travels through the place in Team Create; the backend is the safe,
searchable copy, and restores the team chat. Live updates over `/gateway` and
reading history from the backend instead of the place are the next steps.

The simpler team database in [`server/`](../../server) ([../DATABASE.md](../DATABASE.md))
keeps working next to it.

## Known limits

- One PostgreSQL primary. Messages are designed to move to partitions or
  ScyllaDB later ([MESSAGES.md](MESSAGES.md)); that isn't needed below
  hundreds of millions of messages.
- `@everyone` notifies at most 5,000 members per message.
- Search is Postgres full-text with the `simple` configuration (no stemming,
  works for any language). A dedicated search engine is the next step at
  large scale.
- Bot event URLs are checked against private addresses when saved and before
  every delivery, but DNS that changes between the check and the request
  (DNS rebinding) isn't fully prevented. Route outgoing traffic through an
  egress proxy if that matters to you.
