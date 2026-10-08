# Cursor web API inventory

Audited with ego on October 8–9, 2026, starting at `https://cursor.com/agents`.
Sources are authenticated browser network observations and the public JavaScript
actually delivered to the browser. Settings, environments, Automations, Codebase,
plugins, integrations, usage, spending, and billing were also inspected.

The [endpoint catalog](api/cursor-web-endpoints.json) retains exact paths, methods,
type-only request/response shapes, and bundle references. The
[service catalog](api/cursor-web-services.json) records Connect and VM RPC fields.
Read the [public API reference](cursor-public-api.md) separately: web cookies and
public API keys are different credentials with different contracts.

## Evidence and coverage

The audit scanned **428 public JS chunks**, producing **857 route candidates**.
Network captures observed **123 distinct paths**, **120 with responses**. Shared
Dashboard, enterprise, helper, and third-party code makes static coverage a superset;
these numbers are not a count of verified Agent APIs or an exhaustive server inventory.

| Evidence | Meaning |
| --- | --- |
| `observed-response` | A browser response was captured; status and type shape are recorded |
| `observed-request` | A request was seen, without a complete captured response in that observation |
| `static-call` | A fetch, resolved HTTP helper, or RPC call site exists in public frontend code |
| `static-descriptor` | A method is registered by a service descriptor, without a confirmed call site |
| `static-candidate` | Only a path string or unresolved helper argument was found |

Labels overlap and their counts must not be added. `refs` contains a bundle filename
and zero-based character offset. The retrieval prefix was
`https://cursor.com/_next/static/immutable/chunks/`; deployment updates may remove old
bundles. `queryNames` contains names only; `requestBodyShape` describes body types.
`?keys=...` in capture references is an audit sanitizer marker, not a real parameter.
Absence from a sampled response does not prove a field is unsupported.

No prompt, terminal command, desktop takeover, or file save was executed. Opening
`/automations/new` automatically created one disabled empty draft; it was deleted
and the empty list was verified. Those create/delete observations do not validate
other mutations. Account identifiers, credentials, and private values are omitted.

## Authentication and transport

Web calls depend on same-origin session cookies. Connect explicitly includes
credentials. No evidence establishes that a public Cloud Agent key can call web
Settings, Usage, or VM endpoints.

Team selection uses `x-cursor-team-id` and UI cookie `portal-selected-team-id`.
Bodies may still require `teamId`, `team_id`, `owner`, or `expectedScope`; do not
remove those fields. Scope caches and in-flight work by connection, team, and Agent.
Cancel old streams when switching teams and reject stale account callbacks.

The Origin `originPostJson` helper uses GET `/api/csrf-token`, cookie `csrf-token`
(or `cursor-csrf-token` with a base path), and header `x-csrf-token`. It refreshes
and retries once on 403 with `error.code == invalid_csrf_token`. The Dashboard
helper enables CSRF only for non-GET calls with `csrf:true`; inspected composer
mutations do not uniformly set it. Implement the observed requirement per adapter,
not one blanket rule for every POST. API keys, CSRF, session cookies, and VM tokens
must remain separate.

| Transport | Use |
| --- | --- |
| POST JSON | Most background-composer, dashboard, and automation reads and writes |
| Connect RPC | `/api/connect-proxy/<service>/<method>`, including server streams |
| Binary blob | GET `/api/background-composer/get-blob-for-agent-kv/{bcId}/{blobId}` |
| File JSON/base64/download | `/api/files/{bcId}/*` |
| VM WebSocket | JSON envelopes containing protobuf bytes |
| VNC | RFB/noVNC over WebSocket; separate from conversation and PTY |

Protobuf JSON may encode int64/uint64 as strings. Preserve precision and tolerate
unknown enum values and fields. Conditional JSON caches use method, URL, headers,
and body, not URL alone. On 304 without a cached body, retry once without validators.

## Agent lifecycle and discovery

The following use `/api/background-composer/`; POST unless noted. “Response” means
observed, and “call” means frontend evidence without executing the write.

| Suffix | Evidence | Purpose |
| --- | --- | --- |
| `list` | Response | Pagination, archive/owner filters, pinned state |
| `get-detailed-composer` | Response | Single or batch Agent details |
| `available-models` | Response + call | GET `request=<JSON>` or POST; both call styles exist |
| `pause` | Call | Stop current work; web optimistic state rolls back on failure |
| `mark-read`, `mark-unread` | Call | Read state |
| `pin`, `unpin` | Call | Batch pinned Agent IDs |
| `submit-interaction-response` | Call | Answer Agent interaction |
| `update-experimental-model-opt-out` | Call | Per-Agent experimental model choice |
| `get-diff-details` | Response | Change details |
| `list-artifacts` | Response | Artifact metadata |
| `get-artifact`, `get-artifact-bytes` | Call | Artifact URL or bytes |
| `get-machine` | Response | Machine and temporary connection material |

