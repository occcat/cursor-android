> Historical Chinese research, completed on 2026-10-09. See the [English index](../README.md) for the current implementation status.

# Cursor Web API 分析

审计日期：2026-10-08。入口为 `https://cursor.com/agents`，使用 ego 读取已登录网页、
浏览器网络记录与网页实际交付的公开 JavaScript。另检查 Settings、Cloud Agents、
Environment、Automations、Plugins、Integrations、Codebase、Usage、Billing 和 Spending。

本文件记录 Android 所需的协议、接口分组和设置映射。逐路由的 HTTP 方法、
脱敏请求/响应结构与源码位置见：

- [网页接口目录](../api/cursor-web-endpoints.json)
- [Connect 与 VM RPC 描述符](../api/cursor-web-services.json)
- [官方公开 API 边界](cursor-public-api.md)

## 证据与覆盖边界

本次保存并复扫 428 个公开 JS chunks。它们含共用 Dashboard、企业管理、第三方库及
尚未进入的功能；路径候选数不能当作 Agents 实际调用接口数。最终目录含 857 个路由/候选，实际网络观察到 123 个不同路径，
其中 120 个拿到响应。证据标签可以重叠，精确分类保存在接口目录中。

目录的证据分为：

- `observed-response`：ego 网络记录实际看到响应；附状态码和类型结构。
- `observed-request`：看到请求，但该次捕获没有完整响应。
- `static-call`：公开前端存在 `fetch`、已解析的 HTTP helper 或 RPC 调用点。
- `static-descriptor`：服务描述符声明了方法，未找到其实际调用点。
- `static-candidate`：只发现路径字符串或尚未解析的 helper 参数。

一个接口可同时具有多种证据；统计不能直接相加。`refs` 是 `[bundle 文件名, 字符偏移]`，
偏移从 0 开始。公开 bundle 可用下列前缀加文件名复现，部署更新后可能失效：

```text
https://cursor.com/_next/static/immutable/chunks/
```

`queryNames` 仅记录 URL 查询参数名；`requestBodyShape` 记录 HTTP body 的类型。
捕获文件中的 `?keys=...` 是审计脱敏标记，不是服务端真实参数。
请求字段有时来自实际调用，响应字段有时只来自前端消费；未出现的字段
不表示服务端不存在。生产兼容性不能由一次 200 或描述符存在推导出来。

审计未执行 Agent 提示词、终端命令、文件保存或桌面接管。例外是导航到
`/automations/new` 自动创建了一个未启用的空草稿；已删除该本次产生的草稿，
并核对列表恢复为空。因此 create/delete automation 有实际调用证据，
其用途仅是这次编辑器副作用与清理，不能宣称全部写接口都已验证。

## 认证、作用域与传输

### 网页会话与团队

网页主要依赖同源浏览器会话。Connect transport 显式设置 `credentials: include`；
很多同源 `fetch` 使用默认 cookie 行为。没有证据证明公开 Cloud Agent API key
能替代网页会话，或能调用 Settings、Usage、VM 与所有私有接口。

`14ta1fxczl8a2.js` 的 module `3000723` 明确实现：

- 请求头 `x-cursor-team-id: <teamId>`，未选择团队时不发送。
- UI 团队 cookie 名 `portal-selected-team-id`。
- Secret 请求头是 `Content-Type: application/json` 加上述团队头。

请求体仍可能另含 `teamId`、`team_id`、`owner` 或 `expectedScope`；不能统一删除。
Android 的缓存与请求必须以账号、团队、Agent 三层作用域隔离；团队切换时取消旧流，
避免旧回调把不同团队的数据写入同一状态。

### CSRF 的真实边界

`3g296e7dwboay.js` / `05-fcgsyvm6g8.js` 的 `originPostJson` 明确使用：

- GET `/api/csrf-token`。
- Cookie `csrf-token`；配置了站点 base path 时用 `cursor-csrf-token`。
- 请求头 `x-csrf-token`。
- POST JSON，带 cookie 和可选团队头。
- 遇到 `403` 且 `error.code == invalid_csrf_token` 时重新取 token，并重试一次。

