> Historical Chinese research, completed on 2026-10-09. See the [English index](../README.md) for the current implementation status.

# Android 原生实现方案

调研日期：2026-10-08（Asia/Shanghai）。本文是设计，不代表 Android 功能已实现或验证。

产品范围以 [README](../../README.zh-CN.md) 为准：原生 Android 客户端用于发起、跟进、审阅
Cloud Agent，并覆盖 `cursor.com/agents` 的会话、环境和工作面板。
本次不接入 Grok Bot；用量只保留 Cursor Model 与 Other Model。
账号、账单、源码托管绑定仍在网页或 Dashboard 管理；本次运行的 Secret 可以原生管理。

配套材料：

- [网页接口清单与实测证据](cursor-api-inventory.md)
- [官方 API 明细与版本边界](cursor-public-api.md)
- [胶囊、状态栏与页面 UI 设计](design/cursor-android-ui.md)
- 用量参考源码：`../../grok-usage-floating` 的 `sites/cursor` 与 `packages/core/src`。

本文中的“官方支持”表示官方文档存在相应能力，不表示本次已通过真实账号调用。
“网页适配”只允许实现接口清单中已有证据的协议；无证据项必须先验证。
仅由静态前端代码发现的路径不能等同于已确认可用的 Android API。

## 1. 先解决的技术边界

推荐以官方 Cloud Agents v1 为新运行的主通道，网页私有 API 补齐网页特有能力。
两条通道使用不同凭据和适配器，通过同一领域模型向 Compose 提供数据。
官方 v1 目前仍处于 public beta，应隔离 DTO 与领域模型，保留接口版本和降级路径。
[来源：Cursor Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints)

以下问题是 P0 验收条件，不能在实现前承诺：

1. **账号登录**：Cursor 及其第三方 SSO 是否允许 Android WebView 完成登录；
   回跳、Passkey、挑战页面、cookie 分区和会话刷新是否可用。
2. **凭据关系**：网页登录与用户 API Key 是否对应相同账号、团队和权限范围。
   本客户端尚无经验证的 Cursor OAuth/device-code 授权接入，不应虚构令牌交换接口。
3. **数据可见性**：网页已有运行是否出现在 v1 列表，双方 Agent/Run ID 是否直接对应，
   不同机器环境、历史会话和归档是否一致。即使 ID 字符串相同，也要验证实际记录。
4. **完整历史**：官方 Run stream 的保留期、网页历史会话接口和完整工具记录的关系。
   本地缓存能保留本机已经同步的内容，但不能创造从未取得的历史。
5. **工作面板**：Desktop、Terminal、Files 的认证、短期会话、数据传输与断线语义。
   不从界面名称推断 WebSocket、VNC、PTY 或下载路径。
6. **用量**：`usage-summary` 的当前账号响应能否复现参考仓库中的两个额度池字段。

P0 未通过时，仍可交付官方 API Key 模式下已验证的原生功能，但要清楚标明数据来源。
网页登录阻塞会同时阻塞私有设置和个人用量；不能把网页入口或演示数据标成原生接入完成。
不为绕过登录限制而读取其他应用的浏览器 cookie，或将桌面浏览器会话直接搬到手机。

## 2. 功能与通道矩阵

