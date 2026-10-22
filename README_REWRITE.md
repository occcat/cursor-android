# Flutter rewrite (1.x)

## Status

The app is being rewritten in Flutter, working toward 1.0.0. The rewrite lives at the repository
root in `pubspec.yaml`, `lib/` and `test/`.

The Kotlin 0.1.5 app is still in `app/` and is the release that ships today. See
[README.md](README.md) for its features and its build and install instructions. Archiving the
Kotlin tree is deferred until the Flutter app can replace it.

The Flutter `android/` platform folder exists, with applicationId and namespace
`app.cursor.android` and minSdk 26. The Kotlin `app/` tree remains the shipped 0.1.5 install line
until the Flutter app replaces it.

## What is in the Flutter tree

Features are ported from Kotlin 0.1.5 in small steps, each with unit or widget tests.

- **Theme.** Warm-neutral light and dark colors with an orange accent, plus tests that check
  text contrast.
- **Session and preferences.** A credentials store, the cursor.com session cookie store, sign-in
  policy and navigation rules, and the display and refresh preferences used by the usage capsule
  and widgets.
- **CursorApi.** A dio client for the cursor.com web session. It covers create, follow-up, pause,
  archive and restore for agents, artifacts, the conversation stream, cloud environments (list,
  get, save) and runtime secrets (list, add, revoke), plus a generic JSON request. Domain models
  parse agent lists and usage summaries. Requests send the session cookie only to the session
  origin, never follow redirects, keep error text free of cookies and secrets, and retry once
  after refreshing an expired CSRF token.
- **UI pages.** Inbox, Create Agent, Agent Detail, Settings and Environment, plus the usage
  capsule and usage panel. Each page takes its data and callbacks from the caller and never calls
  the network itself. Error text that looks like it carries a cookie or secret is replaced by a
  generic message.
- **Widget presentation.** `WidgetState` turns cached usage, agents and preferences into the same
  English and Chinese labels as the Kotlin widgets. `WidgetPayload` flattens those labels into a
  map with stable string keys, documented at the top of `lib/widget/widget_payload.dart`, for
  home-screen widgets to read. Nothing writes this map to the platform yet.

`lib/main.dart` starts a go_router shell with the routes `/`, `/settings`, `/create`,
`/agent/:bcId` and `/environment/:publicId`. Each route gives its page disconnected stub data;
`CookieSessionStore` and `CursorApi` are not wired into the routes yet.

## Still deferred

- Live state: wiring Riverpod providers, `CookieSessionStore` and `CursorApi` into the routes, so
  the app works end to end.
- Home-screen widgets: the Glance Usage widget exists; Recent Agents and Quick Actions are not
  ported yet.
- The floating usage capsule's overlay service. Settings can request the overlay permission and
  start `UsageOverlayService`, but it does not show live usage until live state is wired.
- Flutter screenshots for this README.
- Archiving the Kotlin `app/` tree into `legacy/`, deferred by choice until Flutter replaces it.

## Verify locally

From the repository root, with the stable Flutter SDK:

```sh
flutter pub get
flutter analyze
flutter test
```

These are the same steps the `verify` job of the Flutter CI workflow
(`.github/workflows/flutter-ci.yml`) runs; its `apk` job then builds a debug APK. The workflow
runs only through manual `workflow_dispatch` (Actions → Flutter CI → Run workflow). Pull requests
and pushes do not start it.

A signed Flutter APK comes from Publish Flutter release (see [Releases](#releases)). Its current
`1.0.0+1` is versionCode 1, below the shipped Kotlin 0.1.5 (versionCode 6), so it cannot upgrade
an existing Kotlin install with the same applicationId until `+build` is raised. Until then, to
install over the shipped app, follow the Kotlin instructions in [README.md](README.md).

## Releases

Flutter releases use `.github/workflows/flutter-release.yml` (**Publish Flutter release** in
Actions). It runs only through manual `workflow_dispatch`, with one required input, `tag`: an
existing version tag such as `v1.0.0`. Pushing a tag does not start it. The legacy Kotlin
workflow, `.github/workflows/android-release.yml` (Publish Android release), is also manual
`workflow_dispatch` only and no longer runs on tags.

To cut a Flutter release:

1. Set `version:` in `pubspec.yaml` to `x.y.z+build` and commit it to `main` on its own.
2. Create and push the matching tag: `git tag vx.y.z && git push origin vx.y.z`.
3. Open Actions → Publish Flutter release → Run workflow, and enter `vx.y.z` as `tag`.

The workflow checks out that tag and fails unless it equals `v` plus the `x.y.z` from
`pubspec.yaml`. It then runs `flutter build apk --release`, rejects a debug-signed APK, and
uploads `cursor-android-x.y.z.apk` with its `.sha256` file to the GitHub Release for the tag.

These repository secrets are required (names only; never commit their values):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD`.

The current `1.0.0+1` gives versionCode 1, lower than the shipped Kotlin 0.1.5 (versionCode 6).
Android will not install a lower versionCode over an app with the same applicationId, so raise
`+build` above 6 (for example `1.0.0+7`) before an upgrade release.