`1z7dbycgd57-k.js` 的 `requestPortalJson` 仅在非 GET 且 `csrf: true` 时启用
`withCsrfToken`。其 Dashboard 浏览器绑定使用 POST，未统一设置该开关。
所检查的 background-composer mutation 调用点也没有统一附加 CSRF 头。
这只能证明各调用点的前端行为，不能证明服务端永不要求 CSRF。

Android 应为 Origin 和明确要求 CSRF 的接口单独实现 token 获取/一次刷新，
其余接口照对应调用点建模；不要假设“所有 POST 同一个 token”或“全部无需 token”。
网页登录凭证、CSRF token、VM token 与公开 API key 是不同凭证。

### JSON、protobuf 与缓存

网页同时存在以下传输，不能用一个普通 JSON 客户端覆盖：

1. `/api/background-composer/*`、`/api/dashboard/*`、`/api/automations/*`：
   多数读写都是 POST JSON；有些 JSON 是 protobuf 的 JSON 表示。
2. `/api/connect-proxy/<service>/<method>`：Connect RPC，含服务器流。
3. `/api/background-composer/get-blob-for-agent-kv/{bcId}/{blobId}`：GET 二进制 blob。
4. `/api/files/{bcId}/*`：JSON、base64 文件和下载流。
5. VM WebSocket：自定义 JSON 信封内承载 protobuf 二进制。
6. VNC：WebSocket 上的 RFB/noVNC，与对话流、PTY 均不同。

protobuf JSON 中的 int64/uint64 可能是字符串；应保留 `Long` 或无损无符号表示。
枚举要容忍未知值。`fromJson(..., ignoreUnknownFields: true)` 在网页大量使用。

`fetchJsonConditionally` 以 method、URL、headers、body 建缓存键，发送 `If-None-Match`；
304 复用原 JSON。有 304 而无缓存时不带 validator 重试一次。
仅按 URL 缓存这些 POST 会跨请求体、团队或筛选条件串数据。

## Agent 核心接口

下列路径以 `/api/background-composer/` 为前缀，除标注外均为 POST。
R 表示实际看到响应；C 表示源码调用证据。写接口未实际执行时保持 C。

| 接口 | 证据 | 行为 |
| --- | --- | --- |
| `list` | R | 列表、分页、归档筛选、拥有者、置顶状态 |
| `get-detailed-composer` | R | 单个或批量 Agent 详情 |
| `available-models` | R/C | GET 查询参数或 POST 请求体，两种调用点都存在 |
| `pause` | C | 停止当前运行；网页会乐观改状态，失败回滚 |
| `mark-read` / `mark-unread` | C | 已读状态 |
| `pin` / `unpin` | C | 批量 Agent ID 的置顶状态 |
| `submit-interaction-response` | C | 回答 Agent 的交互问题 |
| `update-experimental-model-opt-out` | C | 单 Agent 的实验模型选择 |
| `get-diff-details` | R | 变更详情 |
| `list-artifacts` | R | 产物列表 |
| `get-artifact` / `get-artifact-bytes` | C | 产物地址/内容 |
| `get-machine` | R | 当前机器与临时连接材料 |

`list` 实際请求字段包括 `n`、`include_status`、`include_archived`、
`should_include_collaborators`、`owner_filter.owners[{id,owner_type}]`、
`include_pinned_state`；源码还支持 `last_message_activity_at_ms_offset`、`team_id`、
`include_sources`、`include_hidden_sources`。返回 `composers`、`participants`、
`hasMore`、`nextPageOffset/nextPageToken`、`pinnedBcIds`、`didLoadPinnedState`，
以及某些查询上的 `canUseBackgroundAgents`。

详情单条请求为 `{bcId,n:1,includeTeamWide:true}`；批量调用另用
`{bc_ids,n,include_diff,include_team_wide,include_archived?,status_only?}`。
返回 `composers[]` 中的 `composer`、prompt、分支、环境、diff 等。
不要把单条/批量字段命名强行统一为同一种序列化约定。

`available-models` 的 GET 以 `request=<AvailableModelsRequest JSON>` 为查询参数，
可加 `team`；Settings 内也有 POST 相同路径。响应 `models[]` 包含能力、展示名、
variants、参数、推荐状态；另含各场景 model config 与 `useModelParameters`。
应展示服务端实际可用模型，保留 `requestedModel` 的 `modelId/maxMode/parameters`。