Observed list fields include `n,include_status,include_archived,
should_include_collaborators,owner_filter.owners[{id,owner_type}],include_pinned_state`.
Source also supports activity offset, team, and source filters. Responses include
`composers,participants,hasMore,nextPageOffset/nextPageToken,pinnedBcIds,
didLoadPinnedState`, and sometimes `canUseBackgroundAgents`.
Single detail uses `{bcId,n:1,includeTeamWide:true}`; batch uses
`{bc_ids,n,include_diff,include_team_wide,include_archived?,status_only?}`.
Do not normalize these different wire naming conventions by guesswork.

Models include names, capabilities, variants, parameters, recommendations, per-surface
configuration, and `useModelParameters`. Preserve `requestedModel` as
`modelId/maxMode/parameters`; do not hardcode the currently visible model catalog.

Lifecycle POST calls under `/api/auth/`:

- `startBackgroundComposerFromSnapshot`: `bcId`, prompt/richPrompt, models,
  repo/environment, images/skills/MCP, machine, expectedScope; descriptor fields are
  not all mandatory. Uploads use `presignPromptUpload`, `completePromptUpload`, and
  `abortPromptUpload` with separate size, expiry, and recovery rules.
- `addAsyncFollowupBackgroundComposer`: bcId, followup/richFollowup,
  followupMessage/followupId, requestedModel/modelDetails, followupSource,
  expectedScope; descriptor returns runId. Archived 404 recovery is a web behavior.
- `archiveBackgroundComposer`: `{bcId}`, or `unarchive:true` to restore.
- `renameBackgroundComposer`: `{bcId,newName}`.
- `wakeBackgroundComposer`: `{bcId,reason}`, response `signaled`.
- Pending follow-ups: `listPendingFollowups`, `updatePendingFollowup`,
  `deletePendingFollowup`, `submitPendingFollowupNow`, `markFollowupEditing`,
  `reorderPendingFollowup`; updates include followupId and relevant message/order.
  Check `success/errorMessage`, not HTTP 200 alone.

Persist request identity where supported and reconcile uncertain delivery. Do not
blindly retry a timed-out creation or follow-up that may already have executed.

## Connect conversation and list synchronization

Service: `aiserver.v1.BackgroundComposerService`.
`StreamBackgroundComposerUpdates` was observed with POST 200. Request fields include
resumeCursor, teamId, snapshot count, archived/pinned/workers/subagents flags;
response oneof is `snapshot / event / heartbeat`.

`StreamConversation` connected successfully. Request fields include bcId, offsetKey,
purpose, expectedScope, prefetch, and heartbeat flags. Responses include initial
state, cloud-agent state with ID/offset, interaction update/query, workflow status,
worker lifecycle, prefetched blobs, stream signal/heartbeat, transient errors, and
settled interactions. It is **not SSE** and cannot be read as EventSource or a JSON
array. Implement framing, cursor/offset recovery, deduplication, reducers, and blob
cache. Consume prefetched blobs before requesting missing agent-kv content.
A similarly named export helper `stream-conversation` does not prove identical framing.

Other call sites include ListBackgroundComposerChildren, StartSideChatBackgroundComposer,
GetEnvironmentHistory, GetBackgroundComposerEnvironmentVersion, DuplicateEnvironment,
RenameEnvironment, RestoreEnvironmentVersion, and MigrateEnvironmentToOrigin.
Methods such as ForkBackgroundComposer retain descriptor-only labels where applicable.

## Settings: complete feature-family mapping

### Personal Cloud Agent preferences

POST `get-background-composer-user-settings` was observed. POST
`update-background-composer-user-settings` submits a **partial patch**, followed by
cache invalidation/refetch; it is not a full-object replacement.

| Setting | Wire fields |
| --- | --- |
| Default model | `modelName`, `defaultModelSelection` |
| Branch prefix | `branchPrefix` |
| Follow up on CI failure | `ciFailureFollowupEnabled` |
| Browser use | `browserUseEnabled` |
| Web-Agent Slack notifications | `slackNotificationsForWebEnabled` |
| Automatic PR | `autoCreatePrSetting` |
| PR destination | `prReviewOpenDestination`, observed `prReviewOpenSurface` |
| GitHub artifact posting | `githubArtifactPosting` |
| Automatic answer timeout | `askQuestionAutoAnswerTimeoutMinutes` |
| Network policy | `egressProtectionMode`, `egressPolicy.allowlist` |
| Private machines | `allowPrivateWorkers` |
| Remote control | `remoteControlEnabled` |
| Quick subagents | `quickActionSettings` |
| Multi-repo limit | `maxMultiRepoEnvironmentRepos` (read-only limit) |