| 功能 | 首选实现 | 边界与验收 |
| --- | --- | --- |
| 会话列表、分页、归档/恢复 | v1 原生 Repository | 网页历史可见性待 P0；不同来源暂不合并 |
| 搜索、置顶、自定义列表 | 网页已确认接口；无接口时本地搜索缓存 | 本地状态与服务端同步状态要明确区分 |
| 新建 Cloud Agent | v1 Agent + 初始 Run | 提示词、环境、模型、仓库等只发送已支持字段 |
| 单仓库、多仓库、从零开始 | v1 创建参数 | 不同环境的仓库数量规则从官方契约校验 |
| 仓库添加、SCM 绑定 | 原生展示可用仓库，管理入口到网页 | 不原生重做账号与源码托管绑定后台 |
| 模型、参数、多模型 | v1 模型发现；网页多模型能力另行核验 | 多模型不能简单循环创建并宣称等同网页语义 |
| Files、Skills、MCP 上下文 | 已验证的官方字段或网页上传/选择协议 | 附件、技能引用和 MCP 配置不能混成普通文本 |
| 语音输入、照片、相机、文件 | Android 系统能力及已确认的上传协议 | 运行时申请相关权限；遵守服务端大小/格式限制 |
| 实时会话、追问、取消 | v1 Run 与 SSE | 已有活动 Run 时处理冲突，取消与新追问分开 |
| 子代理卡片、斜杠命令 | 已确认事件/上下文能力 | 不靠字符串猜测子代理关系或命令执行结果 |
| Fork Chat、Side Chat | 网页已确认接口 | 必须保留服务端分支/上下文语义，不仅复制提示词 |
| Changes、diff、Review、PR | 原生 diff 阅读器 + 已确认数据源 | PR 链接用浏览器打开；不擅自等同于 PR 合并 |
| Environment、Secret、继承用户设置 | v1 与网页运行配置适配 | 区分持久环境 Secret 与本次运行 Secret |
| Desktop、Terminal、Files 面板 | 原生导航和连接状态，逐项协议适配 | 初期可用受控网页面板过渡，必须标明完成层级 |
| 截图、录像、日志、产物 | 官方/网页产物元数据 + 原生查看/下载 | 下载链接可能过期，重新签发，不永久缓存凭据 URL |
| Automations、模板、All Runs | 网页已确认自动化接口 | 服务端执行；WorkManager 不充当远端自动化引擎 |
| Codebase Early Beta | 网页已确认能力 | 按账号能力开放；未开通时给明确状态 |
| Cloud、Team Pool、My Machines | v1 环境/机器能力与网页补差 | 手机为控制端，不能冒充 worker 或创建机器凭据 |
| Remote Control | 先验证目标机器、连接和会话协议 | 手机不本地执行目标电脑的终端与测试 |
| 个人用量两池 | 网页 `usage-summary` | v1 Agent token usage 不等于账户额度池百分比 |
| 账号、账单、高级账号设置 | Dashboard/网页入口 | 可分析接口，但不扩大为原生管理产品 |

每个功能以 `Capability` 描述可用性，而不是只用一个全局“已登录”判断。
建议状态为 `available`、`requiresWebSession`、`requiresApiKey`、`notEntitled`、
`notVerified`、`temporarilyUnavailable`。加载中不等于未开通；服务端错误不等于无权限。

能力判断来源依次为：明确的服务端能力字段、已验证权限结果、已完成的适配器实现。
“文档有接口”仅说明可进入实现，不直接点亮产品按钮。

## 3. 原生工程组织

建议新工程采用 Kotlin、Jetpack Compose、Material 3、单向数据流、Coroutines/Flow、
Room、DataStore、OkHttp 和 Kotlin Serialization。具体依赖版本在建工程时锁定，
本次不生成占位 `build.gradle.kts`，也不伪造现有构建结果。

建议目录如下，最终包名和 `applicationId` 在工程初始化时确定：

```text
app/                         应用入口、导航、依赖装配
core/model/                  Agent、Run、Usage、Capability、领域错误
core/network/                HTTP、SSE、超时、脱敏、协议 DTO
core/database/               Room、事务、迁移、账号隔离
core/auth/                   API Key、WebSession、Keystore、注销
core/designsystem/           主题、字体、无障碍、共享状态组件
core/testing/                脱敏 fixture、时钟、Fake Repository
data/cursorapi/              官方 v1 适配器
data/cursorweb/              网页私有 API 适配器
data/repository/             数据同步、能力路由与来源映射
feature/inbox/               收件箱、搜索、列表、置顶、归档
feature/composer/            新运行、多仓库、模型、上下文、草稿
feature/conversation/        消息、工具、子代理、追问、Fork/Side Chat
feature/workspace/           Environment、Changes、Desktop、Terminal、Files
feature/automations/         模板、配置、运行记录
feature/codebase/            Codebase 能力入口
feature/usage/               两池、周期、pace、详情
feature/settings/            本地偏好、展示、连接状态、网页管理入口
feature/overlay/             可选跨应用悬浮层及其生命周期
feature/notifications/       通知、深链、可选 Live Updates
```

