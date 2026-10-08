# Contributing

Keep changes small and specific to the issue. English is the default for code-facing
messages, documentation, and UI resources; optional Chinese translations belong next
to the canonical version. This repository currently has no declared redistribution
license; do not assume a license based on another project's README.

## Local checks

Use the tested JDK 21 toolchain and Android SDK 36. Select JDK 21 as Android
Studio’s Gradle JDK, or point `JAVA_HOME` to its installation. On macOS with JDK 21
installed: `export JAVA_HOME="$(/usr/libexec/java_home -v 21)"`. Website checks require
Node.js 22 or later; the documentation check also requires Python 3.

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
node --test website/test/*.test.mjs
node website/scripts/build.mjs
python3 docs/scripts/check-docs.py
```

Run the relevant subset for a scoped change and the full suite after integration.
Device changes also need `./gradlew :app:connectedDebugAndroidTest` where a device is
available, plus the relevant [manual matrix](docs/testing.md). Record unavailable
checks explicitly. A logic fix should include a regression test.

## Commits

Follow [AGENTS.md](AGENTS.md). Every commit uses a Conventional Commits subject, a
blank line, and a multiline body describing observable behavior, compatibility
boundaries, and concrete validation commands. For example:

```text
fix(usage): preserve unknown pool values

Keep a missing pool visible as unavailable instead of displaying zero usage.
Preserve the other pool, the selected metric, and the existing account scope.
Validation: ./gradlew :app:testDebugUnitTest
```

Use an English branch under `thoxvi/` and check for a collision before creating it.
Do not commit keys, cookies, signing material, local.properties, backup ciphertext,
compiled packages, or generated website output.

## Release changes

Before producing an installable distribution release, increment `versionName` by one
patch and `versionCode` by one in `app/build.gradle.kts`. Commit that separately as
`chore(app): bump release to <versionName>`, with the required multiline body. Keep
applicationId stable. A debug or unsigned package is not a signed release.

## API changes

Preserve API/web credential separation, unknown-field tolerance, and documented
capability boundaries. Add sanitized fixtures, not production account responses.
Do not turn a static route candidate into a claimed verified endpoint. Update the
capability matrix, test plan, and validation record when behavior changes.
