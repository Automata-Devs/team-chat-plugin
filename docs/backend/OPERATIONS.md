# Running the backend

## Deploy

### Render with Neon (free to start)

[`backend/render.yaml`](../../backend/render.yaml) is a Render Blueprint for
the backend, next to a Neon database:

1. **Neon:** in your project, copy the **direct** connection string (not the
   one with `-pooler`) and change its ending to `?sslmode=verify-full`.
2. **Render:** New > Blueprint, connect this GitHub repository, and set the
   **Blueprint Path** to `backend/render.yaml`. (The `render.yaml` at the repo
   root is the older team database in `server/`.)
3. Render asks for the secrets:
   - `DATABASE_URL`: the Neon string from step 1.
   - `ROBLOX_OAUTH_CLIENT_ID` and `ROBLOX_OAUTH_CLIENT_SECRET`: leave them empty
     for now.

   `ENCRYPTION_KEY` is generated for you.
4. When the first deploy is live, note its address, such as
   `https://teamchat-backend.onrender.com`. `/health/ready` there should say
   `"ok": true`. The database tables are made on start.
5. **Roblox:** on create.roblox.com, under OAuth 2.0 Apps, create an app.
   - Redirect URL: `https://<your address>/api/v1/auth/roblox/callback`.
   - Scopes: `openid` and `profile`.

   Put its client id and secret in the Render service's Environment, and save
   (it redeploys).
6. **Plugin:** set `DEFAULT_URL` in `src/Config/Backend.luau` to the address
   and build it ([PLUGIN.md](PLUGIN.md)).

`PUBLIC_URL` isn't needed on Render: the service's own address
(`RENDER_EXTERNAL_URL`) is used. On the free plan the service sleeps after 15
minutes without requests, and its first answer after that takes up to a
minute; Team Chat keeps what's waiting until then.

### Docker Compose (one machine)

```bash
cd backend
cp .env.example .env
# ENCRYPTION_KEY:  node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
# POSTGRES_PASSWORD, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY: long random strings
# PUBLIC_URL: the https address people reach the API on
docker compose up -d --build
```

This runs PostgreSQL 17 (UTF8), Redis, MinIO (S3) and the API on port 8080.
Put a TLS proxy in front, for example Caddy:

```text
chat.example.com {
	reverse_proxy localhost:8080
}
```

Set `TRUST_PROXY=true` behind a proxy, so rate limits and the audit log see
real client addresses. Clients download and upload files directly from MinIO
on port 9000, so give it a public https address too (`S3_PUBLIC_ENDPOINT`)
or use a hosted S3 instead.

### Managed services

Anything that runs a Node 20+ container works: Fly.io, Railway, Render,
ECS, Kubernetes. Pair it with:

- **PostgreSQL 15+**: Neon, Supabase, RDS, Cloud SQL, Crunchy. The database
  must be UTF8; the API refuses to start otherwise.
- **Redis** (when running more than one instance): Upstash, ElastiCache.
- **S3-compatible storage**: AWS S3, Cloudflare R2, Backblaze B2. Allow `PUT`
  and `GET` from any origin in the bucket's CORS if browsers will upload.

### Scaling out

Instances are stateless. With `REDIS_URL` set, run as many as you like
behind a load balancer:

- Each leases its own snowflake worker id from Redis.
- Rate limits, sessions and sign-ins are shared through Redis.
- Live events reach every instance through Redis pub/sub, so a `/gateway`
  stream can be on any instance.
- Background jobs are claimed with `FOR UPDATE SKIP LOCKED`, so every instance
  can run them without doing one twice. Set `RUN_JOBS=false` on instances
  that should only serve requests.

Size `DATABASE_POOL_MAX` × instances below PostgreSQL's `max_connections`,
or put PgBouncer in transaction mode in between. That works because
advisory locks are only taken inside transactions; add
`ignore_startup_parameters = statement_timeout` to PgBouncer's config, since
the API sets its statement timeout when it connects.