初期可以使用较少 Gradle 模块并保持上述包边界；有独立测试与依赖隔离收益时再拆模块。
Compose 页面只调用 ViewModel，ViewModel 不读取 CookieManager、HTTP JSON 或数据库表。
网络 DTO 不直接成为 Compose state；运行、展示与用户输入均映射为不可变 UI state。

`UsageRepository` 是应用内胶囊、跨应用胶囊和通知的唯一数据源，三者不得各自轮询。
工作面板也复用会话的账号、Agent 与环境身份，不建立不受控的第二套登录逻辑。

## 4. 身份与认证

### 4.1 官方 API Key 通道

用户从 Cursor Dashboard 提供其允许使用的 API Key，客户端验证身份后建立独立连接。
仅对确认的官方 API origin 设置 Authorization；不能向网页、产物下载域名或重定向目标
自动转发该 header。Key 的范围不足应显示具体能力缺失，不自动请求更高权限。

保存 `connectionId`、脱敏显示名、服务端账户/团队标识和认证方式，不在普通偏好里保存 Key。
API Key 的管理、创建和撤销入口留在网页；不默认创建团队、管理员或 worker 凭据。

### 4.2 网页会话通道

专用登录 WebView 仅加载经调研确认的 HTTPS origin，并跟随合法认证回跳。
通过本应用的 `CookieManager` 管理 WebView cookie：按准确 URL 取请求 cookie、
接收更新、持久化和注销；不能仅复制一次 Cookie header 后假定永久有效。
相关操作要有串行化与会话代次，防止旧请求在退出登录后写回旧会话。

