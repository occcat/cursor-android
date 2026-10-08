# Android 胶囊与状态栏设计

设计日期：2026-10-08。只有 **Cursor Model** 和 **Other Model** 两个用量池。
胶囊、详情、浮窗和通知共用一份快照；不接入 Grok Bot，不添加第三池。

[交互原型](cursor-android-prototype.html)使用虚构数据，可切换正常、额度紧张、离线、
登录过期场景。它是可审阅的设计，并非已实现的 Android App。
整体架构见[实现方案](../android-implementation-plan.md)。

## 信息层级

手机主导航建议为会话、自动化、Codebase；用量通过顶部胶囊进入，设置位于用户菜单。
原型中的“会话／用量／设置／通知”是设计检查入口，不是最终四个产品底部导航项。

- 会话：先显示缓存列表，提供搜索、置顶、归档、自定义列表和新建。
- 新建：仓库和环境在提示词上方；上下文、模型参数、多模型和发送在输入区。
- 会话详情：运行状态、对话、追问；Changes、Environment、Desktop、Terminal、Files
  放在工具面板。小屏全屏打开面板，大屏可并排；保留 Fork、Side Chat 和产物入口。
- 用量：点击胶囊打开 BottomSheet；两行额度下方显示周期、数据时间和刷新动作。
- 账号、账单、源码托管绑定：保留已登录网页入口，遵守仓库 README 的产品边界。

配额分类来自服务端两个额度池，不能按当前聊天所选模型名分类。
“不接入 Grok Bot”不意味着删掉 Cursor 可用模型目录中名称含 Grok 的模型。

## 与参考项目的对应

参考目录是 `../grok-usage-floating`，只迁移 Cursor 用量部分。

| 来源 | 保留的设计 |
|---|---|
| `sites/cursor/site.css:30` | Cursor 霜蓝；Other 中性灰 |
| `sites/cursor/site.css:42` | 展开条高 8 px、圆端 |
| `packages/core/src/content.css:600` | 双行 mini bars，条宽 60、高 6 |
| `packages/core/src/mini.ts:130` | 双环模式：外 Cursor，内 Other |
| `packages/core/src/hud.ts:350` | 拖动、吸边、展开后保持位置 |
| `packages/core/src/pace.ts:105` | 计费周期日末目标、节奏偏差 |
| `packages/core/src/reset-watch.ts:77` | 到期后更新，避免旧周期重复请求 |

Android 使用 dp/sp，不机械复制网页 CSS 尺寸。原三池截图不作为 Android 设计稿。
参考项目默认显示已用；本方案默认显示剩余，并提供全局口径切换。

## 视觉规格

| 项目 | Light | Dark |
|---|---|---|
| 基础面 | `#fcfcfc` | `#181818` |
| 主文本 | `#141414` | `#f0f0f0` |
| 次文本 | `#717171` | `#9a9a9a` |
| 分隔线 | `#e9e9e9` | `#292929` |
| Cursor | `#81a1c1` | `#81a1c1` |
| Other | 主文本与底色混合 60% | 主文本与底色混合 60% |
| 警示文本 | `#a46700` | `#f1b467` |
| 错误文本 | `#be1744` | `#e34671` |

两池身份颜色保持固定。用得快、离线、额度耗尽用图标和文字说明，
不要把两根进度条同时变红，导致用户无法区分模型池。
小字不直接用霜蓝作正文；保证文本与背景对比度。百分比使用等宽数字。

### 紧凑胶囊

默认横向双值：`Cursor 68% · Other 39%`，语义为剩余。
视觉约 156 × 40 dp，整体触摸区域至少 48 dp 高；标签有对应色点。
顶部应用栏允许把“剩余”作为可见辅助标签，TalkBack 必须读完整口径。
大字体时自动加高或换成双行，不压缩到难读字号。

可选双行 mini bars：176 × 48 dp，条约 60 × 6 dp，标签为 Cursor / Other。
可选双环：外环 Cursor、内环 Other；中心数值不能被误认为两池总额度。
第一版只需默认胶囊和双行详情；双环作为后续样式，避免设置过多。

点击展开用量；长按显示位置、暂停刷新、隐藏；拖动不触发展开。
跨应用胶囊默认右侧中下部，距可用屏幕边缘 16 dp；横竖屏保存归一化坐标。
拖动门槛使用 Android touch slop，避让挖孔、导航手势和键盘。

### 展开的用量面板