Observed/read and write-call fields coexist; not every account can edit every field.
Timeout clearing uses `-1`; network patches may contain bcId. Enabling remote control
may also enable private workers, but must respect a team restriction. Quick actions
have slots, explicit state, catalog versions, template mutations, personal/team/builtin
scope, and subagent/parent_agent types; they are not just prompt strings.

### Team policy

POST `/api/dashboard/get-team-background-agent-settings` and
`update-team-background-agent-settings` use teamId and (for writes) settings.
Web capability checks include `team.background_agent_settings.manage`.
Policies cover allowlists, PRs, follow-ups/tests, private workers, automations, VM sharing,
remote control, egress locks, administrator-only Secret/environment editing, artifact
sharing, retention, CI handling, and worker token/Secret sync. Display effective
policy and locked state separately from personal preferences.

### Account, privacy, appearance, and notifications

Dashboard's typed helper converts camelCase methods to kebab-case and uses POST.
Its internal “v2 data layer” does not imply a `/api/v2/` URL prefix.

| Area | Dashboard methods / boundary |
| --- | --- |
| Profile | `get-user-profile`, `update-user-profile`, `claim-user-profile-handle`; visibility/links/metadata/contributions; handle is separate |
| Name | `update-user-name` with firstName/lastName |
| Avatar | `upload-profile-picture` sends raw image bytes; empty URL through `update-user-profile-picture` removes it |
| Privacy | `get-user-privacy-mode`, `set-user-privacy-mode`, team get/switch; forced policies and grace periods apply |
| Smart Auto | `get-user-smart-auto-settings`, `update-user-smart-auto-settings`; enabled/showRoutedModel and canEnable |
| Non-ZDR consent | `get-no-zdr-model-consent-status`, `set-user-no-zdr-model-consent`; modelId/enabled/acknowledged/consentVersion |
| Sessions | GET `/api/auth/sessions`; POST `/api/auth/sessions/revoke`; revocation does not establish mobile token issuance |
| Push | Register/delete token call sites exist; browser PushSubscription is not an Android FCM contract |
| Appearance | Local light/dark/system and named-theme hook; no verified cloud-sync REST contract |

Account deletion, payments, organization merges, and OAuth remain browser-managed
product flows. Local Android appearance/language/usage preferences belong in DataStore.

## Environments, Secrets, MCP, and plugins

Environment POST families include list/get, personal/team set/delete, draft and
multi-repo resolve/create. `get-environment` uses publicId/includeEnvironmentJson;
response includes ID, scope, repoConfig, environmentJson, and version. Environment
visibility is not the same as repository authorization.

Build settings use get/update-environment-build-settings; history uses list/get-
environment-builds and active-build. Trigger/cancel/update are separate writes.
Settings include fastForwardDefaultBranch/autoFastForwardStalenessHours and explicit
clear fields; a descriptor also declares buildsEnabled.

Secrets use list-background-composer-secrets, create-background-composer-secret-batch,
update-background-composer-secret, and revoke-background-composer-secret. Scope includes
teamScope, owner, scopedToRepos, and surface; owner can be user/team/environmentId.
Metadata includes id/name/createdAt/scope/level; levels distinguish environment,
runtime, and build values. Never request old plaintext. Batch success is per item.
Keyring calls and grants exist but do not establish universal personal entitlement.

MCP get-mcp-config uses `redactSecrets:true`; retain it. Set uses configJson plus
rename/ID mappings and scope. get-available-mcp-servers, check-http-mcp-status, and
update-user-default-mcp-settings handle discovery, auth status, and enabledServerIds.
OAuth account management/tool previews are separate. Plugins include marketplace,
effective installs, install/update/uninstall, slash commands, and launch snapshots.
A selected plugin/skill must use the actual context contract, not just its name in text.

## Automations, Codebase, integrations, and PRs

`/api/automations/` uses POST JSON for list/get/create/update/delete, templates and
create-from-template, run listings/summaries, test/cancel/retry, memory operations,
managed-team settings, reassignment, and authoring. IDs, scope, workflow and permissions
matter. Restricted summaries are not full editable workflows. Memory writes use
version/expectMissing and return conflicts. Test Run executes work. Keep save,
enable, and test separate; create local drafts until the user explicitly saves.