## Environment variables

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | (required) | `postgres://user:password@host:5432/db` |
| `ENCRYPTION_KEY` | (required) | 32 bytes, base64. Encrypts bot signing secrets. **Back it up**: without it, bots need new secrets |
| `PORT` / `HOST` | `8080` / `0.0.0.0` | |
| `PUBLIC_URL` | `http://localhost:8080` | Where people reach the API: used for the Roblox sign-in redirect |
| `TRUST_PROXY` | `false` | Trust `X-Forwarded-For` |
| `LOG_LEVEL` | `info` | `fatal` … `trace`, `silent` |
| `REDIS_URL` | | Needed for more than one instance |
| `WORKER_ID` | leased from Redis, else `0` | 0-1023, unique per instance |
| `DATABASE_POOL_MAX` | `20` | Connections per instance |
| `DATABASE_STATEMENT_TIMEOUT_MS` | `10000` | Queries running longer are cancelled |
| `SESSION_TTL_DAYS` | `30` | |
| `ALLOW_PASSWORD_SIGNUP` | `true` | `false`: Roblox sign-in only |
| `ROBLOX_OAUTH_CLIENT_ID` / `_SECRET` | | From an OAuth 2.0 app on create.roblox.com with redirect URL `<PUBLIC_URL>/api/v1/auth/roblox/callback` and scopes `openid profile` |
| `ROBLOX_OAUTH_BASE_URL` | `https://apis.roblox.com/oauth` | |
| `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_FORCE_PATH_STYLE` | | Without `S3_BUCKET`, uploads answer 503 |
| `MAX_UPLOAD_BYTES` | `26214400` (25 MB) | |
| `RUN_JOBS` | `true` | |
| `RATE_LIMIT_SCALE` | `1` | Multiplies every rate limit |
| `ALLOW_INSECURE_BOT_URLS` | `false` | Development only: allows `http://` and private bot URLs |

## Migrations

They run on start, holding an advisory lock, so a rolling deploy applies
each once. To run them separately (in a release step): `npm run migrate`.
[SCHEMA.md](SCHEMA.md#migrations) has how to write one.

## Backups and restoring

Two layers:

1. **Continuous (point-in-time recovery).** Use your provider's backups
   (Neon, RDS and Supabase all keep WAL for point-in-time restores), or run
   WAL archiving yourself with pgBackRest or WAL-G. This is what recovers
   from a lost disk with minutes of data loss at most.
2. **Logical dumps** with [`scripts/backup.sh`](../../backend/scripts/backup.sh):
   a compressed `pg_dump` that is checked by reading it back with
   `pg_restore --list`, keeping the newest 14. Run it from cron, and copy
   `backups/` off the machine (to S3, for example).

```bash
# Every night at 03:00
0 3 * * * cd /srv/teamchat/backend && DATABASE_URL=postgres://… ./scripts/backup.sh
```

Files in S3 aren't in these dumps: turn on bucket versioning or replication.
Also keep `ENCRYPTION_KEY` safe and separate.

### Restore

[`scripts/restore.sh`](../../backend/scripts/restore.sh) restores into an
**empty** database and refuses one with tables, so it can't overwrite live data.

```bash
createdb -E UTF8 -T template0 teamchat_restored
DATABASE_URL=postgres://…/teamchat_restored ./scripts/restore.sh backups/teamchat-20261112T030000Z.dump
```

Then stop the API, point `DATABASE_URL` at the restored database, and start
it. Newer migrations run on start. **Test a restore every few months**:
an untested backup isn't one.

## Monitoring

- `GET /health/live`: restart the process when this fails.
- `GET /health/ready`: take the instance out of the load balancer when this
  fails (`503` when the database or Redis doesn't answer). It also reports
  waiting and failed job counts; alert when `failed` grows.
- Logs are JSON (pino), one line per request with its id, status and time,
  and the signed-in user or bot. Tokens, passwords and secrets are redacted.
- When the database goes away, requests answer `503` with `Retry-After: 5`,
  and the pool reconnects by itself when it's back; nothing needs restarting.
- Failed jobs stay in `jobs` with `last_error` for 30 days:
  `select type, attempts, last_error from jobs where attempts >= max_attempts`.

## Security checklist

- Serve the API only over HTTPS.
- Keep `ENCRYPTION_KEY`, the database password and the S3 keys in a secret store.
- Give the database user only this database; no superuser.
- Keep `ALLOW_INSECURE_BOT_URLS=false`.
- Watch the audit log (`audit_log`): sign-in failures, token resets, deletions.
