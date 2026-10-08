# Cursor public Cloud Agents API

Reviewed October 8, 2026 using Cursor's reference and linked OpenAPI. No API key
was used to execute live business requests during this research. Documentation
support, account access, implementation, and live verification are separate facts.

Sources: [current endpoints](https://cursor.com/docs/cloud-agent/api/endpoints),
[OpenAPI](https://cursor.com/docs-static/cloud-agents-openapi.yaml),
[authentication](https://cursor.com/docs/api),
[legacy v0](https://cursor.com/docs/cloud-agent/api/v0), and
[v0 webhooks](https://cursor.com/docs/cloud-agent/api/webhooks).

## Version and identity boundaries

Base URL: `https://api.cursor.com`. The current API is **v1 Public Beta**.
Its OpenAPI contains 25 paths and 33 HTTP operations. The current reference also
contains 12 documented `/v0/private-workers/*` operations; these are the official
self-hosted control plane, not the private cookie-authenticated web API.
The legacy v0 Agent reference adds 12 operations.

An **Agent** is a persistent workspace/conversation; a **Run** executes one prompt.
Keep their lifecycles separate. v1 provides SSE but its webhooks are not yet
available. Agent token usage cannot supply account subscription pool percentages.
The public API does not document every web preference, read/pin/rename state, or
personal two-pool usage. Those capabilities have separate web evidence.

## All v1 operations

Agent paths use an Agent ID; environment paths use an Environment UUID. Responses
are JSON except for the stream. Secrets expose metadata, never existing values.

| Method | Path | Contract |
| --- | --- | --- |
| POST | `/v1/agents` | Required `prompt.text`; 201 `{agent,run}` |
| GET | `/v1/agents` | `limit` 1–100 (default 20), `cursor`, `prUrl`, `includeArchived`; `{items,nextCursor?}` |
| GET | `/v1/agents/{id}` | Full configuration, repos, `latestRunId`; execution status belongs to Run |
| DELETE | `/v1/agents/{id}` | Permanent deletion; 200 `{id}` |
| POST | `/v1/agents/{id}/runs` | `prompt`, optional `mcpServers,mode`; 201 `{run}`; active run → 409 `agent_busy` |
| GET | `/v1/agents/{id}/runs` | `limit,cursor`; newest first; `{items,nextCursor?}` |
| GET | `/v1/agents/{id}/runs/{runId}` | Status, times, terminal `result/durationMs`, current Agent `git` snapshot |
| GET | `/v1/agents/{id}/runs/{runId}/stream` | SSE; optional `Last-Event-ID` |
| POST | `/v1/agents/{id}/runs/{runId}/cancel` | 200 `{id}`; otherwise 409 `run_not_cancellable` |
| GET | `/v1/agents/{id}/usage` | Optional `runId`; token totals and per-run usage |
| GET | `/v1/agents/{id}/artifacts` | `{items:[{path,sizeBytes,updatedAt}]}` |
| GET | `/v1/agents/{id}/artifacts/download` | Query `path`; `{url,expiresAt}`; 15-minute signed URL |
| POST | `/v1/agents/{id}/archive` | Repeatable idempotent archive; 200 `{id}` |
| POST | `/v1/agents/{id}/unarchive` | Repeatable idempotent restore; 200 `{id}` |
| POST | `/v1/environments` | Required `owner,name,repos,environmentJson`; 201 environment |
| GET | `/v1/environments` | `limit,cursor`; recently updated first |
| GET | `/v1/environments/{id}` | Details and optional `environmentJson,versionId,repoFile` |
| PATCH | `/v1/environments/{id}` | At least one of `name,environmentJson`; atomic; 204 empty body |
| DELETE | `/v1/environments/{id}` | Permanent deletion; 200 `{id}` |
| GET | `/v1/environments/{id}/history` | `limit,cursor`; changes and historical configuration |
| GET | `/v1/environments/{id}/builds` | `cursor`; at most 10 per page |
| GET | `/v1/environments/{id}/builds/{buildId}` | Build status, cause, failure, timestamps |
| GET | `/v1/environments/{id}/builds/active` | `{type:"build",buildId}` or `{type:"universal_image"}` |
| GET | `/v1/environments/{id}/secrets` | Version metadata; `{items,nextCursor:null}` |
| PUT | `/v1/environments/{id}/secrets/{name}` | `value,type?,repos?`; optional query `id`; 200 update / 201 create |
| DELETE | `/v1/environments/{id}/secrets/{name}` | Optional version query `id`; deletion information |
| GET | `/v1/team/secrets` | Team version metadata; `{items,nextCursor:null}` |
| PUT | `/v1/team/secrets/{name}` | `value,type?,repos?`; optional query `id`; 200/201 |
| DELETE | `/v1/team/secrets/{name}` | Optional version query `id` |
| POST | `/v1/sub-tokens` | `forUserEmail` XOR `forUserId`; scoped service-account key; one-hour user token |
| GET | `/v1/me` | API-key metadata; user identity fields may be absent for service accounts |
| GET | `/v1/models` | `{items:[{id,displayName,description?,aliases?,parameters?,variants?}]}` |
| GET | `/v1/repositories` | `{items:[{url}]}`; GitHub App-accessible GitHub repositories only |

### Creation and follow-up

- `model` is `{id,params?:[{id,value}]}`; discover legal combinations dynamically.
  Omission resolves user → team → system default. `name` is at most 100 characters.
- `env` is `{type:"cloud"|"pool"|"machine",name?}`. A named cloud environment and
  explicit `repos` are mutually exclusive. Omit both for a repository-free Agent.
- `repos` allows at most 20 `{url,startingRef?,prUrl?}` entries. A PR URL takes
  precedence over startingRef. Creation supports GitHub, GitLab, Bitbucket, and
  Azure DevOps variants documented by Cursor; repository discovery lists GitHub only.
- `workOnCurrentBranch=false` creates a `cursor/...` branch; true writes the chosen
  branch or PR head. `autoCreatePR` and `skipReviewerRequest` configure creation.
- `prompt.images`: up to five images, 15 MB each; `data + mimeType` XOR `url`;
  PNG/JPEG/GIF/WebP. Web attachment limits are a separate contract.
- `envVars`: at most 50; key ≤255 bytes, value ≤4096 bytes, no `CURSOR_` keys.
  Mutually exclusive with `agentId`; rollout may silently ignore unsupported values.
- `mcpServers`: up to 50 remote HTTP/SSE or VM stdio servers. Supplying them on a
  follow-up replaces that run's inline MCP configuration; omission retains it.
- `customSubagents`: up to 20, each `name,description,prompt,model?`; no built-in name
  collisions. `mode` is `agent|plan`, with follow-up omission preserving the mode.
- Optional `agentId` is `bc-<uuid>`; duplicate creation returns 409
  `agent_id_conflict`, not the old creation result.
- **CreateRun has no `model` field.** Do not advertise model switching on v1 follow-up.

Agent status is `ACTIVE / IDLE / ARCHIVED`. The reviewed OpenAPI summary enum omits
`IDLE`, despite the reference including it. Tolerate unknown values.
Run status is `CREATING / RUNNING / FINISHED / ERROR / CANCELLED / EXPIRED`; the last
four are terminal. `git.branches[]` is the Agent's current workspace snapshot,
not an immutable diff of that run. Its `repoUrl` omits `https://`.
Usage contains input/output/cache-write/cache-read/total token counts, not money
or subscription pool balances. Optional name/result/git fields can be absent.

## SSE contract

| Event | Payload / behavior |
| --- | --- |
| `status` | `{runId,status}`; initial sticky state has no ID and repeats on reconnect |
| `assistant` | `{text}` delta |
| `thinking` | `{text}` delta |
| `tool_call` | `callId,name,status,args?,result?,truncated?` |
| `interaction_update` | Rich SDK event; choose this or simplified rendering to avoid duplication |
| `heartbeat` | `{}` |
| `result` | `runId,status,text?,durationMs?,git?` |
| `error` | `{code,message}` |
| `done` | `{}` |

Tool `args/result` are arbitrary JSON. Omitted oversized data is identified by
`truncated.args/result`; it does not mean a tool had no input/output.
An event ID is opaque. Resume with the last **durably applied** ID for the same
run; a wrong-run ID returns 400 `invalid_last_event_id`. Read the actual retention
window from `X-Cursor-Stream-Retention-Seconds`. A 410 `stream_expired` requires a
Run snapshot instead of endless reconnects. Streams do not replay previous runs.

Android design inference: deduplicate by run, event ID, and event type/content as
appropriate, not ID alone. Cursor's example gives `result` and `done` the same ID.
Treat ID-free status as an upsert. Subscribe while visible or explicitly tracked;
background process survival is not guaranteed. **v1 has no conversation endpoint,
and its Run DTO does not contain the original user prompt.** Persist locally sent
prompts; never fabricate missing history or assume v0 can read v1-created records.

## Authentication, pagination, and errors

Bearer API-key authentication and Basic `base64(key + ":")` are documented. The API
key does not replace a web cookie. No mobile OAuth/device-code exchange is specified.
Do not distribute service-account administrator keys with the app.

Repository listing is limited to one request/user/minute and 30/user/hour and can
be slow; cache it. Generic limits do not prove every endpoint has an independent
20 RPM budget. Honor actual `Retry-After` and use jitter on retriable reads.
The public Cloud Agent API has no general documented ETag contract.

Normal list responses omit `nextCursor` at the end. Secrets currently use explicit
null and do not paginate. Environment pages can be short or omit records during
permission checks; stop on the cursor, not `items.size < limit`. Deduplicate by ID
and reconcile on refresh.

Secrets are distinguished by **version ID**, including same-name repository scopes.
Missing query `id` can yield 409 `secret_name_ambiguous` with candidates. Values are
write-only, 1–4096 UTF-8 bytes; at most 1000 per environment/team. Lists may include
`build_secret`, while PUT only permits `runtime_secret/environment_variable`.
New 201 responses may temporarily lack id/createdAt. Expect consistency delays.
Environment PATCH does not change repos/owner; `environmentJson` is a complete JSON
string replacement, not a partial object merge.

Errors normally use `{error:{code,message,helpUrl?,provider?,environmentId?}}`.
Branch on status and code, with message for explanation. Preserve 403 permission or
`feature_unavailable` separately from 401 authentication. Relevant errors include
`agent_busy`, `agent_archived`, `agent_id_conflict`, `invalid_model`,
`repository_access`, `integration_not_connected`, `usage_limit_exceeded`,
`run_not_cancellable`, and `environment_name_conflict`.

Archive/unarchive are explicitly idempotent. Creation can persist an `agentId`
before sending and query it after a lost response; `envVars` excludes that strategy.
CreateRun has no documented idempotency key/run ID input. After uncertain delivery,
refresh runs and show **Delivery not confirmed** instead of automatically sending
the same prompt twice. No generic `Idempotency-Key` header is documented.

## Official worker/pool control plane (12 v0 operations)

This is administrator infrastructure, usually authenticated by a service account.
The Android client is a controller, not a self-hosted worker.

| Method | Path | Contract |
| --- | --- | --- |
| GET | `/v0/private-workers` | `status,scope,limit,pageToken`; `{workers,totalCount,nextPageToken?}` |
| GET | `/v0/private-workers/summary` | User/team connected and in-use counts |
| GET | `/v0/private-workers/{id}` | Worker details |
| GET | `/v0/private-workers/pools` | Durable pools, including currently empty pools |
| POST | `/v0/private-workers/pools` | `scope:user\|team,poolName,repoOwner?,repoName?,repoUrl?,workerReadyTimeoutSeconds?` |
| DELETE | `/v0/private-workers/pools` | Query `scope,pool_name,repo_owner?,repo_name?`; does not disconnect workers |
| GET | `/v0/private-workers/pending-requests` | `limit,pageToken,repository?,pool?`; requests and shared `streamCursor` |
| GET | `/v0/private-workers/pending-requests/stream` | SSE with filter-bound cursor; header takes precedence |
| POST | `/v0/private-workers/claim` | `{id,workerId,sessionToken?}` → claim and optional token/expiry |
| POST | `/v0/private-workers/tokens` | `{id,workerId}` → seven-day token bound to existing claim |
| POST | `/v0/private-workers/claims/{id}/release` | Empty body; in-use 400; missing claim 404 |
| POST | `/v0/private-workers/claims/{id}/fail` | `message` 1–500 characters; do not retry 400/404 |

Worker list filters: status `all|in_use|idle`; scope `all|team_pool|personal`;
limit defaults to 50, maximum 100. Pool list has `includeStale=false`; list scope
values differ from create/delete. Worker fields include `workerId,isInUse,
workspaceRootPath,connectedAtMs,userId`, optional team/service-account/Agent/name/repo;
any-repo workers may have empty repoOwner/repoName. Pools include identity, connected
and in-use counts, first/last seen, stale state, readiness timeout, and optional repo.

Pending requests include ID, user, labels, creation time, optional service-account,
repository, claimed-worker, and timeout. Read all list pages before watching their
shared cursor. Worker watch is distinct from Run SSE: cursors expire after five
minutes; approximately 20-second heartbeats do not extend them. On 410
`cursor_expired`, list again. Do not persist these cursors; at most four streams per
service account. Events: created, claimed, claimed_offline, expired, heartbeat.
Delivery is best effort; the list remains authoritative.

## Legacy Agent API (12 v0 operations)

| Method | Path | Difference from v1 |
| --- | --- | --- |
| GET | `/v0/agents` | `{agents,nextCursor?}`; flattened execution status |
| POST | `/v0/agents` | `prompt,model?:string,source,target?,webhook?`; returns Agent directly |
| GET | `/v0/agents/{id}` | `source,target,summary,status` |
| DELETE | `/v0/agents/{id}` | Permanent deletion |
| GET | `/v0/agents/{id}/conversation` | `{id,messages:[{id,type,text}]}`; user/assistant messages |
| POST | `/v0/agents/{id}/followup` | `{prompt}` → `{id}` |
| POST | `/v0/agents/{id}/stop` | Stops work; another follow-up can start work |
| GET | `/v0/agents/{id}/artifacts` | Absolute paths; at most 100, within six months of Agent creation |
| GET | `/v0/agents/{id}/artifacts/download` | Absolute `path`; signed URL valid 15 minutes |
| GET | `/v0/me` | API-key metadata |
| GET | `/v0/models` | `{models:[string]}`; requestable `default` is not listed |
| GET | `/v0/repositories` | `{repositories:[{owner,name,repository}]}`; 1/min and 30/hour |

v0 artifact limits of 300/min and 6000/hour do not establish v1 limits.
v0 does not support MCP; v1 supports inline MCP.

v0 creation accepts `webhook:{url,secret?}` with a secret of at least 32 characters.
Only terminal ERROR/FINISHED `statusChange` is documented. Verify the raw body with
HMAC-SHA256 against `X-Webhook-Signature: sha256=<hex>`; deduplicate by
`X-Webhook-ID` and return 2xx. Retry count/order guarantees are unspecified.
A webhook targets a server, not Android FCM. Do not claim v1 native push based on v0.
A future backend could track runs and send FCM; low-frequency Android background
checks remain subject to platform scheduling.

## Integration gates

Keep `CloudAgentsV1Api`, `LegacyAgentsV0Api`, and `CursorWebSessionApi` separate in
credentials, DTOs, errors, and capability flags. Verify account entitlement,
web/public identity mapping, environment scope, SSE replay/410, unknown send outcomes,
secret version conflicts, envVars rollout, and cross-version history before claiming
live parity. See the [implementation plan](android-implementation-plan.md) and
[test plan](testing.md). Original detailed Chinese notes are [retained](zh-CN/cursor-public-api.md).