BottomSheet 宽度随屏幕适配，内容边距 16 dp，平板可限制到 400 dp。
标题 Cursor Usage；已知时显示套餐；右侧刷新和关闭。

每池固定位置显示：

1. 完整标签 Cursor Model / Other Model。
2. 主值“剩余 68%”，次值“已用 32.0%”。
3. 8 dp 圆角进度条和目标刻度。
4. “用得较快／节奏正常／用得较慢”，附文本而不只变色。

底部显示共同计费周期、确切重置时间、本地时区、剩余天数、上次成功更新、暂停状态。
不可用时保留池位，显示 `—`；不能把缺失当 0%。
“额度用尽”仅表示该池已耗尽，不宣称所有请求必然停止；网页 Spending 明确存在
转用 Other 额度或按量计费的情况，实际执行由账户策略决定。

## 唯一数据口径

数据来自 `GET https://cursor.com/api/usage-summary` 的网页登录会话。
该 GET 已在 ego 中观察到 200；完整接口证据见[接口分析](../cursor-api-inventory.md)。

| UI 字段 | JSON 来源 |
|---|---|
| Cursor 已用 | `individualUsage.plan.autoPercentUsed` |
| Other 已用 | `individualUsage.plan.apiPercentUsed` |
| 周期起点 | `billingCycleStart` |
| 周期终点 | `billingCycleEnd` |
| 不限量 | `isUnlimited === true` |
| 套餐 | `membershipType` |

计算：`displayUsed = clamp(rawUsed, 0, 100)`；`remaining = 100 - displayUsed`。
保留 raw 值，以便超过 100 时解释超额；进度绘制仍限制到 0–100。
只有有限数字和合法纯数字字符串可接受；空值、布尔、非法数字为 unknown。
不使用 `plan.used / plan.limit` 推算两个池，不把美元或 token 数当百分比。

示例：Cursor 已用 32、Other 已用 61，则所有表面默认显示剩余 68、39。
切换为已用后，胶囊、通知、详情主值和条长一起切成 32、61。
不能只改文字，留下方向相反的进度条。

套餐缺失时隐藏 badge；不为获取套餐发起 Bot 请求。
`isUnlimited` 为 true 时显示 `∞`，不用百分比、倒计时或 pace。
团队账户缺少 individualUsage 时保留“本账户未提供个人双池额度”，不拼造团队额度。

## 节奏算法

算法按 UTC 时间戳计算，日期展示用本地时区。设 `day = 86400000`：

```text
span = cycleEnd - cycleStart
elapsed = clamp((now - cycleStart) / span, 0, 1)
targetUsed = min(1, (floor((now - cycleStart) / day) + 1) * day / span) * 100
delta = usedPercent - targetUsed
```

`delta > 5` 为用得较快，`delta < -5` 为用得较慢，否则节奏正常。
刻度代表当前账单周期日结束的目标，不是本地午夜，也不是硬性用量上限。
剩余口径时刻度位置为 `100 - targetUsed`；已用口径时为 `targetUsed`。

优先用服务端起止；参考实现接受 1–32 天周期，否则由结束时间倒推一个日历月，
月底日期作截断。Android 若保留这个 fallback，要标“估算周期”；没有结束时间就不画刻度。
时间早于起点或周期异常时不生成误导性的节奏判断。

到期但未拿到新周期数据时标“待同步”，保留旧值与时间，不能自动归零。
按参考实现可在周期到期后 5 秒进行一次刷新；后台触发仍受系统调度约束。
同一过期 end 只触发一次，重新获得新 end 才重置计划。

进阶可提供“周期七格”，其含义为整个月周期七等分，不能标成“最近七天”。
参考 graded 色阶衡量额度可能用不完，不等于超支风险；第一版保留文字节奏即可。

## 状态矩阵

| 状态 | 胶囊 | 面板与通知 |
|---|---|---|
| 首次加载 | `···` | 骨架；不显示 0% |
| 正常 | 两池剩余值 | 周期与更新时刻 |
| 额度紧张 | 值及警示点 | 哪个池、剩余值、节奏原因 |
| 单池缺失 | 对应 `—` | 另一池继续显示 |
| 无个人配额 | 两池 `—` | “暂无个人额度数据” |
| 不限量 | `∞` | 不画 pace 和重置倒计时 |
| 离线或请求失败 | 旧值及离线标志 | “上次成功更新 …”；有手动重试 |
| 周期过期 | 旧值及待同步标志 | 不伪造新周期 |
| 暂停 | 暂停标志 | 停止计时刷新，仍可手动刷新 |
| 登录过期 | “重新登录” | 隐藏私密数值、停止重试风暴 |