生命周期另使用 `/api/auth/`：

- `startBackgroundComposerFromSnapshot`：POST，创建并启动 Agent。
  主要字段有 `bcId`、`prompt/richPrompt`、`requestedModels/modelDetails`、
  `repositoryInfo/repoUrl/baseBranch`、环境、图片、skills、MCP、机器选择、
  `expectedScope`；完整 descriptor 含更多来源专属字段，不能全当必填字段。
- `addAsyncFollowupBackgroundComposer`：POST，追问。
  `bcId`、`followup/richFollowup`、`followupMessage`、`followupId`、
  `requestedModel/modelDetails`、`followupSource`、`expectedScope`。
  descriptor 的响应为 `runId`。网页会在 404 且已归档时尝试恢复后重发。
- `archiveBackgroundComposer`：POST `{bcId}`；恢复带 `unarchive:true`。
- `renameBackgroundComposer`：POST `{bcId,newName}`。
- `wakeBackgroundComposer`：POST `{bcId,reason}`，消费响应 `signaled`。

上传是 presign/complete/abort 三步：`presignPromptUpload`、`completePromptUpload`、
`abortPromptUpload`。后续实现需要单独校验上传大小、失败恢复与临时 URL。
不要因为 start 请求超时就无条件重试创建；保留 `bcId/followupId` 并先查询确认。

Pending followup 使用以下 POST：

- `listPendingFollowups`：`{bcId}`。
- `updatePendingFollowup`：`{bcId,followupId,updatedMessage}`。
- `deletePendingFollowup`、`submitPendingFollowupNow`、`markFollowupEditing`：
  `{bcId,followupId}`。
- `reorderPendingFollowup`：另加 `targetFollowupId,insertAfter`。

响应会包含 `success/errorMessage`，不能只看 HTTP 200。

## Connect 对话与列表同步

服务为 `aiserver.v1.BackgroundComposerService`，完整描述符见服务目录。
源：`0trhuhkvsawxl.js`，transport 位于 `1l1m7vajkehly.js`。

`StreamBackgroundComposerUpdates` 已有 POST 200 的实际流连接证据。
请求字段包括 `resumeCursor`、`teamId`、`snapshotN`、`snapshotIncludeArchived`、
`snapshotIncludePinnedState`、`snapshotIncludeWorkers`、`snapshotIncludeSubagents`。
响应 oneof 为 `snapshot / event / heartbeat`。

`StreamConversation` 也已连接成功。请求包括 `bcId`、`offsetKey`、`purpose`、
`expectedScope`、prefetch 与 heartbeat 开关。响应不是简单的文本 token 流，而是：

- `initialState`、`cloudAgentStateWithIdAndOffset`。
- `interactionUpdateWithOffset`、`interactionQueryWithOffset`。
- `workflowStatusWithOffset`、`workerLifecycleEventWithOffset`。
- `prefetchedBlobs`、`streamSignal`、`streamHeartbeat`。
- `transientErrorWithOffset`、`interactionSettledWithOffset` 等。

Android 需要 offset/cursor、去重、断线续传、blob 缓存和状态归约器。
已 prefetched 的 blob 不应再次下载；缺失的才 GET agent-kv 路径。
把这个接口误做成 `EventSource` 或普通 JSON 数组会丢状态。
源码另存在供导出使用的 `/api/background-composer/stream-conversation` helper 路径，
不能凭同名就宣称它与 Connect 的 framing 相同。

其他已见调用点包括 `ListBackgroundComposerChildren`、
`StartSideChatBackgroundComposer`、`GetEnvironmentHistory`、
`GetBackgroundComposerEnvironmentVersion`、`DuplicateEnvironment`、
`RenameEnvironment`、`RestoreEnvironmentVersion`、`MigrateEnvironmentToOrigin`。
`ForkBackgroundComposer` 等注册方法若仅有 descriptor，目录会单独标明。

## 全局设置映射

### 个人 Cloud Agent 设置

读：POST `/api/background-composer/get-background-composer-user-settings`，已实测。
写：POST `/api/background-composer/update-background-composer-user-settings`，
前端发送部分字段 patch，成功后失效并重取设置；不是 PUT 全对象替换。
主要源为 `1utexe4gt31en.js`、`3lzefatc9wleb.js`。

