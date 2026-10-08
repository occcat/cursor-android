# Website deployment

The website source is `website/`. It is a static site with no account proxy or secret
handling in browser code. Cloudflare Pages builds the repository's `main` branch.

| Setting | Value |
| --- | --- |
| Pages project | `cursor-android` |
| Repository | `occcat/cursor-android` |
| Production branch | `main` |
| Root directory | Repository root |
| Build command | `node website/scripts/build.mjs` |
| Output directory | `website/dist` |
| Build environment | `NODE_VERSION=22` |
| Project hostname | `cursor-android.pages.dev` |
| Custom domain | `cursor-android.app` |
| Apex DNS | CNAME `@` → `cursor-android.pages.dev`, managed with Pages |

The project and domain were configured through Cloudflare. Cloudflare reports the
domain Active with SSL enabled. DNS attachment is not proof of a successful build
or a verified site-content response; see the [validation record](validation.md)
for the deployment check. The first build against the original empty main is expected
to fail until the website implementation is merged.

## Local build

Requires Node.js 22 or later:

```sh
node website/scripts/build.mjs
python3 -m http.server 8788 --bind 127.0.0.1 --directory website/dist
```

Open `http://127.0.0.1:8788`. Alternatively, `node website/scripts/serve.mjs` serves
the built site on port 4173. Add `--offline` to the build command for a deterministic
unpublished-release preview. Generated `website/dist` is not committed.

## Refresh on release

A Cloudflare Pages deploy hook named `github-release` targets main. Its URL is stored
as the GitHub Actions secret **`CLOUDFLARE_PAGES_DEPLOY_HOOK`** in this repository.
Treat the entire URL as a credential. Never put it in source, README, screenshots,
build output, or a client-side environment variable.

The Website workflow handles release published/edited/deleted/unpublished events and
manual dispatch, after its verification job succeeds. GitHub does not start another
workflow from a release created with GITHUB_TOKEN, so the Android release workflow
must also call `node website/scripts/deploy-hook.mjs` directly after uploading the APK.
The website build reads GitHub’s latest stable release into `latest.json` and exposes
only a matching APK asset from this repository. Drafts, prereleases, missing APKs,
and network failures show a release/source fallback instead of an invented download; its empty-release state must
remain honest. The agreed APK naming convention is `cursor-android-<version>.apk`.
Publishing a release and making a new Pages deployment are distinct steps; verify both.
The implemented workflow is authoritative for supported event types and retry behavior.

For a manual rebuild, use the Pages dashboard or the configured workflow dispatch.
If a release is removed or download assets change, rebuild to refresh metadata.
A deploy hook triggers a build of main, so merge the relevant site code before release.
The helper validates the official Cloudflare origin/path, refuses redirects, requires
a successful JSON confirmation, and does not print the hook or response body. Its
success confirms that a deployment was requested, not that the build is live.

## Release discipline

Before distributing an Android release, increment versionName's patch and versionCode
by one in `app/build.gradle.kts`, in a separate Conventional Commit. Keep applicationId
stable. Signing credentials stay in protected CI secrets or a local secure store;
never commit a keystore or claim an unsigned/debug artifact is a signed release.

Check the new site's release label/link, APK asset, English default, Chinese selection,
mobile layout, demo interaction, custom-domain HTTPS, and absence of client-side secrets.
Roll back a bad site deployment through Pages; correct or withdraw a broken Android
release through the repository's release workflow and rebuild the site afterward.

References: [Pages Git integration](https://developers.cloudflare.com/pages/configuration/git-integration/),
[deploy hooks](https://developers.cloudflare.com/pages/configuration/deploy-hooks/),
[custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/).
