# Cursor Android 调研与设计

本轮交付接口分析、Android 实现方案及可交互设计稿；尚未建立 Android 工程。
调研于 2026-10-08 开始，2026-10-09 完成；使用 ego 检查 Cursor Agents 及相关设置页面，
并参考 `../../grok-usage-floating` 的 Cursor Usage 实现。

推荐路线是原生 Compose，加官方 v1 Agent/Run 通道和隔离的网页兼容层。
用量只保留 Cursor Model、Other Model；不接入 Grok Bot。
核心前置条件是 Android 登录会话、官方与网页数据可见性及 ID 映射，不能用演示稿代替验证。

## 阅读入口

| 内容 | 文档 |
|---|---|
| 网页接口、设置、流、文件、终端、桌面 | [Web API 分析](cursor-api-inventory.md) |
| 官方 v1、v0 与迁移边界 | [官方 API](cursor-public-api.md) |
| 架构、认证、状态、离线、实施阶段 | [实现方案](android-implementation-plan.md) |
| 两池映射、胶囊、通知、状态和设置 | [UI 规格](design/cursor-android-ui.md) |
| 可点击的手机设计稿 | [交互原型](design/cursor-android-prototype.html) |
| 逐路由证据和类型样本 | [接口目录](api/cursor-web-endpoints.json) |
| Connect、PTY、Tmux 等字段描述 | [协议目录](api/cursor-web-services.json) |

## 结论

- 官方 v1 Public Beta 已有 Agent/Run、SSE、产物、环境和 Secret；官方核查列出
  33 个 v1 operation、12 个官方 v0 Worker/Pool operation、12 个 legacy operation。
- 网页接口包含 POST JSON、Connect 流、二进制 blob、VM WebSocket 与 VNC。
  428 个公开 JS chunks 还含共用后台代码，静态候选不能当作已验证的服务端全集。
  目录收录 857 个路径候选，实际观察到 123 个路径，其中 120 个取得响应。
- 个人双池直接读取 `usage-summary` 的 `autoPercentUsed` 与 `apiPercentUsed`，
  不从金额、token 或当前选中模型推算。缺数据与 0% 是不同状态。
- 系统状态栏只用单色通知小图标；双池值在通知抽屉，完整胶囊在 App 内或授权浮窗。
  Android 后台刷新受系统限制，不承诺无限前台服务或秒级后台更新。

## 本次验证与证据边界

网页观察包括 Agents 首页、已有会话的 Changes/Desktop/Files、个人设置、Cloud Agent
偏好、环境详情、Plugins/MCP、Integrations、API/SSH Keys、Automations、Codebase、
Usage、Spending 和 Billing。只把请求字段及响应类型写入目录，未保存 cookie、
API key、Secret 值、个人会话内容或 VM 凭据。

新自动化编辑页会自动创建未启用草稿，本次产生的空草稿已删除，列表已恢复为空。
没有发送 Agent 提示词、执行终端命令、接管桌面或保存文件。
尚未验证的写请求、团队权限、隐藏入口和 Android 登录都在各文档中明确区分。

原型已经通过 ego 检查：四个场景、页面切换、剩余／已用数值一致、两池全关、
通知图标隐藏、展开面板与 Escape 关闭，以及 320 px 宽度无横向溢出。
它不请求业务 API，不保存账号配置；HTML 里的仓库、百分比和日期为演示数据。
JavaScript 语法与文档本地链接也已检查。

本轮没有 APK、Gradle 工程或真机运行结果。未来 Android 验收命令见实现方案；
本轮不递增 release 版本，不把参考扩展的测试结果当作 Android 测试结果。

## 本地预览

可直接打开设计稿，或在仓库根目录运行：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design
```

浏览器打开 [本地预览](http://127.0.0.1:8765/cursor-android-prototype.html)。
