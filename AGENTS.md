# Agent 约定

本文件只约束编码与提交。不要把产品计划或业务说明写进这里。

## 提交

每个提交必须使用 [Conventional Commits](https://www.conventionalcommits.org/)。

- subject 一行：`type(scope): 摘要`
- subject 之后必须空一行，再写**多行正文**
- 正文必须写明：
  1. **行为**：这次提交改变了什么可观察行为
  2. **兼容边界**：什么必须保持不变
  3. **验证命令**：如何验证（写具体命令，禁止只写「已测试」）
- 禁止只有一行 subject 的提交
- 禁止把正文塞进 subject

示例：

```
feat(inbox): show pinned agents above older threads

收件箱把置顶会话放在其余会话上面，未置顶的顺序不变。
不改变归档、搜索和发起会话的入口。
验证：`./gradlew :app:testDebugUnitTest`
```

`type` 使用 `feat` / `fix` / `docs` / `test` / `refactor` / `chore` / `ci`。`scope` 用模块名。

## 版本

打出供安装或分发的 release 包时，必须先递增版本，禁止沿用上一版的 `versionName` / `versionCode`。

- 改 `app/build.gradle.kts`：`versionName` 递增补丁号，`versionCode` 加 1。
- 单独提交：`chore(app): bump release to <versionName>`。
- 不改变功能行为与 `applicationId`。

## 编码

- 空格缩进，不用 Tab。Kotlin **4 空格**。
- 行宽 100。连续空行最多 1 行。
- 标识符 ASCII；类型名大写驼峰；其余 lowerCamelCase。
- 导入有序，不提交未使用导入。
- 多元素集合保留尾逗号。
- 文档用 KDoc；不要用块注释堆砌。
- 不在表达式里赋值。
- 不扩大任务范围：不顺手重构无关代码。
- 不提交密钥、口令、`local.properties`、备份密文、生成物。