| 设置 | 对应字段 |
| --- | --- |
| 默认模型 | `modelName`、`defaultModelSelection` |
| 分支前缀 | `branchPrefix` |
| CI 失败跟进 | `ciFailureFollowupEnabled` |
| 浏览器使用 | `browserUseEnabled` |
| Web Agent 的 Slack 通知 | `slackNotificationsForWebEnabled` |
| 自动 PR | `autoCreatePrSetting` |
| PR 打开位置 | `prReviewOpenDestination`、读取到的 `prReviewOpenSurface` |
| GitHub 产物发布 | `githubArtifactPosting` |
| 问题自动回答超时 | `askQuestionAutoAnswerTimeoutMinutes` |
| 网络保护 | `egressProtectionMode`、`egressPolicy.allowlist` |
| 私有机器 | `allowPrivateWorkers` |
| 远程控制 | `remoteControlEnabled` |
| 快捷子代理 | `quickActionSettings` |
| 多仓库上限 | `maxMultiRepoEnvironmentRepos`，只读限制 |

表中既有实际读取字段，也有写调用证据；不表示所有字段都对所有用户可改。
超时清除在网页写 `-1`；网络设置 patch 可带 `bcId`。
个人启用 remote control 时，网页可能同时写 `allowPrivateWorkers:true`。
团队禁止 remote control 时，个人页面不能绕过。

`quickActionSettings` 包括 slots、是否显式设置、catalog version、template mutations。
模板有 create/update/delete 操作和 personal/team/builtin scope；slots 还区分
`subagent` 与 `parent_agent`。不能把它们压缩成一个纯字符串快捷命令列表。

### 团队策略

POST `/api/dashboard/get-team-background-agent-settings` 与
`/api/dashboard/update-team-background-agent-settings`，请求包含 `teamId` 和写入时的
`settings`。权限在网页通过 `team.background_agent_settings.manage` 等判断。
主要 descriptor 为 `BackgroundAgentSettings`。

覆盖 allowlist、自动 PR、团队追问、测试、强制私有机器、自动化、VM sharing、
remote control、网络保护与锁定、Secret/Environment 仅管理员可写、产物共享、
数据保留、CI 跟进，以及私有机器 GitHub token mint/Secret sync。

Android 必须区分个人偏好、团队生效策略、团队锁定与无权修改。
不能拿个人设置的默认值覆盖团队策略。

### 账号、外观、通知与隐私

`/api/dashboard/` 的 typed `dashboardMethod` 会把 camelCase 方法名转为 kebab-case，
浏览器绑定统一使用 POST；源码中的“v2 数据层”不等于 URL 都是 `/api/v2/*`。

- Profile：`get-user-profile`、`update-user-profile`、`claim-user-profile-handle`。
  写入包括 `visibility`、`links`、`metadata`、`showPrivateOriginContributions`；
  handle 单独提交。返回 profile 与可用可见性边界。
- 姓名：`update-user-name`，字段 `firstName,lastName`。
- 头像：`upload-profile-picture` 为 POST 原始图片 bytes，Content-Type 为图片类型；
  返回 `profilePictureUrl`。删除头像走 `update-user-profile-picture`，传空 URL。
- 隐私：`get-user-privacy-mode`、`set-user-privacy-mode`；团队还有
  `get-team-privacy-mode`、`switch-team-privacy-mode`。响应可能含强制策略、宽限期、
  `partnerDataShare` 与 `accountPrivacyMode`。不要乐观假定修改总能成功。
- Router：`get-user-smart-auto-settings`、`update-user-smart-auto-settings`，
  `settings.enabled/showRoutedModel`，读取 `canEnable`。
- 非 ZDR 模型同意：`get-no-zdr-model-consent-status`、`set-user-no-zdr-model-consent`；
  写 `modelId,enabled,acknowledged,consentVersion`。
- 会话：GET `/api/auth/sessions`，POST `/api/auth/sessions/revoke`。
  列表已有 200；撤销只确认前端调用与 POST，不能据此声称 Android 可重新签发会话。
