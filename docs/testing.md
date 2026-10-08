# Test plan

This is the acceptance plan. [Validation](validation.md) records actual execution;
a planned check, mock response, browser preview, or source inspection is never a
substitute for a real account or device result.

## Fast automated gates

Run from the repository root with the documented JDK and Android SDK installed:

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
node --test website/test/*.test.mjs
node website/scripts/build.mjs
python3 docs/scripts/check-docs.py
```

Device instrumentation, when a supported emulator/device is connected:

```sh
./gradlew :app:connectedDebugAndroidTest
```

Exact task availability is defined by the implemented build. Test reports must retain
the executed command, code revision, environment, exit status, and skipped checks.

## Contract and logic matrix

| Area | Cases | Expected result |
| --- | --- | --- |
| DTO parsing | Missing optional fields, unknown enums, string int64, extra keys | Preserve meaning without crashes or precision loss |
| Agent/run identity | Same ID across accounts, multiple runs, team switch | No accidental record merge or stale callback write |
| Pagination | Repeated IDs/cursor, short page with nextCursor, omitted cursor | Deduplicate; stop loops; continue by cursor |
| Writes | Double-tap, timeout after server acceptance, busy 409 | Single submission; uncertain delivery is explicit |
| SSE | ID-free status, same ID result/done, duplicate frame, reconnect, 410 | Apply distinct events once; snapshot fallback |
| Secrets | Write-only values, ambiguous names, failed write, scope switch | No old value disclosure or wrong-scope update |
| Usage parsing | Number/numeric string, null/blank/boolean, nonfinite, >100 | Finite validation, unknown distinct from zero, clamped geometry |
| Usage mapping | autoPercentUsed=32, apiPercentUsed=61 | Cursor/Other remaining 68/39; used 32/61 everywhere |
| Usage states | Partial, absent individual data, unlimited, expired session | Fixed pool slots; no invented percentages; privacy preserved |
| Cycle/pace | Month-end/leap year, invalid/missing start/end, ±5 points | Billing-day-end marker, explicit estimate or no pace |
| Reset | Old snapshot after end, repeat end, pause across end | Retain stale values, no local reset or refresh loop |
| Preferences | Both hidden, metric/language switch, restart | Consistent surfaces; persisted settings |
| HTTP/auth | 401 vs403,429,redirect, logout during request | Stop expired auth, respect retry, no credential leakage |

A code-logic regression must add a test that fails before its fix. Do not add tests
that merely duplicate formatting or implementation details without useful behavior coverage.

## Android manual/device matrix

Minimum representative levels: API 26, 33, 35, and the actual compile/target level;
one Google device/emulator and one vendor ROM, plus a large screen or multi-window.
Record unavailable rows explicitly rather than marking them passed.

- First launch is English; selecting Chinese works; restart preserves the choice.
- API-key connect/disconnect; correct identity; wrong/expired key; no key in logs/backups.
- Separate web sign-in; SSO/challenge behavior; expiry/reconnect; no implied browser cookie sharing.
- Inbox cached first paint, search, pagination, archive/restore, offline retry.
- Create a deliberately authorized small run, stream it, follow up, cancel if appropriate;
  confirm no duplicate prompt after rotation/network interruption.
- Environment/Secret operations use a disposable test resource and clean it up;
  do not expose or overwrite production values for a test.
- Usage matches the same account's web response, including stale/partial/unlimited states.
- Notification permission grant/deny/revoke; lock-screen privacy; channel settings.
- Overlay grant/deny/revoke, stop action, rotation, keyboard, cutout, process stop;
  no obstruction of system controls or misleading foreground-service promise.
- TalkBack, 200% text, dark/light theme, landscape and split-screen, 48 dp targets.
- Background/Doze and offline behavior show truthful timestamps; work remains inexact.
- Web-only work panels open the intended HTTPS page and are identified as web features.

## Browser and website matrix

Use ego for actual browser QA; keep browser task ownership with the coordinator.

| Surface | Check |
| --- | --- |
| Desktop / mobile | 320, 390, 768, 1440 px; no horizontal overflow or clipped controls |
| Language | English default, optional Chinese, persistence, document lang and accessible labels |
| Demo | Two pools only; metric switch, scenario changes, stale/auth states; no real credentials |
| Navigation | Menu, anchors, docs/source/release links, keyboard focus and Escape |
| Accessibility | Headings, labels, contrast, reduced motion, focus visibility |
| Release metadata | No release, valid signed APK, absent APK, API failure; never invent a download |
| Security | No deploy hook/key in browser bundle; external links and CSP/headers where supplied |
| Production | HTTPS at cursor-android.app; correct content and release link after Pages build |

## Documentation and evidence

Check local links, JSON parsing/counts, SVG validity, English canonical docs, and
prototype syntax. Screenshots/illustrations must identify fictional demo data.
API evidence labels survive translation; 857 candidates must never become “857 verified APIs”.
Archived Chinese research remains dated, while current READMEs match the implementation.

## Release and integration gate

Each implementation branch commits reviewed milestones. Reviewers focus on P0/P1.
The Merger uses --no-ff and runs the full applicable automated suite after integration.
The Operator rebases with --rebase-merges onto current main, repeats tests after a
real rebase, creates one PR, inspects cloud review/checks, and waits for the required
quiet interval before merge. The Cleaner verifies the merge and removes only merged
branches/worktrees. Preserve actual evidence and limitations in the PR and report.

A release additionally requires the separate version bump, valid signing, an installable
artifact, and Pages refresh. A configured deploy hook or accepted deployment request
alone does not establish that new content is live.