Codebase/Origin uses `/api/origin/<method>` POST with the CSRF helper: namespaces,
hosted repos, repo content/paths, SSH keys, invitations, and repository creation.
Its authorization differs from SCM selection for launching an Agent.
Integrations include GitHub/GitLab/Bitbucket/Azure DevOps and collaboration providers.
Use browser flows for binding and organization policy.
PR reads include merge/detail status, commits, discussion/timeline, and refresh.
Open, merge, update-branch, draft conversion, auto-merge, replies, and thread resolution
are distinct writes; opening a PR link does not authorize merging it.

## Usage contract

GET `/api/usage-summary` (optional teamId) was observed. It includes billing cycle,
membership, limitType, isUnlimited, individualUsage.plan, onDemand, and teamUsage.
Use only `individualUsage.plan.autoPercentUsed` for **Cursor Model** and
`individualUsage.plan.apiPercentUsed` for **Other Model**. Missing values are unknown,
not zero. Do not infer one pool from totalPercentUsed or use money/tokens to derive it.
This mapping follows the reference client's semantics and the observed account;
field naming alone is not a permanent promise about every model in a pool.

Older GET `/api/usage?user=...`, dashboard event/period/billing data, and VM resource
usage have different meanings. Keep the product at two pools; excluded third-product
paths are retained only as marked research evidence, never as integration fallbacks.

## Terminal, files, and desktop protocols

`get-machine` uses `{bcId,mintDesktopTicket?:true}`. Pod fields include podId,
tenantId, cluster, networkToken, and ptyAuthToken. Private worker desktop includes
wsUrl/sessionId/sessionSecret/controlAllowed. These temporary credentials must not
enter logs, Room, export files, or external browsing history.

```text
wss://{tenantId}-{podId}-{port}.{cluster}.cursorvm.com:443/{path}
  ?network_token={issuedToken}&resume_lower_s=900&resume_upper_s=18000
```

PTY/Tmux uses port 26054; VNC uses 26058 (legacy 6080). Build URLs only from validated
machine discovery, never a hardcoded real VM address.

WebSocket RPC uses JSON envelopes with type, requestId, path, method POST, headers,
and base64 protobuf body. Type 1/2/3/4/5/6 is REQUEST/CANCEL/RESPONSE/HEADERS/END/ERROR.
Unary content type is application/proto; streams are application/connect+proto with
one flag byte + four-byte big-endian length + payload. Authentication uses
ptyAuthToken in the WS token query and RPC Authorization. Raw text is not valid PTY RPC.

| Service | Methods |
| --- | --- |
| `agent.v1.TmuxSessionService` | ListSessions, CreateSession, AttachSession, KillSession |
| `agent.v1.PtyHostService` | ListPtys, SpawnPty, AttachPty, SendInput, ResizePty, TerminatePty |

CreateSession's name field is sessionName. AttachPty uses lastEventId; PtyEvent has
ptyData/ptyExited. Preserve partial UTF-8 across frames and bound buffers.
Opening Terminal may automatically create a shell, so it was not opened in this audit.
Viewing/attaching and creating a terminal should remain separate; navigation only
detaches, rather than silently killing the process or replaying input.

Files under `/api/files/{bcId}` use same-origin cookies:

| Method / suffix | Contract |
| --- | --- |
| GET `list` | path/includeHidden → entries (name/path/type/sizeBytes/modifiedAtUnixMs) |
| GET `read` | path → text content |
| GET `read-binary` | path → base64 content |
| POST `write` | JSON path/content; returned fields not consumed by inspected frontend |
| GET `download` | path → browser download; headers not observed |

No revision/ETag conflict protection was established for writes. Keep dirty edits
on failure. The web download action may save dirty content first; it is not always
read-only. Connect AgentStore files and persisted artifacts are distinct from live VM files.

Cloud desktop uses noVNC at `/websockify`; a library reference to RTCDataChannel is
not proof of application WebRTC signaling. Private desktop ticket subprotocols are
`binary`, `cursor-desktop-ticket.{sessionId}.{sessionSecret}`, and, only for explicit
control, `cursor-desktop-control`. Default view-only. DesktopLease takes bcId,
action ACQUIRE/RELEASE, and stable surfaceId; it returns held. Source shows a
30-second lease renewed every 10 seconds. Lost lease/background/exit releases control
and restores view-only. Never take over automatically merely by opening the view.

## Remaining integration work

Android login/SSO, team entitlement, Connect encoding, write reconciliation, FCM,
VNC negotiation, file concurrency, and web/public ID visibility require independent
verification. Public frontend code is evidence, not a stability guarantee for third-party
clients. See the [implementation plan](android-implementation-plan.md) and
[original Chinese notes](zh-CN/cursor-api-inventory.md).
