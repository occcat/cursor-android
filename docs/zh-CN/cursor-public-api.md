> Historical Chinese research, completed on 2026-10-09. See the [English index](../README.md) for the current implementation status.

# Cursor 官方 Cloud Agents API 核查

核查日期：2026-10-08。方法：只读取 Cursor 官方参考页与它链接的 OpenAPI；未使用任何 API key 发真实业务请求。这里的“官方已声明”不代表当前账户已开通或已做联调。

来源：

- [当前 Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints)
- [官方 OpenAPI](https://cursor.com/docs-static/cloud-agents-openapi.yaml)
- [鉴权与限制](https://cursor.com/docs/api)
- [v0 legacy](https://cursor.com/docs/cloud-agent/api/v0)
- [v0 Webhooks](https://cursor.com/docs/cloud-agent/api/webhooks)

## 结论与覆盖范围

- Base URL：`https://api.cursor.com`。当前 Cloud Agents API 为 **v1 Public Beta**；公开文档仍保留 v0。
- OpenAPI：25 个 path、33 个 HTTP operation，全部 `/v1/`。
  当前参考页另有 12 个 `/v0/private-workers/*` operation；
  它们是正式文档中的自托管控制面，不是 `cursor.com` 网页私有 API。
- v1 Agent 是持续会话/工作区，Run 是每次 prompt 的执行。Agent 生命周期和 Run 执行状态必须分开。
- 普通 Android 客户端优先 v1 Agent/Run、模型、仓库、环境、Secrets；
  Worker/Pool 控制面需要 service-account key，适合作为管理员能力或后端控制器。
- v1 已提供 SSE；**v1 Webhooks 尚未提供**。v0 Webhook 有单独能力，不能把它当作 v1 原生推送。
- `GET /v1/agents/{id}/usage` 是 Agent/Run token 统计；
  不能直接导出账户 Cursor Model / Other Model 的套餐余额、重置窗口或占比。
- 官方没有声明本客户端所需的全部网页设置：用户默认模型写入、主题/语言、消息置顶/已读/重命名、个人套餐两类额度等仍需由网页观测单独确认。

## 当前 v1 全部端点（33 个 operation）

`id` 在 Agent 路径中是 Agent ID，在环境路径中是 Environment UUID。除流以外数据为 JSON。

| Method | Path | 输入/输出要点 |
|---|---|---|
| POST | `/v1/agents` | `prompt.text` 必填；创建 Agent + 初始 Run；201 `{agent,run}` |
| GET | `/v1/agents` | 说明 1 |
| GET | `/v1/agents/{id}` | 完整 Agent、repos、分支策略、`latestRunId`；执行状态取 Run |
| DELETE | `/v1/agents/{id}` | 永久删除；200 `{id}` |
| POST | `/v1/agents/{id}/runs` | 说明 2 |
| GET | `/v1/agents/{id}/runs` | `limit=20`（1–100）、`cursor`；`{items,nextCursor?}`，新建在前 |
| GET | `/v1/agents/{id}/runs/{runId}` | Run 状态、时间、终态 `result/durationMs`、Agent 当前 `git` 快照 |
| GET | `/v1/agents/{id}/runs/{runId}/stream` | SSE；可带 `Last-Event-ID`；响应含保留窗口秒数 |
| POST | `/v1/agents/{id}/runs/{runId}/cancel` | 说明 3 |
| GET | `/v1/agents/{id}/usage` | 可选 `runId`；`{totalUsage,runs:[{id,usageUuid?,usage}]}` |
| GET | `/v1/agents/{id}/artifacts` | `{items:[{path,sizeBytes,updatedAt}]}`，属于 Agent 工作区 |
| GET | `/v1/agents/{id}/artifacts/download` | query `path`；`{url,expiresAt}`，15 分钟签名下载 URL |
| POST | `/v1/agents/{id}/archive` | 200 `{id}`；可逆，重复归档幂等 |
| POST | `/v1/agents/{id}/unarchive` | 200 `{id}`；重复恢复幂等 |
| POST | `/v1/environments` | `owner,name,repos,environmentJson` 必填；201 环境 |
| GET | `/v1/environments` | `limit=20`（1–100）、`cursor`；`{items,nextCursor?}`，最近更新在前 |
| GET | `/v1/environments/{id}` | 环境详情，额外 `environmentJson? / versionId? / repoFile?` |
| PATCH | `/v1/environments/{id}` | `name`、`environmentJson` 至少一个；两者原子应用；204 无 body |
| DELETE | `/v1/environments/{id}` | 永久删除；200 `{id}` |
| GET | `/v1/environments/{id}/history` | `limit=20`（1–100）、`cursor`；变更记录及历史配置 |
| GET | `/v1/environments/{id}/builds` | 仅 `cursor`，每页最多 10 个；`{items,nextCursor?}` |
| GET | `/v1/environments/{id}/builds/{buildId}` | 单次构建状态/触发源/失败原因/时间 |
| GET | `/v1/environments/{id}/builds/active` | 说明 4 |
| GET | `/v1/environments/{id}/secrets` | 版本元数据，不返回 secret value；`{items,nextCursor:null}` |
| PUT | `/v1/environments/{id}/secrets/{name}` | 说明 5 |
| DELETE | `/v1/environments/{id}/secrets/{name}` | 可选 query `id` 指定版本；200 删除信息 |
| GET | `/v1/team/secrets` | 团队 secret 版本元数据；`{items,nextCursor:null}` |
| PUT | `/v1/team/secrets/{name}` | body `value,type?,repos?`；可选 query `id`；200/201 |
| DELETE | `/v1/team/secrets/{name}` | 可选 query `id`；删除指定版本 |
| POST | `/v1/sub-tokens` | 说明 6 |
| GET | `/v1/me` | `apiKeyName,createdAt,userId?,userEmail?,userFirstName?,userLastName?` |
| GET | `/v1/models` | `{items:[{id,displayName,description?,aliases?,parameters?,variants?}]}` |
| GET | `/v1/repositories` | `{items:[{url}]}`；仅 GitHub App 可访问的 GitHub 仓库 |

- 说明 1，GET `/v1/agents`：`limit=20`（1–100）、`cursor`、`prUrl`、`includeArchived=true`；
  `{items,nextCursor?}`，新建在前；列表只含身份摘要
- 说明 2，POST `/v1/agents/{id}/runs`：`prompt`、可选 `mcpServers`、`mode`；
  201 `{run}`；现有活跃 Run 时 409 `agent_busy`
- 说明 3，POST `/v1/agents/{id}/runs/{runId}/cancel`：200 `{id}`；转 CANCELLED；
  不可取消时 409 `run_not_cancellable`
- 说明 4，GET `/v1/environments/{id}/builds/active`：`{type:"build",buildId}` 或
  `{type:"universal_image"}`
- 说明 5，PUT `/v1/environments/{id}/secrets/{name}`：body `value,type?,repos?`；可选 query
  `id=secretVersionId`；200 更新/201 新建
- 说明 6，POST `/v1/sub-tokens`：`forUserEmail` / `forUserId` 二选一；
  仅 agent-scoped team service-account key；返回 1 小时 user token

### CreateAgent 必须了解的字段

- `prompt.images`：最多 5 张、每张 15 MB；二选一 `data + mimeType` / `url`；PNG/JPEG/GIF/WebP。网页附件限制另算。
- `model`：`{id,params?:[{id,value}]}`；从 `/v1/models` 动态发现合法组合。
  省略整个 `model` 按 user → team → system default 解析。
- `name`：最长 100 字符；省略则自动命名。
- `env`：`{type:"cloud"|"pool"|"machine",name?}`。命名 cloud environment 与显式 `repos` 互斥。
- `repos`：最多 20 条，`{url,startingRef?,prUrl?}`；每条 url 必须有。
  prUrl 存在时 startingRef 不生效。未提供 repos/env 可建无仓库 Agent。
- 支持 GitHub Cloud/Enterprise、GitLab Cloud/Self-Hosted、Bitbucket Cloud、Azure DevOps；但列表
  `/v1/repositories` 仅 GitHub，因此其他 provider 需粘贴 URL 或网页数据源。
- `workOnCurrentBranch=false`：新建 `cursor/...` 分支。true 写 startingRef；PR 输入时写 PR head。
- `autoCreatePR`、`skipReviewerRequest`：创建时行为配置。
- `envVars`：最多 50 条，key ≤255 bytes、value ≤4096 bytes，key 不能 `CURSOR_`；
  与 `agentId` 互斥。灰度未开通可能静默忽略，不能只凭 201 判定生效。
- `mcpServers`：最多 50；remote HTTP/SSE（headers/OAuth）或 VM 内 stdio（command/args/env）。
  follow-up 中发送时覆盖本 run 的 inline MCP，省略沿用。
- `customSubagents`：最多 20；`name,description,prompt,model?`；不与内建名字冲突。
- `mode`：`agent|plan`；初始默认 agent；follow-up 省略沿用。
- `agentId`：可选 `bc-<uuid>`；重复返回 409 `agent_id_conflict`，不会自动返回旧创建结果。
- CreateRun schema **没有 `model` 字段**；不可假设支持 follow-up 切换模型。

### Agent / Run / Usage DTO

- Agent 页面声明：`ACTIVE / IDLE / ARCHIVED`。
  **官方 OpenAPI 的 AgentSummary enum 当前只列 ACTIVE/ARCHIVED，漏 IDLE**；
  客户端不能盲目按生成 enum 拒绝 IDLE。
- Run：`CREATING / RUNNING / FINISHED / ERROR / CANCELLED / EXPIRED`；后四种终态。
- `git.branches[] = {repoUrl,branch?,prUrl?}`，repoUrl 无 `https://`；它是同 Agent 的当前快照，不能当成本 Run 独占变更。
- Usage：`inputTokens,outputTokens,cacheWriteTokens,cacheReadTokens,totalTokens`；
  尚无 usage 的 run 返回 0；没有账户套餐余额/金额字段。
- Agent list 不含完整配置，应按需 get；Agent/Run 均不保证存在 name/result/git 等可选字段。

## SSE 设计合同

| event | data |
|---|---|
| `status` | `{runId,status}`；开头 sticky 状态无 id；每次 reconnect 都会重发 |
| `assistant` | `{text}` 增量 |
| `thinking` | `{text}` 增量 |
| `tool_call` | `{callId,name,status:"running"\|"completed",args?,result?,truncated?}` |
| `interaction_update` | SDK `InteractionUpdate`；可选丰富事件；与 simplified events 二选一消费以免重复 |
| `heartbeat` | `{}` |
| `result` | `{runId,status,text?,durationMs?,git?}` |
| `error` | `{code,message}` |
| `done` | `{}` |

- `args/result` 是任意 JSON；过大时字段省略并置 `truncated.args/result=true`，UI 不能把它解释为调用无输入或无输出。
- SSE `id` 为 opaque string，不解析格式。用最后**已落盘处理**的 id 放入 `Last-Event-ID`。
- id 必须属于当前 run；错误返回 400 `invalid_last_event_id`。
- 保留窗口读 `X-Cursor-Stream-Retention-Seconds`，文档未固定窗口时长。
- 410 `stream_expired` 后停止重连流，GET Run 读终态。流仅覆盖当前 Run，不重播以前 Run。
- Android 推论：Room 以 `(agentId,runId,eventId,eventType)` 或更完整事件身份做去重，
  不能仅以 eventId 全表唯一；文档示例 result/done 使用同一 id。
  开头无 id 的 status 以 upsert 状态处理。
- Android 推论：OkHttp SSE + StateFlow；只保持可见会话或用户显式关注会话的流，后台完整送达另走服务端/系统推送设计。

## 设置、分页、鉴权与错误

- Bearer `Authorization: Bearer <key>` 与 Basic `base64(key + ":")` 等价。
  用户 key 与团队 service-account key 来自 Dashboard。文档没有移动端 OAuth 登录/刷新 token 合同。
- `/v1/me` 的 service-account 响应可能没有 userId/email；不要据此断言登录失败。
- 通用限流文档：未另行说明时默认每分钟 20 次；Cloud Agents 表格仅称 standard rate limiting。
  不能宣称每个 v1 endpoint 一定独立有完整 20 RPM。
- `/v1/repositories` 具体限额：1/user/min、30/user/hour，可能耗时几十秒。应缓存，禁止每次展开 picker 刷新。
- 429：退避加 jitter，并尊重实际 `Retry-After`；
  文档只对 Admin/Organization 明确固定 `Retry-After: 60`，不要硬套 Cloud Agents。
- Cloud Agents 没有声明通用 ETag 缓存合同；概览里 ETag 能力是 Analytics / AI Code Tracking。
- 普通 v1 list 的 `nextCursor` 无更多时**省略**，不是 null；Secrets list 当前例外：始终 `nextCursor:null`，尚未分页。
- Environment list 可能因权限校验超时短页、暂漏或提前结束；
  数据更改会移动到首页导致重复/漏项。客户端 ID 去重，刷新后纠正；
  不能以 `items.size < limit` 判结束。
- Secrets 用 **version ID** 区分同名不同 repo scope；
  同名未带 query id 可能 409 `secret_name_ambiguous`（含候选 versions）。读写有短暂一致性延迟。
- Secret 类型列表可见 `build_secret`，但 PUT 仅接受 `runtime_secret/environment_variable`；
  不得展示可编辑 Build Secret 的虚假入口。
- Secret value 永不回读；`value` 1–4096 UTF-8 bytes；每环境/团队最多 1000 条；新建 201 有时暂缺 `id/createdAt`。
- Environment PATCH 仅 name/config；不能推断它能改 repos/owner。
  `environmentJson` 是编码为字符串的整份 JSON，替换而非字段 merge。
- Environments 创建/读取按 personal/team、仓库访问权限、API key scope 控制；部分账户 403 `feature_unavailable`。
- v1 常见错误 envelope `{error:{code,message,helpUrl?,provider?,environmentId?}}`；
  401 可另有 auth schema。客户端按 status + code 分支，原文 message 用于辅助，不做唯一逻辑判断。
- 关键业务错误：`agent_busy`、`agent_archived`、`agent_id_conflict`、`invalid_model`、`repository_access`、
  `integration_not_connected`、`usage_limit_exceeded`、`run_not_cancellable`、
  `environment_name_conflict`。

## 幂等与未知结果

- 官方明确 archive/unarchive 重复操作幂等。
- CreateAgent 可传 agentId 防重复，但 duplicate 是 409；Android 持久化 UUID 后发起，超时可 GET 该 ID核对，再决定下一步。
- 若使用 envVars 不能传 agentId，该防重复策略失效。避免传输失败后自动重试创建。
- CreateRun 无文档化 idempotency key/runId 输入，不能盲重试。网络未知结果先刷新 runs；无法确认则给用户“发送结果待确认”，不自动再发一个 prompt。
- 未发现通用 `Idempotency-Key` header、取消请求幂等、跨 v0/v1 数据互通保证。

## 当前 reference 中的官方 Worker/Pool 端点（12 个，保留 v0 路径）

这是自托管基础设施能力，非网页 Cookie 接口；通常由 service account 鉴权。

Worker 详情的关键字段：`workerId,isInUse,workspaceRootPath,connectedAtMs,userId`，
以及可选 `teamId,serviceAccountId,activeBcId,name,repoUrl`。
`repoOwner/repoName` 在 any-repo worker 上可以是空字符串。
Summary 参考页展示 `teamSummary.totalConnected/inUse`，未给出完整稳定 schema。

Pool 列表 query：`scope=all|team_pool|personal`、`includeStale=false`。
返回 `{pools:[...]}`；条目包括 `scope,ownerId,poolName,connectedWorkerCount`、
`inUseWorkerCount,firstSeenAtMs,lastSeenAtMs,isStale,workerReadyTimeoutSeconds`，
以及可选 repo 字段。list scope 与 create/delete 的 `user|team` 不是同一组取值。

Pending request 条目包含 `id,userId,labels:[{key,value}],createdAtMs`；可选
`userEmail,serviceAccountId,repoOwner,repoName,repoUrl,claimedWorkerId,wakeTimeoutMs`。
队列逻辑分页中的所有页面共享一个 `streamCursor`，读完所有页才开始 watch。

| Method | Path | 输入/输出 |
|---|---|---|
| GET | `/v0/private-workers` | 说明 7 |
| GET | `/v0/private-workers/summary` | user/team 连接数、使用数 |
| GET | `/v0/private-workers/{id}` | 单 worker |
| GET | `/v0/private-workers/pools` | durable pools，包含无 worker 的 pool |
| POST | `/v0/private-workers/pools` | 说明 8 |
| DELETE | `/v0/private-workers/pools` | 说明 9 |
| GET | `/v0/private-workers/pending-requests` | 说明 10 |
| GET | `/v0/private-workers/pending-requests/stream` | 说明 11 |
| POST | `/v0/private-workers/claim` | 说明 12 |
| POST | `/v0/private-workers/tokens` | `{id,workerId}` → 绑定现有 claim 的 7 天 session token |
| POST | `/v0/private-workers/claims/{id}/release` | 无 body；释放闲置 claim；正在使用返回 400；无 claim 404 不重试 |
| POST | `/v0/private-workers/claims/{id}/fail` | 说明 13 |

- 说明 7，GET `/v0/private-workers`：
  `status=all|in_use|idle,scope=all|team_pool|personal,limit=50(1–100),pageToken` →
  `{workers,totalCount,nextPageToken?}`
- 说明 8，POST `/v0/private-workers/pools`：
  `scope:user|team,poolName,repoOwner?,repoName?,repoUrl?,workerReadyTimeoutSeconds?` →
  `{registered}`
- 说明 9，DELETE `/v0/private-workers/pools`：query `scope,pool_name,repo_owner?,repo_name?` →
  `{deregistered}`；不踢已连接 worker
- 说明 10，GET `/v0/private-workers/pending-requests`：`limit=50(max100),pageToken,repository?,pool?` →
  `{requests,nextPageToken?,streamCursor}`
- 说明 11，GET `/v0/private-workers/pending-requests/stream`：`cursor,repository?,pool?`；SSE，
  Last-Event-ID 优先于 query cursor
- 说明 12，POST `/v0/private-workers/claim`：`{id,workerId,sessionToken?}` →
  `{id,workerId,token?,expiresAt?}`
- 说明 13，POST `/v0/private-workers/claims/{id}/fail`：`{message}` 1–500 字符；
  报告等待启动的 worker 失败；400/404 不重试，5xx 可重试

Worker watch 与 Run SSE 是不同协议：先 list 再 watch；cursor 绑定 repo/pool filter；
5 分钟后过期，心跳约 20 秒不延长寿命；410 `cursor_expired` 重新 list；
不要持久化这些 cursor；每 service account 最多 4 streams。
事件 `created/claimed/claimed_offline/expired/heartbeat`。
投递 best-effort，list 是最终事实来源。

## Legacy v0 常规 Agent 能力（12 个，另保留为兼容层）

| Method | Path | 与 v1 的差异 |
|---|---|---|
| GET | `/v0/agents` | `{agents,nextCursor?}`；扁平 Agent 执行状态 |
| POST | `/v0/agents` | `prompt,model?:string,source,target?,webhook?`；直接返回 Agent |
| GET | `/v0/agents/{id}` | `source/target/summary/status` |
| DELETE | `/v0/agents/{id}` | 永久删除 |
| GET | `/v0/agents/{id}/conversation` | 说明 14 |
| POST | `/v0/agents/{id}/followup` | `{prompt}` → `{id}` |
| POST | `/v0/agents/{id}/stop` | 停止，follow-up 可再跑；不要等同 v1 同一 run resume |
| GET | `/v0/agents/{id}/artifacts` | 说明 15 |
| GET | `/v0/agents/{id}/artifacts/download` | query absolute path；15 分钟 URL；与 v1 相对路径不同 |
| GET | `/v0/me` | API key 信息 |
| GET | `/v0/models` | `{models:[string]}`；`default` 可用于请求但不会列在模型结果 |
| GET | `/v0/repositories` | `{repositories:[{owner,name,repository}]}`，仍限 1/min、30/hour |

- 说明 14，GET `/v0/agents/{id}/conversation`：
  `{id,messages:[{id,type:"user_message"|"assistant_message",text}]}`
- 说明 15，GET `/v0/agents/{id}/artifacts`：`{artifacts:[{absolutePath,sizeBytes,updatedAt}]}`；最多 100，
  Agent 创建 6 个月内

v0 artifacts 两个端点文档具体上限 300/min、6000/hour，不能推断 v1 沿用。v0 MCP 未支持；v1 明确支持 inline MCP。

### v0 Webhook / Android 推送

- 创建 v0 Agent 时传 `webhook:{url,secret?}`；secret 最少 32 字符。
- 仅 `statusChange`，ERROR / FINISHED 状态；POST payload 包含 event/timestamp/id/status、可选
  source/target/summary。
- `X-Webhook-Signature: sha256=<hex>` 对 raw request body 做 HMAC-SHA256；
  `X-Webhook-ID` 用于 delivery 去重；返回 2xx；可能重试，次数/间隔/顺序保证未知。
- 这是发往服务器的 webhook，不是 Android FCM。若后端采用 v0，可验签入库后发 FCM；**不能为 v1 新建 Agent 声称已有官方 webhook**。
- v1 Android 当前可行路线：前台 SSE；后台由自有服务器持续追踪 + FCM，或受 Android 后台调度限制的低频检查。移动进程被杀后持续 SSE 没有文档保障。

## Android 集成建议与实测待办

1. `CloudAgentsV1Api`、`LegacyAgentsV0Api`、`CursorWebSessionApi` 三层分开；分别 DTO、凭据、错误协议和能力标识。
2. v1 领域层使用 Agent + Run + StreamEvent；
   Room 记录自己发送的 prompts、send-state、last SSE ID。
   **v1 当前没有 conversation endpoint，Run DTO 也没有原始用户 prompt。**
   导入历史完整聊天需网页数据或 v0 conversation；
   v0 读取 v1-created Agent 的兼容性未保证，列为联调项。
3. 设置页对“官方支持”“仅当前网页支持”“本机偏好”分别绑定真实能力，不通过猜测路径补齐。
4. 仓库列表长缓存/懒加载；分页按 cursor，严格 ID 去重。模型参数动态读取，未知 enum/新增字段向后兼容。
5. 版本监测：固定 DTO contract fixtures + 开发阶段刷新 OpenAPI diff；当前 beta 文档已有 Agent IDLE enum 的偏差。
6. Capsule 的 Cursor Model / Other Model 只接受账户 usage snapshot 的明确 bucket；
   Agent tokens 仅任务详情展示，不能混算为套餐百分比。
7. 不在 Android 分发 service-account 管理 key；
   本机用户 key 使用 Android Keystore 保护，敏感请求禁止日志/备份；
   如需要 worker 管理则后端代理/明确管理员能力。
8. 实测必须覆盖：账户所持 key 权限、当前个人/团队环境 scope、SSE 410/重连、
   CreateAgent unknown outcome、CreateRun duplicate、v0 conversation 跨版本、
   envVars 灰度、secret 版本冲突。此核查没有执行这些真实 API。