- 通知：网页 push token 的 register/delete 接口存在；Android 的 FCM 支持与 token
  平台参数仍需单独验证，不能把浏览器 PushSubscription 直接当成 FCM token。
- Appearance：已有 light/dark/system 与命名主题的本地 theme hook，
  没有发现能证明云端同步的 Appearance REST 接口。Android 用本地 DataStore。

账号删除、套餐支付、组织合并、第三方 OAuth 等在完整目录中保留候选，
Android 首阶段通过受控网页入口完成，不擅自扩大为原生管理功能。

## 环境、Secrets、MCP 与 Plugins

环境的 POST 包括 `list-environments`、`get-environment`、个人/团队 list 与 set/delete、
`resolve-or-create-draft-environment`、`resolve-or-create-multi-repo-environment`。
`get-environment` 用 `{publicId,includeEnvironmentJson}`。
返回环境 ID、scope、repoConfig、environmentJson 与版本。
列表支持分页与包含无仓库访问权的环境；不能把环境列表视为仓库授权清单。

构建设置与记录分别走 `get-environment-build-settings`、
`update-environment-build-settings`、`list-environment-builds`、
`get-environment-build`、`get-environment-active-build`；写操作另有 trigger/cancel/update。
更新设置支持 `fastForwardDefaultBranch`、`autoFastForwardStalenessHours`，
对应 clear 字段表达清除；descriptor 另有 buildsEnabled。

Secrets 使用 POST：

- `list-background-composer-secrets`：`teamScope,owner,surface`。
  响应消费 `id,name,createdAt,scopedToRepos,level,surface,owner`，不应读取明文旧值。
- `create-background-composer-secret-batch`：`secrets,teamScope,owner,scopedToRepos,surface`。
  逐项返回 created/updated/error，批量 HTTP 成功不代表每项成功。
- `update-background-composer-secret`：`id,name,value,level` 与同样的 scope 字段。
- `revoke-background-composer-secret`：`id,name` 与 scope 字段。

owner 可为 user、team、environmentId；level 区分环境变量、运行时 Secret、构建 Secret。
Android 固定 Cloud Agent surface，排除 Grok Bot surface。Keyring 的 list/get/create/
rename/delete、secret 与权限 grant/revoke 也有前端调用；不要把所有 keyring 候选变成
个人用户必定可用的 UI。

MCP 的 POST：

- `get-mcp-config`：`teamScope,teamId?,redactSecrets:true`，返回 `configJson` 与
  `serverMetadataByName`；Android 保持 redaction，不为了编辑而请求旧明文。
- `set-mcp-config`：`configJson,serverRenames?,serverIdsByName?` 与 scope。
- `get-available-mcp-servers`：返回 server、enabled、accounts 与授权状态。
- `check-http-mcp-status`：`servers:[{id}]`，返回可用性、requiresAuth、authUrl 等。
- `update-user-default-mcp-settings`：`enabledServerIds`。
- OAuth account/token delete、rename、move-to-team、mark-seen 与工具预览另有接口。

Plugins 涉及 marketplace/list、effective installs、install/uninstall/update，
及 repo/global/team slash commands 与 cloud-agent plugin snapshot。
任务启动需要选择后的快照/清单与上下文；不能只把 Plugin 名加入 prompt。
OAuth 连接使用网页授权流程；不应在 Android 硬编码提供商登录或复制旧授权 token。

## Automations、Codebase、集成与 PR

`/api/automations/` 的以下调用点均为 POST JSON：

- list/get：`list-automations`、`get-automation`。
  get 用 `automationId,teamId?`，结果可能是完整 workflow 或 restrictedSummary。
- create/update/delete：主要字段 `name,description,workflow,scope,managedType`，
  create 可带 `templateId,teamId,creationSource,enabled`；update/delete 带 automationId。
- templates：list/get/create-from-template；实例化需 templateId 与 inputValues。
- runs：list-all-runs、get-automation-run、get-run-summary；可带 automationId、
  teamId、ownerOnly、limit、cursor，返回 runs/nextCursor 或统计窗口。
- run 写操作：test、cancel、cancel-all、retry；test 会运行，不能当作只读验证。
- memory：list/get/update/delete；update/delete 带 version 或 expectMissing，
  返回 conflict/content/version/files，必须处理并发冲突。
