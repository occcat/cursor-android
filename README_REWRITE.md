# Flutter rewrite (1.x)

## Status

The app is being rewritten in Flutter, working toward 1.0.0. The rewrite lives at the repository
root in `pubspec.yaml`, `lib/` and `test/`.

The Kotlin 0.1.5 app is still in `app/` and is the release that ships today. See
[README.md](README.md) for its features and its build and install instructions. Archiving the
Kotlin tree is deferred until the Flutter app can replace it.

The Flutter `android/` platform folder does not exist yet. CI will generate it with
`flutter create` in a later round.

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

`lib/main.dart` still shows a placeholder home page. The pages above are not connected to routes
or live data yet.

## Deferred until `android/` exists

- Home-screen widgets through `home_widget` and Glance: a refreshable Usage widget, Recent Agents
  and Quick Actions.
- The floating usage capsule, which needs the overlay permission. Until then, the Settings page
  says the capsule arrives in a later update.
- Wiring the pages into the go_router shell with real data, so the app works end to end.

## Verify locally

From the repository root, with the stable Flutter SDK:

```sh
flutter pub get
flutter analyze
flutter test
```

These are the same steps the Flutter CI workflow (`.github/workflows/flutter-ci.yml`) runs. It
runs on pull requests and pushes to `main` that change `lib/`, `test/`, `pubspec.yaml`,
`pubspec.lock`, `analysis_options.yaml` or the workflow file itself.

The Flutter tree cannot produce an installable app yet, because `android/` is missing. To build
or install the app today, follow the Kotlin instructions in [README.md](README.md).

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
