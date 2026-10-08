<div align="center">

# Cursor Android

**随时跟进，从容掌握。**

Cursor Cloud Agents 的原生 Android 伴侣，让两个用量池一目了然。

[English](README.md) · 简体中文

[官网](https://cursor-android.app) ·
[版本发布](https://github.com/occcat/cursor-android/releases) ·
[文档](docs/README.md) ·
[反馈问题](https://github.com/occcat/cursor-android/issues)

</div>

![胶囊、用量详情与通知设计](docs/assets/cursor-android-ui.svg)

*示意图使用虚构数据。本项目是独立社区项目，不是 Cursor 官方应用，也不代表官方关联。*

## 在手机上跟进工作

原生 Android 客户端通过官方 v1 API 发起、查看和跟进 Agent 运行，通过独立网页登录
读取账户用量。胶囊仅保留 **Cursor Model** 与 **Other Model** 两个额度池，默认显示剩余。
应用、官网及文档默认英语，可选中文。

- 原生收件箱、搜索、归档恢复、新建、运行更新、追问、取消与产物。
- 两池用量在应用内胶囊、详情和通知中保持相同数据口径。
- Kotlin、Compose、Navigation 3、ViewModel、Room、DataStore、Hilt 与 WorkManager。
- Desktop、Terminal、Files、Automations、Codebase 通过 Cursor 网页入口打开，
  不把网页跳转称作原生协议实现。

项目处于首轮实现阶段。已完成检查与真实账户、设备验证的边界见
[验证记录](docs/validation.md)。源码公开，但仓库尚未声明可再分发的软件许可证。
当前能力和准确构建信息以 [English README](README.md) 为准；
[中文调研存档](docs/zh-CN/README.md)保留原始设计，不作为当前完成状态。

## 开始使用

在[发布页面](https://github.com/occcat/cursor-android/releases)查找实际存在的
`cursor-android-<version>.apk`。只有发布并签名的版本才可作为发行包；没有 APK 时从源码
构建。没有宣称 Play Store 上架。

在应用中连接用户 API key 使用原生 Agent 功能。账户用量需要应用内独立的 Cursor
网页登录；API key 不能代替网页登录会话。已有网页会话的可见性和 SSO 受 Cursor 支持范围约束。

准备 JDK 17 或以上、Android SDK 36。应用最低支持 Android 8.0 / API 26，
当前 compile/target SDK 36：

```sh
git clone https://github.com/occcat/cursor-android.git
cd cursor-android
./gradlew :app:assembleDebug
```

调试包位于 `app/build/outputs/apk/debug/app-debug.apk`。也可用 Android Studio 运行。
`local.properties`、密钥、签名文件和生成物不得提交。

## 胶囊与状态栏

当 Cursor 已用 32%、Other 已用 61% 时，所有界面默认显示剩余 68%、39%。
切换为已用时，数字、标签、进度条和节奏刻度同时切换。缺少数据为 `—`，不限量为 `∞`；
刷新失败保留旧快照和更新时间，不能把旧周期自动归零。

Android 系统状态栏使用单色通知小图标，两个数值放在通知抽屉。
跨应用胶囊需要单独授权，位于系统栏和键盘之下；后台刷新由系统调度，不承诺常驻实时。

[交互原型](docs/design/cursor-android-prototype.html)默认英语，可切换中文：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design
```

打开[本地预览](http://127.0.0.1:8765/cursor-android-prototype.html)。原型不请求业务接口，
不读取或保存凭据。完整设计见 [UI 规格](docs/design/cursor-android-ui.md)。

## 接口、测试与发布

ego 调研读取了 428 个公开 JS chunks，收录 857 个路由候选，实际观察 123 个不同路径，
其中 120 个获得响应；另核查 57 个官方公开操作。候选不等于全部可用服务端接口。
接口证据、设置与协议边界见[文档索引](docs/README.md)。

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
node --test website/test/*.test.mjs
node website/scripts/build.mjs
python3 docs/scripts/check-docs.py
```

有设备或模拟器时运行 `./gradlew :app:connectedDebugAndroidTest`。
[测试方案](docs/testing.md)区分契约测试、浏览器检查、真实账户和设备验证。

Cloudflare Pages 构建 main，通过 `cursor-android.app` 提供网站。
发布事件触发重新构建以更新版本信息；配置见[部署指南](docs/deployment.md)。
提交规范与独立版本递增要求见 [CONTRIBUTING](CONTRIBUTING.md) 和 [AGENTS.md](AGENTS.md)。