Android WebView 与系统浏览器不共享 cookie。Custom Tabs 适合第三方登录和管理页面，
却不能被当作浏览器会话导出工具。SSO 若禁止 WebView，必须取得受支持的回调授权方式，
否则保留网页管理和官方 API Key 模式，标记 WebSession 不可用。
[文档](https://developer.android.com/develop/ui/views/layout/webapps/overview-of-android-custom-tabs)、
[CookieManager](https://developer.android.com/reference/kotlin/android/webkit/CookieManager)

不能用 `document.cookie` 作为完整 cookie 源；不能用全站 JS bridge 暴露读取密钥、
发送任意原生请求或执行本地命令的能力。HTTP 401、明确的 `not_authenticated` 进入
`expired`；403 只有被确认是认证失效时才按退出登录处理，其余保留权限错误含义。

### 4.3 身份关联与退出

领域主键包含来源与账号：`ConnectionKey + RemoteId`。网页和官方 ID 关系在验证前
不做自动合并，也不把两个同名 Agent 当同一会话。关联成功后记录可撤销的来源映射。

退出某条连接时：递增会话代次、取消其请求/流、清除凭据与 cookie、移除通知、
清理或锁定账号缓存、清空内存 Secret。切换账号时新页面不可闪现旧账户数据。
系统备份不包含凭据、WebView 会话、秘密草稿或带敏感内容的调试日志。

## 5. 领域数据与状态机

### 5.1 数据模型

| 模型 | 建议字段与用途 |
| --- | --- |
| `Connection` | 来源、账号/团队、认证状态、能力集合、会话代次 |
| `Agent` | 来源 ID、名字、生命周期、环境、仓库、最新 Run、网页链接 |
| `Run` | Agent、Run ID、状态、开始/更新时间、模型选择、结果、错误 |
| `TimelineItem` | 本地 ID、远端事件 ID、Run、类型、内容、顺序、同步来源 |
| `ToolCall` | callId、名字、状态、经过限长的输入/输出、截断标记 |
| `WorkspaceSnapshot` | 环境、仓库、分支、PR、diff 版本、工作面板能力 |
| `Artifact` | Agent、远端路径、MIME、大小、更新时间、本地缓存状态 |
| `SyncCheckpoint` | 来源、Agent、Run、opaque cursor、已应用事件位置 |
| `Draft` | 本地 ID、目标连接、仓库/模型选择、文字、附件状态 |
| `UsageSnapshot` | 连接、抓取时间、周期、套餐、两个固定额度池、可用性 |

Agent 与 Run 生命周期必须分开；一个 Agent 可以有多个历史 Run。
UI 的“正在运行”来自当前 Run，不把 Agent 仍然存在当成任务仍在工作。
未知服务端枚举保留原值并显示“未知状态”，避免升级后因严格枚举解析直接崩溃。

### 5.2 状态机

```text
Auth: signedOut -> authenticating -> active -> expired
                               \-> failed

Connection: idle -> connecting -> streaming -> reconnecting -> streaming
                                 |                |
                                 +-> ended        +-> needsAuthentication
                                 +-> failed       +-> snapshotOnly

Draft: editing -> validating -> submitting -> accepted
                     |              |
                     +-> invalid    +-> failed / outcomeUnknown

Run: creating -> running -> finished / error / cancelled / expired

Usage: loading -> fresh / partial / unavailable / signedOut
                   |
                   +-> stale（快照仍保留）
```

`paused` 是本地刷新偏好，不应覆盖 Usage 的 `stale` 或认证失效状态。
“取消中”是本地操作状态，只有收到服务端确认才将 Run 改为 cancelled。
本地发送文本先显示待确认项；收到远端对应结果后合并，失败则提供明确重试入口。

### 5.3 实时事件落库

`RealtimeCoordinator` 按连接和 Run 管理流，优先订阅当前打开的运行；列表状态通过
轻量同步更新。每个事件经过解析、校验、去重、reducer 和 Room 事务，再更新 UI。
文本增量在短窗口内合并刷新，避免逐 token 写数据库与引起全列表重组。

官方 SSE 断线使用 `Last-Event-ID` 恢复；游标是 opaque 字符串，不能解析时间或排序。
无 ID 的初始 `status` 可重复发送；同一流中不同事件类型可能复用 ID，不能仅以 ID
丢弃所有后续帧。使用协议事件身份与 reducer 幂等性去重，检查最终结果与 done 的组合。
只选择 simplified 或 `interaction_update` 中一条完整渲染路径，防止文字与工具重复。
`410 stream_expired` 改取 Run 快照和终态；完整旧过程可能不可恢复，应明确显示缺口。
[来源：Cursor Run stream](https://cursor.com/docs/cloud-agent/api/endpoints#stream-a-run)

私有网页实时协议必须按其自身序号、快照和握手机制实现，不把 SSE 恢复规则套到未确认协议。
进程重启时先加载 Room、读取远端最新 Run，再决定恢复流；不能从本地 running 推断远端还活跃。

## 6. 离线、错误与重试

采用本地优先读取：收件箱、已同步会话、已缓存 diff 和产物离线可打开，并显示同步时间。
在线同步以 Room 事务更新页面观察源；旧页面不能因为请求失败退回空白。
大型录像和完整仓库文件按需缓存，设置容量、过期和清理入口，不承诺全仓库离线镜像。
[离线架构](https://developer.android.com/topic/architecture/data-layer/offline-first)

| 情况 | 行为 |
| --- | --- |
| 网络断开、超时、暂时性 5xx | 读请求指数退避加抖动，保留快照；用户可手动刷新 |
| 429 | 遵守 Retry-After/已验证限流约定，合并触发，不轮流冲击多个入口 |
| 401 / 明确认证失效 | 停止该连接重试，显示重新登录入口 |
| 403 权限/套餐限制 | 显示所需权限或当前不可用，不反复登录 |
| 404 | 区分资源消失、不可见和路由失效；刷新列表并保留本地只读记录 |
| 409 运行冲突 | 同步当前 Run，解释为何不能继续提交；不自动取消已有运行 |
| 410 流过期 | 回到快照读取，记录历史缺口，不无限重开流 |
| JSON/字段不兼容 | 隔离该能力，记录无秘密的字段诊断；可用页面继续工作 |
| 写入响应丢失 | 标记 outcomeUnknown，查询远端对账后再决定重试 |
| 分页循环、游标重复 | 停止继续加载，保留当前结果并报告同步失败 |

GET 等幂等读取可自动重试；写请求只有服务端明确支持幂等键或操作本身可幂等时才自动重试。
不为尚未核验的接口自行发明 `Idempotency-Key`。创建、追问、终端输入、Secret 更新、
自动化启用等都可能有副作用；离线只保存草稿，不在恢复网络后无提示执行过时意图。

Room 中远端状态带服务端版本/更新时间和本地抓取时间。重复列表页不能覆盖较新的流状态。
若远端没有可比较版本，则由单连接同步协调器串行提交快照，必要时重新拉取完成对账。

## 7. 双模型用量与 pace

参考仓库使用 `GET https://cursor.com/api/usage-summary`，凭据来自网页登录会话。
本次 ego 已观察到 200 与两个字段；Android 会话可用性仍需真机验证。
不请求 Bot 接口，不显示第三行，也不使用第三产品的套餐字段作 fallback。

固定映射为：

| 池 | 后端字段 | UI 标签 |
| --- | --- | --- |
| `cursor` | `individualUsage.plan.autoPercentUsed` | Cursor Model；紧凑 Cursor |
| `other` | `individualUsage.plan.apiPercentUsed` | Other Model；紧凑 Other |

它们是服务端额度池，不按客户端的模型名分类。
不能由 `plan.used / plan.limit` 推算百分比，不能用单 Agent token usage 替代账户用量。
保留 raw 百分比用于诊断；进度几何 clamp 到 0–100。缺失池固定显示 `—`，不移动另一个槽位。
`isUnlimited === true` 才显示 `∞`，且不计算 pace；无套餐字段则不显示套餐 badge。

`UsagePool` 建议包含 `rawUsedPercent`、`displayUsedPercent`、`unlimited`、`availability`；
`UsageSnapshot` 包含 `billingCycleStart`、`billingCycleEnd`、`membershipType`、`fetchedAt`。
百分比、日期和套餐解析均放纯 Kotlin 层，依赖注入 `Clock` 以便验证周期边界。

pace 保持参考语义：

- 两池共享月账单周期；合法 start/end 区间为 1–32 天。缺少合法 start 时，从 end
  倒推一个日历月并钳制月末日期，不能固定减 30 天；缺 end 则 unknown。
- `target` 为当前账单周期日结束时的累计使用目标，不是本地自然日午夜目标。
- `delta = used - target`；±5 个百分点为 On pace；大于 +5 表示用得快；
  小于 -5 表示用得慢；`used >= 100` 表示 full。
- 剩余每日可用量为 `max(0, 100-used) / max(remainingDays, 1/24)`。
  周期经过至少 4% 后才显示线性投影；投影只是当前速度估计。
- end 已过且还未取得新周期数据时标 stale，保留旧数与同步时间，不能本地强制归零。
- “七格”表示整个周期的七等份，不是最近七天。

前台默认 60 秒刷新，可提供 30/60/120/300 秒选项；最低值需经过服务端限流验证，
不移植浏览器参考中的 3 秒高频下限。时间与 pace 每分钟本地重算，不因此请求 API。
请求合并、手动刷新取消旧请求、暂停保留数据；跨重置边界执行一次去重刷新。
重复收到旧 reset 时间不进入刷新死循环。

应用不可见时停止常规 UI 轮询。用户开启可见 overlay 后由同一 Repository 按受控周期刷新；
无可见界面时只安排非实时后台同步。几何、配色、拖动、无障碍和展开卡片见
[UI 设计](design/cursor-android-ui.md)。

## 8. 工作面板与设置实现边界

### 8.1 Changes、Review 与产物

原生 diff 页面支持文件树、文件变更摘要、按文件查看、折叠上下文、二进制占位和大文件限制。
每份 diff 绑定来源、Agent、仓库和快照版本，更新后不把旧行号的选择误用到新版本。
多仓库按仓库分组；PR 操作引用对应仓库，不依赖列表第一项。

下载先取得服务端签发链接，再按返回信息请求；Cookie 和 API Key 不能泄漏到产物 CDN。
下载链接过期后重新获取。文件路径与 MIME 视为不可信数据，限制目录穿越，
通过系统内容 URI 分享文件，不直接暴露应用私有目录。

### 8.2 Desktop、Terminal 与 Files

这三个面板在产品范围内。第一阶段先完成原生导航、加载/错误/连接状态和网页过渡入口；
随后逐个验证协议再提供原生交互。网页过渡层不等于三个原生面板已经完成。

- Desktop：验证帧传输、输入事件、坐标缩放、键盘、旋转和会话失效。
- Terminal：验证会话创建/恢复、输出顺序、编码、resize、输入回执；
  输入超时不自动重放，防止相同命令执行两次。
- Files：验证列表、分页、读写、上传/下载、路径范围与权限；
  文件编辑若纳入实现，必须有保存冲突检测和版本依据。

通过 WebView 承载过渡面板时复用本应用的网页登录管理，限定域名与导航范围，
外部站点用浏览器打开；不向整个页面注入密钥或任意 native API。

### 8.3 Secret 与设置

设置拆为三类：

| 类别 | 原生范围 |
| --- | --- |
| 本地偏好 | 主题、语言、用量刷新/暂停、胶囊样式/位置、通知、缓存清理 |
| 当前运行配置 | 环境查看、运行 Secret、继承用户设置、模型与已确认的运行参数 |
| 账号级管理 | 账号、账单、SCM 绑定、密钥管理、高级账号设置，保留网页入口 |

查看运行实际使用的环境与修改持久环境模板是不同操作；UI 明确显示影响范围。
读取 Secret 列表不意味着服务端允许取回明文。已有秘密默认只显示名称与状态；
新输入只在提交期间驻留内存，成功后清空，不回显至通知、日志或自动草稿。
更新成功后重新读取允许返回的元数据，不能把提交内容当成服务器已应用的证据。

参考用量设置可迁移 pace style、classic/graded 色彩、折叠样式、套餐 badge 和恢复默认；
没有产品拆分数据就不显示 `showBreakdown`。设置采用单一预览组件，
非法输入不落盘、刷新数值提交后再生效；恢复默认保留语言与认证。

## 9. 胶囊、前台服务与状态栏

三层展示各有职责，不能把应用内自绘能力当作系统状态栏能力：

| 表面 | 实现 | 保证与限制 |
| --- | --- | --- |
| 应用内胶囊 | Compose | 无额外权限；首期交付完整双池展示 |
| 跨应用胶囊 | WindowManager + ComposeView | 用户主动授权 SYSTEM_ALERT_WINDOW |
| 系统通知/状态栏 | NotificationCompat；可选 Live Update | 外观、可见性、权限与 OEM 由系统约束 |

`TYPE_APPLICATION_OVERLAY` 在普通 Activity 之上，但位于系统状态栏与输入法之下；
系统可调整其大小、位置与可见性。因此 overlay 不能被描述为“嵌入系统状态栏”。
需处理挖孔、系统栏、键盘 Insets、旋转、大字体和多窗口；权限撤销后安全移除窗口。
[来源：WindowManager](https://developer.android.com/reference/android/view/WindowManager.LayoutParams)

常规状态栏显示系统小图标；双池文字与进度放通知抽屉。Android 13+ 普通通知需要
`POST_NOTIFICATIONS`，拒绝权限后应用内功能继续可用。通知入口深链到对应连接和页面，
当前连接失效时先进入登录恢复，不展示其他账号的数据。
[来源：通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)

持续用量刷新不能依赖无限期 `dataSync` 前台服务。target 35+ 在后台运行的该类型
有每日累计时限；持有 overlay 权限也不自动豁免所有启动限制，要求窗口当前可见等条件。
若为用户主动开启的悬浮监控评估 `specialUse`，必须声明真实用途并验证分发审核可接受性；
不借用位置、媒体、通话或 remoteMessaging 类型保活。
[来源：Android 15 行为变化](https://developer.android.com/about/versions/15/behavior-changes-15)、
[FGS 类型](https://developer.android.com/develop/background-work/services/fgs/service-types)

WorkManager 用于后台补同步和清理；周期任务最短 15 分钟，可能被系统电量策略延后。
它不是秒级用量轮询器，也不能保证任务完成瞬间唤醒应用。
[来源：PeriodicWorkRequest](https://developer.android.com/reference/androidx/work/PeriodicWorkRequest)

Live Updates 作为可选增强只考虑用户主动跟踪、时间敏感、有明确开始结束的运行。
持续额度看板不应依赖 Live Update；它不支持任意自定义 RemoteViews，用户和 OEM 也能
限制提升显示。必须保留普通通知回退，不承诺所有机型都出现双百分比系统 chip。
[来源：Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)

后台完成推送需另行验证服务端支持。Cursor iOS 的推送不能直接复用至本客户端。
若后续增加自己的同步/推送后端，作为独立阶段设计账号授权、最少数据与退出撤销；
不能将手机持久连接、FCM 或官方 webhook 尚未支持的路径包装成已具备的推送保证。

## 10. 安全与资源管理

Keystore 用于保护加密密钥，API Key/必要会话副本加密后放应用私有存储。
Keystore 不等于任意字符串保险箱，不能声称它直接接管了 WebView cookie 的全部存储。
硬件支持情况按设备检测；备份、崩溃报告和日志均排除认证与 Secret 数据。
[来源：Android Keystore](https://developer.android.com/privacy-and-security/keystore)

WebView 默认不开启 native bridge；若某个自有内容面板确需消息桥，则限定 origin、
校验消息结构与大小，不暴露通用请求或凭据读取。拒绝明文 HTTP 和 SSL 错误继续访问，
站外导航交给浏览器，不能靠简单字符串后缀判断安全域名。
[桥](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)

所有网络和流任务都持有连接代次与生命周期；退出、页面关闭或连接切换时释放。
大消息、日志、diff、图片和下载设置合理大小上限；超限显示截断/按需加载。
不在通知或 overlay 默认显示提示词、仓库秘密路径或 Secret 值。
锁屏通知的敏感内容按用户偏好隐藏。

## 11. 分阶段交付与验收

### P0：契约与认证原型

交付：脱敏请求/响应 fixture、字段说明、来源等级、权限矩阵、真实设备登录试验记录。
在可用账号下核对 v1 与网页的列表、身份、ID、历史、模型、环境和用量两池。
只做用户授权范围内的试验，不因调研自动创建运行、改 Secret 或启用 Automation。

通过标准：

- 每个首期按钮有已验证的 API/能力路径，未验证项明确关闭或提供网页入口。
- 已确认可用认证方式及会话失效恢复；未能登录的路径有明确阻塞描述。
- 两池字段、缺失、不限量、周期与 stale 的脱敏样本齐全。
- 明确网页已有运行是否可由 v1 访问；无证据时保持来源分离。

### P1：官方通道与原生基本闭环

交付：原生登录连接、收件箱、创建 Agent、Run 会话、追问/取消、结果/产物、缓存、
应用内双池胶囊与详情、网页管理入口。用量依赖 WebSession；不能以 API Key 登录成功
掩盖用量仍不可用。

通过标准：

- 真实运行从提交到结果可追踪；断网重连不重复消息/工具；进程重启可恢复已缓存内容。
- 写入响应丢失不会重复创建；409/401/429/410 有明确行为。
- 多仓库、模型参数与环境选择符合当前服务端限制。
- 两池显示、pace、重置与无限量通过纯函数 fixture；两个渠道身份不混淆。

### P2：网页对齐能力

交付：已核验的置顶/自定义列表、Fork/Side Chat、上下文、diff、运行环境与 Secret、
Automations、Codebase，以及 Desktop/Terminal/Files 的逐项实现。

通过标准：

- 每项功能与网页行为对照；未开通、没有权限和网络失败可以区分。
- Fork/Side Chat 保持服务端上下文语义；Automation 在服务端持续执行。
- diff 更新不误用旧行号；多仓库工作面板不会读写错误仓库。
- Secret 不落日志/草稿/通知；终端输入不因恢复而重复发送。
- 三个工作面板分别列出原生、网页过渡、未完成的实际状态。

### P3：系统展示与后台体验

交付：普通通知、用户开启的跨应用胶囊、停止/权限恢复、WorkManager 补同步，
以及通过可行性验证后的可选 Live Update/推送方案。

通过标准：

- 拒绝/撤销通知和悬浮权限不会崩溃，应用内胶囊可继续使用。
- 旋转、分屏、键盘、大字体、暗色、TalkBack、系统停止服务有明确降级。
- 无可见 UI 时不按秒请求用量；数据过时明确显示，不产生伪实时状态。
- 不依赖无限前台服务，不宣称 FCM/Live Update/厂商后台必然即时可用。

## 12. 版本提议与验证计划

仓库尚无 Android 工程。建议 `minSdk = 26`，`compileSdk = 37`、`targetSdk = 37`，
其中 minSdk 是覆盖面与维护成本的项目提议；target/compile 仍需在建工程时核对依赖兼容。
Android 17 / API 37 已发布，应覆盖其大屏、生命周期、通知与前台服务行为。
[来源：Android 17 发布](https://android-developers.googleblog.com/2026/06/Android-17.html)、
[SDK 配置](https://developer.android.com/about/versions/17/setup-sdk)

最低设备矩阵：API 26、33、35、37；一台 Google 系设备、一台主流国产 ROM，
以及大屏/折叠或多窗口环境。依赖库支持范围、Play 分发与侧载要求在发布阶段单独确认。
本次没有生成安装包，因此不递增版本、不提交 release bump。

以下是工程建立后的拟议命令，**本次全部未运行，当前不能在此空工程仓库执行**：

```sh
./gradlew :app:assembleDebug
./gradlew :app:lintDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest
```

若采用上文建议的独立模块，另加入对应模块的单元测试任务；命令以实际 Gradle 项目名为准，
不能在模块创建前把不存在的任务记为通过。

测试重点：

- 契约：脱敏 JSON、未知枚举、可选字段、分页重复、权限失败、两条来源身份映射。
- 流：断线恢复、无 ID status、同 ID 不同类型、重复增量、结果/done、410、进程重启。
- 写入：并发提交、409、超时结果未知、取消确认、Secret 失败后的清理。
- 用量：纯数字字符串、空值、非有限数、单池缺失、不限量、月末/闰年、重置旧数据、
  ±5 个百分点、周期前 4%、七等分、暂停跨重置、单请求与手动刷新取消。
- 安全：logout 后旧响应失效、账号缓存隔离、header 不跨域、日志脱敏、路径处理。
- Compose：离线首屏、分页、长会话、固定两池槽位、大字体、暗色、TalkBack、旋转。
- 系统：通知/overlay 权限撤销、Doze、后台限制、用户停止服务、Deep Link 身份恢复。

验收报告要分开记录“纯函数/契约通过”“模拟服务通过”“真实账号通过”“真实设备通过”，
参考扩展的已有测试不能算作 Android 已通过测试。