- managed team settings、owner reassignment、工具校验、authoring mode 也独立建模。

注意自动保存：网页新建入口已证明可能立即创建草稿。
Android 应先本地编辑，用户显式保存才创建；保存、启用与 Test Run 分开。

Codebase/Origin 使用 `/api/origin/<method>` 的 POST + CSRF helper。
确认的调用族有 namespace、list-hosted-repos、get-repo、resolve-repo-path、
get-repo-content-at-sha、SSH public keys、访问邀请、repo creation 等。
Codebase 浏览内容和启动 Agent 使用的 SCM 仓库选择是相关但不同的授权模型。

Integrations 涉及 GitHub/GitLab/Bitbucket/Azure DevOps 状态与安装仓库，及 Slack、
Linear、Jira、Sentry、PagerDuty、Microsoft Teams。Android 最少读取连接状态和仓库，
连接/解绑及组织策略先进入网页。不要接入 Grok Bot 或账号 unification。

PR 读取有 merge status、detailed status、commits、discussions、timeline 和 batch refresh。
写操作有 open-pr、merge、update-branch、draft conversion、auto-merge 开关、review reply、
resolve/unresolve thread。它们分别是不同 POST，不能把“打开 PR”视为合并授权。

## Usage 给胶囊和状态栏的契约

GET `/api/usage-summary` 可带 `teamId`；已实测响应：

- `billingCycleStart/billingCycleEnd`、membership/limitType/isUnlimited。
- `individualUsage.plan` 下的 used/limit/remaining/breakdown。
- `autoPercentUsed/apiPercentUsed/totalPercentUsed`。
- `individualUsage.onDemand` 与 `teamUsage`。

还有 GET `/api/usage?user={userId}` 的旧请求/令牌计数，及 Dashboard 的
`get-current-period-usage`、`get-aggregated-usage-events`、`get-filtered-usage-events`、
周期与账单接口。机器 CPU/内存的 `get-machine-resource-usage` 绝不是模型使用额度。

胶囊只保留 Cursor Model 和 Other Model。字段映射以既有 Cursor Usage 的语义及
该账号的实际使用响应验证为准；`autoPercentUsed` 的字段名本身不能证明它永远等于
“所有 Cursor 自有模型”，也不能由 `totalPercentUsed` 减一组推算另一组。
空值/无限额/独立团队额度应显式表示，不能显示成 0% 或自动补齐为 100%。

## Terminal、Files 与 Desktop

### VM 发现与临时连接

`get-machine` 请求 `{bcId,mintDesktopTicket?:true}`。
普通查询未带 mint；私有机器桌面连接可用 mint 请求临时票据。
实际观察到 pod 的 `podId,tenantId,cluster,networkToken,ptyAuthToken` 等字段；
源码还消费 worker.desktop 的 wsUrl/sessionId/sessionSecret/controlAllowed。
这些都是瞬时连接材料，不写入日志、导出文档、Room 或外部 URL 历史。

VM URL 源：`2kx23d6enma5-.js`，module `8207929`，字符偏移 46992：

```text
wss://{tenantId}-{podId}-{port}.{cluster}.cursorvm.com:443/{path}
  ?network_token={issuedToken}&resume_lower_s=900&resume_upper_s=18000
```

PTY/Tmux 端口 26054；VNC 26058，旧端口 6080。
这是从 get-machine 返回值构造的临时 URL，不能硬编码真实机器地址。

### PTY 与 Tmux

源：`2kx23d6enma5-.js` 8831、`3dmksujsx09br.js` 125600 附近。
传输为 WebSocket JSON envelope，RPC 的 protobuf bytes 先 base64：

```json
{
  "type": 1,
  "requestId": "generated-id",
  "path": "/agent.v1.PtyHostService/SendInput",
  "method": "POST",
  "headers": {
    "content-type": "application/proto",
    "connect-protocol-version": "1"
  },
  "body": "base64-protobuf"
}
```

认证使用 pod 的 ptyAuthToken，既进入 WS 的 `token` 参数，也进入 RPC Authorization。
类型 1/2/3/4/5/6 分别是 REQUEST/CANCEL/RESPONSE/HEADERS/END/ERROR。
流使用 `application/connect+proto`；每帧为 1 字节 flags、4 字节大端长度、payload。
不能把终端输入直接 send 成裸文本。