错误顺序：登录失效、缺数据、过期、离线、正常。
401 跳重新登录；403 先识别会话失效、权限不足或组织限制，不能统一退出账号。
提醒等级独立于参考扩展 worstPool 排序：耗尽高于低余额，低余额高于节奏偏差。
建议阈值剩余 20% / 10%，默认只在跨阈值时提醒；每个池每周期去重。
这是产品设置值，不是 Cursor 官方限额规则。

## 系统状态栏与通知

普通 Android 应用的系统状态栏只显示单色通知小图标。
不把两条彩色额度、任意文本或自定义胶囊画进系统状态栏。
API 33+ 普通通知需要用户授予 `POST_NOTIFICATIONS`。

通知抽屉折叠示例：

```text
Cursor Usage · 剩余额度
Cursor 68% · Other 39%
8 天后重置 · 更新于 14:32
```

展开显示完整池名和两行值，可选两条进度；操作为“刷新”“查看用量”“暂停”。
以标准通知模板为基础，可用 BigTextStyle 降级；自定义 RemoteViews 的空间由系统决定，
必须在不同 API 和 ROM 检查截断，不能强制通知高度。锁屏默认隐藏具体用量和仓库名。

常规用量通知低重要性、不响铃；运行完成、需输入和失败单独 channel，避免额度刷新刷屏。
关闭普通通知权限不影响应用内胶囊；系统也可能不显示通知小图标，UI 不作保证。

跨应用浮窗采用 `TYPE_APPLICATION_OVERLAY`，需 `SYSTEM_ALERT_WINDOW`，
位于状态栏与输入法之下。用户从可见 Activity 主动开启，提供明确的停止入口。
第一版可以暂不开放长时悬浮，先交付应用内胶囊及常规通知。

不能用无限 `dataSync` 前台服务保活：target 35+ 在后台每 24 小时累计仅 6 小时。
如做长时悬浮，另行验证适用的 FGS 类型、`specialUse` 声明与分发审核；不能虚报用途。
系统停止、权限撤销或进程被杀后，降级缓存及 WorkManager，不反复强行拉起。

Live Update chip 只作为用户正在关注的 Agent 运行状态的可选增强，
不可承诺常驻额度看板符合提升条件；系统控制展示，始终有普通通知回退。

平台依据：

- [悬浮层级](https://developer.android.com/reference/android/view/WindowManager.LayoutParams)
- [通知权限](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [Live Updates](https://developer.android.com/develop/ui/views/notifications/live-update)
- [Android 15 限制](https://developer.android.com/about/versions/15/behavior-changes-15)
- [FGS 类型](https://developer.android.com/develop/background-work/services/fgs/service-types)

## 本机设置和网页设置

本机设置用 DataStore，不提交到 Cursor：

- 显示 Cursor Model、Other Model；两者全关时隐藏胶囊，不留下空壳。
- 剩余／已用，默认剩余；所有表面同步切换。
- 节奏线、紧凑样式、位置、明暗跟随系统、语言与大字体适配。
- 前台刷新 30 / 60 / 120 / 300 秒，默认 60 秒；暂停与手动刷新。
- 通知、低余额提醒、锁屏隐私、可选跨应用浮窗及授权状态。

参考扩展允许最低 3 秒；Android 不照搬。前台才按秒定时、请求合并，
页面隐藏取消普通轮询，返回立即检查新鲜度。后台 WorkManager 最低周期 15 分钟，
不是准点保证；通知必须显示最后更新时间，不宣称实时。

Cloud Agent 设置与本机外观分组：默认模型／仓库／分支前缀、PR 行为、
环境继承和这次运行的 Secret 根据真实 API 能力提供原生编辑。
隐私模式、账户资料、活跃会话、付费及 SCM 绑定提供网页入口。
未确认的写入协议显示网页入口，不能做保存成功的假开关。

## 设计验收

实现时验证 320 dp、大字体 200%、明暗模式、横竖屏、折叠屏、TalkBack、减弱动画。
胶囊点击、拖动、展开、返回键关闭、键盘焦点、权限拒绝与撤销均有明确结果。
保留两个槽位，错误状态不跳位；零剩余、无限量、单池缺失、过期均有用例。
原型只验证信息布局和交互，不代表 Overlay、通知或后台服务已通过真机测试。
