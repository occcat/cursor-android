# Validation record

Implementation launch, October 9, 2026. This record distinguishes research evidence,
automated checks, browser checks, and checks requiring a real Android device/account.
The final integration commit and PR carry the complete execution record.

## Completed research

| Check | Result / boundary |
| --- | --- |
| ego web/API observation | 123 distinct paths, 120 responses; 428 public chunks; no completeness claim |
| Official API review | 33 v1 + 12 official worker/pool + 12 legacy operations; no live API-key writes |
| Original design prototype | Previous Chinese prototype checked in ego for scenarios, metric consistency, hidden pools, Escape, and 320 px overflow |
| Evidence sanitization | Durable catalogs contain paths/types and provenance, not credentials or account values |
| Automation editor side effect | Its disabled empty draft was deleted; empty list verified |

## Infrastructure configuration

Cloudflare Pages project `cursor-android` is connected to GitHub main with build
`node website/scripts/build.mjs`, output `website/dist`, and Node 22. The apex domain
is attached; Cloudflare reports **Active** with **SSL enabled**. The `github-release`
deploy hook targets main, and its URL is stored in the GitHub Actions secret
`CLOUDFLARE_PAGES_DEPLOY_HOOK`. The coordinator verified this configuration through ego.
The infrastructure Operator also configured all four Android signing secrets:
ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and
ANDROID_KEY_PASSWORD. A durable signing key is stored outside the repository.
Configuration alone is not a successful release build or installed-artifact test.

Production site content and release refresh require verification after this
implementation reaches main. Domain/SSL activation is not a successful site-content check.

## Implementation validation

| Area | State |
| --- | --- |
| Documentation links/evidence/HTML/SVG | `python3 docs/scripts/check-docs.py` passed: 100 local references including native screenshot sources, immutable counts, JSON/SVG, duplicate IDs, JS syntax |
| Android reviewed native/widget suite | Widget milestone `d310966`: 37 unit tests passed, debug lint reported zero errors/fatal findings, and the debug build passed; Reviewer independently verified the reports |
| Android instrumentation | 11/11 instrumentation tests passed on the API 36 emulator, with zero failures/errors/skips; this includes the native suite and six widget tests |
| Native screenshot review | Actual API 36 / 320 dp captures from the device job's `device-screens` artifact (see Cursor visual refresh below); overlay uses synthetic 68/39 fixtures; no credentials or paid run |
| Live account API-key and web sign-in | Not run; network behavior uses MockWebServer fixtures, with no paid Agent runs |
| Website build/tests | Widget showcase `f18299a`: 19 Node tests, syntax, offline build, and diff checks passed; Reviewer approved with no P0/P1 findings |
| Website ego preview | Coordinator passed desktop/320 px EN/CN, persistence, metrics/scenarios/pool toggles, keyboard/focus, reduced motion, three widget families/sizes, title privacy, unlimited/stale states, and action destinations |
| English documentation prototype ego check | Coordinator passed default English, EN/CN at 320 px without overflow, 68/39 remaining ↔ 32/61 used, correct pace, Escape/focus return, hidden pools/icon, notification off, and signed-out privacy |
| Native widgets | Real RemoteViews host checks cover responsive sizes, 1.3× text, English/Chinese, full visible bounds, and real PendingIntent cold/warm navigation to four app screens and two distinct Agent details; five approved synthetic-fixture captures are linked in the widget guide |
| Signed-release launcher checks | All three providers and Settings pin buttons are registered; actual Pixel Launcher Usage pinning renders signed-out state, opens native Usage, and refreshes without runtime errors |
| Final combined integration/rebase | Pending final Merger/Operator execution; complete results will be recorded in the PR |
| Signed distribution validation | Version 0.1.2/code 3 was committed separately at `39fe867`; signed R8 build, release lint, certificate verification, and in-place upgrade from 0.1.1 passed; firstInstallTime and the paused-sync preference were preserved |
| Production website/release refresh | Pending deployment after merge |

Android commands reported for the reviewed native suite:

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
./gradlew :app:lintRelease :app:assembleRelease
./gradlew :app:connectedDebugAndroidTest
```

The documentation prototype was checked at localhost:8766; the website preview at
localhost:4173. These are browser preview results, not Android device results or
production-domain content checks. All displayed quotas are fictional.

Android network contracts use MockWebServer fixtures. These checks do not establish
live API-key authentication, web SSO, paid mutations, API 26 compatibility in practice,
or behavior on vendor launchers. API 36 emulator coverage and synthetic widget host
screenshots must not be described as the full device/account acceptance matrix.
The tested Pixel Launcher labels compact Usage 2×2 to satisfy its minimum geometry;
grid labels are hints, while the documented dp breakpoints define actual layouts.

## Cursor visual refresh

The warm light/dark redesign of the app, widgets, overlay, notification, website, and design
documents was checked with these commands. Results are for the redesign branch.

| Check | Result |
| --- | --- |
| `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` | 42 unit tests passed, including `CursorThemeTest` contrast and resource checks; lint 0 errors, 45 pre-existing warnings |
| `./gradlew :app:lintRelease :app:assembleRelease` | Unsigned R8 build passed; lint 0 errors, 45 pre-existing warnings |
| `node --test website/test/*.test.mjs`, `node --check website/src/app.mjs`, `node website/scripts/build.mjs --offline` | 19 tests, syntax check, and offline build passed |
| Website headless Chrome review | No horizontal overflow at 320, 390, 768, and 1440 px in light and dark; theme color follows the scheme; reduced motion removes transitions |
| Android checks run 37872252009 | Verify job passed; device job passed 11/11 tests on the default 320 × 640 mdpi display, then 8/8 native and widget tests in light and again in dark |
| Native capture review | 1080 × 1920 px at 540 dpi (WindowManager caps forced sizes at three times the 640 px skin); README uses the dark run, the widget guide the light run |

Capture notes. In the light run, SystemUI drew an oversized status icon over the clock and
light navigation buttons on the light scrim, including over the launcher; the app had
requested light bars and the dark run, after a real configuration change, was unaffected,
so these are emulator artifacts after the runtime density change. The usage sheet opened
and was asserted in the signed-out capture, but was not yet on screen when it was taken;
the README image therefore shows the inbox capsule's unknown values. Not run: 200% text,
TalkBack, landscape/split-screen, physical devices, and live accounts.

Do not promote pending checks to passed based on source inspection, a mock, an accepted
build request, or a test from the reference browser extension. Update this record with
exact commands/results for later changes; final integration and production evidence
for this launch are recorded in the associated PR.
