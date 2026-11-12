# Team Chat backend

PostgreSQL + Node.js (TypeScript, Fastify, Drizzle) backend for Team Chat:
accounts and Roblox sign-in, workspaces, channels, roles, DMs and groups,
messages, reactions, pins, files on S3, bots, search, notifications and a
live event stream.

```bash
npm ci
npm test                 # against a real PostgreSQL the test run starts itself
cp .env.example .env && docker compose up -d --build
```

Documentation is in [docs/backend](../docs/backend/README.md): the architecture,
[schema and ER diagram](../docs/backend/SCHEMA.md), [API](../docs/backend/API.md),
[message storage](../docs/backend/MESSAGES.md), [bots](../docs/backend/BOTS.md)
and [operations](../docs/backend/OPERATIONS.md).

| Script | |
|---|---|
| `npm run dev` | Run with reload (needs `DATABASE_URL` and `ENCRYPTION_KEY`) |
| `npm run build`, `npm start` | Compile to `dist/` and run it |
| `npm run migrate` | Apply migrations (also done on start) |
| `npm run db:generate -- --name <change>` | Write a migration from `src/db/schema.ts` |
| `npm run typecheck`, `npm test` | |