| 服务 / 方法 | 输入 | 输出 |
| --- | --- | --- |
| Tmux / ListSessions | 空 | sessions |
| Tmux / CreateSession | name/displayName/kind/process/cwd/env | session |
| Tmux / AttachSession | sessionId/cols/rows | ptyId/session |
| Tmux / KillSession | sessionId | success |
| PtyHost / ListPtys | 空 | ptys |
| PtyHost / SpawnPty | process/cwd/env/cols/rows | ptyId |
| PtyHost / AttachPty | ptyId/lastEventId? | PtyEvent 流 |
| PtyHost / SendInput | ptyId/data(bytes) | success |
| PtyHost / ResizePty | ptyId/cols/rows | success |
| PtyHost / TerminatePty | ptyId | success |

服务完整名为 `agent.v1.TmuxSessionService` 与 `agent.v1.PtyHostService`。
精确 protobuf 字段编号见服务目录；表中 CreateSession 的名字字段是 `sessionName`。
PtyEvent 携带 eventId 与 ptyData/ptyExited，断线保存 lastEventId 后继续 attach。
UTF-8 解码必须跨消息保留未完成字节，输出缓冲需要上限。

网页打开 Terminal 可能自动 CreateSession 或 SpawnPty，所以本次没有点击终端入口。
Android 将“查看已有终端”和“新建终端”区分；离开页面仅取消 attach，不默认杀 shell。

### Files

源：`3dmksujsx09br.js` 50180 与 `15rxqhgne36us.js`。
前缀 `/api/files/{bcId}`；同源 cookie，无发现直接 VM token 或团队头。

| 方法 / 子路径 | 请求 | 响应 |
| --- | --- | --- |
| GET `list` | path、includeHidden | entries |
| GET `read` | path | content 文本 |
| GET `read-binary` | path | content base64 |
| POST `write` | JSON path/content | 成功 JSON，字段未消费 |
| GET `download` | path | 浏览器下载，响应头未实测 |

entry 消费 name/path/type/sizeBytes/modifiedAtUnixMs，区分 file/directory/symlink。
源码未证明写入具备 ETag/revision 冲突保护；Android 需保留 dirty 状态与失败内容，
不承诺服务端自动合并。网页“下载有修改的文件”会先 Save，应避免把下载当纯读审计。

AgentStore 的 ListAgentStores/ListAgentStoreEntries/ReadAgentStoreFile 属于 Connect，
和 live VM Files 不同。产物 `get-artifact-bytes` 可用于机器消失后的保存内容读取，
响应消费 base64 content 与可选 contentType。

### Desktop

源：`2ixqj3j1sp_3o.js` 与 `0nx8vkzxcv7w3.js`。
Cloud pod 使用 VNC `/websockify`；实际前端是 WebSocket + noVNC。
库里出现 RTCDataChannel 不构成应用使用 WebRTC signaling 的证据。

私有 worker 桌面使用票据 wsUrl；WebSocket subprotocol：

```text
binary
cursor-desktop-ticket.{sessionId}.{sessionSecret}
cursor-desktop-control    # 仅控制模式
```

默认 view-only。接管会中断 Agent，必须由用户触发。
Connect `DesktopLease` 用 `{bcId,action:ACQUIRE|RELEASE,surfaceId}`，返回 held。
已找到源码租约 TTL 30 秒，每 10 秒以 ACQUIRE 续租；超时/丢租立即退为 view-only，
后台/退出释放。`surfaceId` 在同一租约期间稳定。不要在页面显示时自动接管。

## Android 接入顺序与验证缺口

建议先落地会话/模型/Usage/只读设置，再做创建追问、设置 patch 和环境/自动化，
最后接入独立的 VM transport、终端、文件与桌面。每层要有受限/过期/离线/未知状态。

仍需在实现阶段验证：网页登录的受支持登录路径、Android 会话迁移方式、各团队权限、
Connect 实际协商编码、写接口幂等性、FCM 支持、VNC 安全协商、文件并发写与 API 变更。
公开前端协议不构成第三方 API 稳定性承诺，官方 v1 与网页私有接口必须分开管理。
