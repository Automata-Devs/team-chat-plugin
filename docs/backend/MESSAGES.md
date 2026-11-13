# Messages: IDs, pagination, storage

## Snowflake IDs

Every user, workspace, channel, message, file and notification has a 64-bit
ID made by [`lib/snowflake.ts`](../../backend/src/lib/snowflake.ts):

```text
 0 | 42 bits: ms since 2024-01-01 | 10 bits: worker | 12 bits: sequence
```

- **Sortable by time.** A later message has a larger id, so `ORDER BY id`
  is time order and needs no separate timestamp index. `snowflakeAt(date)`
  turns a date into an id bound for "before/after this time" queries.
- **Made without coordination.** Each running instance has its own worker
  id (0-1023), so instances never ask each other or the database.
  - With `REDIS_URL`, an instance leases a free worker id on start and renews
    it every 20 seconds. If it loses the lease (Redis gone for over a minute),
    it stops, rather than risk sharing an id.
  - Without Redis, set `WORKER_ID`, which defaults to 0 for one instance.
- **4096 per millisecond per instance.** A full millisecond borrows the next
  one, and a clock that steps back keeps counting from the last time, so
  ids never repeat or go backwards.
- **Strings in JSON**, because JavaScript and Luau numbers are exact only to 2^53.
- The 42-bit time runs out in the year 2163.

## Pagination

Lists are paged with ids, never with offsets: a page costs the same however
deep into history it is, and messages arriving meanwhile don't shift it.

`GET /channels/:id/messages` answers newest first. Use at most one of these:

| | Returns |
|---|---|
| (none) | The newest `limit` messages |
| `before=<id>` | Older than that id: keep passing the last id of each page |
| `after=<id>` | Newer than that id: for catching up after a gap |
| `around=<id>` | About half older and half newer: jumping to a reply or search result |

`limit` is 1-100 (default 50). Each is a single range scan on the
`(channel_id, id desc)` index. The page's authors, files, reactions and
replied-to messages come from four batched queries, whatever the page size.

## Writing a message

`POST /channels/:id/messages`, in one transaction:

1. Check the sender's permissions in the channel (send, files, embeds,
   @everyone), DM blocks and slowmode.
2. Insert the message with a new snowflake, link the uploaded files, move the
   channel's `last_message_id` forward, and mark it read for the sender.
3. Queue a `message.created` job: notifications and bot events happen after
   commit, so sending stays fast.

Then the message is published to the `channel:<id>` event topic.

**Retries:** a client that resends after a timeout includes the same `nonce`.
The unique `(author_id, nonce)` index means the second send returns the first
message, also when both arrive at the same moment.

## End-to-end encryption

In a place's workspace (one made by `POST /places/:placeKey/workspace`, see
[PLUGIN.md](PLUGIN.md#end-to-end-encryption)) the server only accepts sealed
messages: `content` must be empty or sealed, and `clientData` must be exactly
`{ "e2e": "<sealed>" }`. Anything else is `400 encryption_required`. Other
workspaces and DMs outside a place take readable text as before.

A sealed value is `e2e1:` followed by standard Base64 of
`nonce (12 bytes) || ciphertext || tag (16 bytes)`:

```
master    = HMAC-SHA256(key = place secret, "Team Chat end-to-end key v1")
enc       = HMAC-SHA256(master, "enc")
mac       = HMAC-SHA256(master, "mac")
nonceKey  = HMAC-SHA256(master, "nonce")
nonce     = first 12 bytes of HMAC-SHA256(nonceKey, 16 random bytes || text)
ciphertext = ChaCha20(enc, nonce, counter 1, text)        (RFC 8439)
tag       = first 16 bytes of HMAC-SHA256(mac, "e2e1" || nonce || ciphertext)
```

Openers check the tag (in constant time) before decrypting. Sealed text is
longer than what it hides, so sealed `content` may be up to 24,000
characters; readable text stays at 4,000. The plugin's implementation is
`src/Services/Backend/Seal.luau`; `backend/test/sealing.ts` is the same in
TypeScript, and the tests check that each opens what the other sealed.

## How storage scales

What's built now is one PostgreSQL. Its access patterns are the ones that scale:

- Reads by channel and id range only. No query scans across channels,
  except search, which is scoped to the channels the reader can see.
- No offsets, no `count(*)` over history. Unread counts stop at 100.
- Hot rows are small; files are in S3.

The next steps, in order, each done only when measurements call for it:

1. **Read replicas** for history and search, when reads outgrow one server.
   The writes stay on the primary.
2. **Partition `messages` by id range** (each range is a time range): old
   partitions are cheap to keep, vacuum and archive, and indexes stay small.
   No query changes, because every query already filters on id.
3. **Move messages to ScyllaDB or Cassandra**, as Discord did, when one
   PostgreSQL can't take the write rate. The partition key would be
   `(channel_id, bucket)`, with the bucket a fixed time window derived from the
   snowflake, so one channel's history spreads over partitions of bounded
   size. The clustering key would be `id desc`. That's the same
   channel-plus-id-range access pattern the API already uses. Reactions and
   pins would move with them. Users, workspaces, permissions and everything
   relational stay in PostgreSQL.

What doesn't change in any of these is the API and the ids: clients never
learn where a message is stored.
