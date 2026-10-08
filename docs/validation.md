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

Production site content still requires a successful deployment of the implementation.
The initial build against the original repository main cannot build files that have
not merged yet. Domain/SSL activation is not a successful site-content check.

## Implementation validation

| Area | State |
| --- | --- |
| Documentation links/evidence/HTML/SVG | `python3 docs/scripts/check-docs.py` passed: 82 local links, immutable counts, JSON/SVG, duplicate IDs, JS syntax |
| Android initial suite | Worker passed 20 unit tests, lintDebug, and assembleDebug; reviewer fixes/regression checks are still in progress, so this is not final integration approval |
| Android instrumentation/device tests | Pending available device/emulator |
| Live account API-key and web sign-in | Not established by the research audit |
| Website build/tests | Worker: `node --test website/test/*.test.mjs` passed 10 cases; `node website/scripts/build.mjs` passed; website Reviewer approved a3ed683 |
| Website ego preview | Coordinator passed desktop/320 px EN/CN, persistence, metric/scenario/pool toggles, keyboard tabs, privacy-dialog Escape/focus, reduced motion at localhost:4173 |
| English documentation prototype ego check | Coordinator passed default English, EN/CN at 320 px without overflow, 68/39 remaining ↔ 32/61 used, correct pace, Escape/focus return, hidden pools/icon, notification off, and signed-out privacy |
| Integrated tests after merges/rebase | Pending Merger/Operator |
| Production website/release refresh | Pending deployment after merge |

The documentation prototype was checked at localhost:8766; the website preview at
localhost:4173. These are browser preview results, not Android device results or
production-domain content checks. All displayed quotas are fictional.

Do not promote pending checks to passed based on source inspection, a mock, an accepted
build request, or a test from the reference browser extension. Update this record with
exact commands/results as each implementation line finishes.
