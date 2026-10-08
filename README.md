# cursor-android

原生 Android 客户端，对齐 [cursor.com/agents](https://cursor.com/agents)。用来发起、跟进和审阅 Cloud Agent。它不是桌面 IDE，也不是账号与账单后台。

官方原生应用目前是 [Cursor for iOS](https://cursor.com/docs/cloud-agent/mobile)。文档写明 Android 仍在计划中，现在手机上打开的是同一网址或它的 PWA。本仓库做那一层原生客户端，会话与网页、桌面 Agents Window 共用后端。

## 网页上要有的能力

会话列表：

- New Chat、搜索、置顶、归档、自定义列表
- Automations
- Codebase（Early Beta）

发起一次运行：

- 仓库可以选一个、多个，也可以 Start from scratch
- 可以添加仓库、刷新列表、添加环境
- 提示词
- 上下文：Files、Skills、MCP Servers
- 模型选择，包括 Use Multiple Models
- 语音输入
- 快捷入口：Run security audit、Create an Automation

一次运行里面：

- 实时对话、追问、Fork Chat、Side Chat
- 环境状态
- Environment（Secret、Inherit user settings）、Changes（diff 与文件树）、Desktop、Terminal、Files
- diff 统计、Review，以及打开对应 PR
- 截图、录像、日志这类产物

Automations：

- 新建
- Mine、Explore、From Cursor
- 现成模板：用 Bugbot 审代码并自动修、每次改动做安全扫描与分诊、分配评审人并自动批准
- All Runs

账号、账单和源码托管的绑定留在网页或 Dashboard。密钥与环境的配置源也在网页；应用里要能查看当前运行用的环境，并按网页已有入口管理这次运行的 Secret。

## 官方移动端另外有的能力

这些在 [Cursor for iOS](https://cursor.com/docs/cloud-agent/mobile) 里，网页首页没有单独做成一级入口：

- Remote Control：从手机继续指挥电脑上的 agent，终端、改文件和测试仍在那台电脑上跑
- 运行结束时的推送通知
- 子代理卡片，点进去看子对话
- Design Mode：附上照片、相机或文件，在图上点选和涂画
- 斜杠命令、skills、automations 与本地、CLI、网页一致
- 每次运行可选 Cloud machine、Team Pool 或 My Machines
- 先读本地缓存，再在有网时同步，收件箱和对话离线也能打开

iOS 把完整编辑器、终端和文件浏览器留在网页，手机上只看 diff。cursor.com/agents 本身有 Desktop、Terminal 和 Files。本客户端以网页为准，这三个面板在范围内。
