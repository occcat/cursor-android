# Agent Guidelines

This file governs coding and commits only. Do not add product plans or business descriptions here.

## Commits

Every commit must follow [Conventional Commits](https://www.conventionalcommits.org/).

- Use a single-line subject: `type(scope): summary`.
- Follow the subject with a blank line and a **multiline body**.
- The body must explain:
  1. **Behavior**: the observable behavior changed by this commit.
  2. **Compatibility boundary**: what must remain unchanged.
  3. **Validation commands**: how to verify the change, using specific commands rather than just
     saying "tested".
- Do not create commits containing only a subject line.
- Do not put the body in the subject.

Example:

```
feat(inbox): show pinned agents above older threads

The inbox places pinned conversations above the rest, preserving the order of unpinned ones.
The entry points for archiving, searching, and starting conversations remain unchanged.
Validation: `./gradlew :app:testDebugUnitTest`
```

Use `feat` / `fix` / `docs` / `test` / `refactor` / `chore` / `ci` for `type`.
Use the module name for `scope`.

## Versions

Before building a release package for installation or distribution, increment the version.
Do not reuse the previous release's `versionName` or `versionCode`.

- In `app/build.gradle.kts`, increment the patch component of `versionName` and add 1 to
  `versionCode`.
- Use a separate commit: `chore(app): bump release to <versionName>`.
- Keep feature behavior and `applicationId` unchanged.

## Coding

- Indent with spaces, not tabs. Use **4 spaces** for Kotlin.
- Limit lines to 100 characters. Use no more than one consecutive blank line.
- Use ASCII identifiers, UpperCamelCase for type names, and lowerCamelCase for other identifiers.
- Keep imports sorted. Do not commit unused imports.
- Keep trailing commas in collections with multiple elements.
- Use KDoc for documentation; do not pile up block comments.
- Do not assign values within expressions.
- Stay within the task's scope: do not refactor unrelated code along the way.
- Do not commit keys, passwords, `local.properties`, encrypted backups, or generated artifacts.
