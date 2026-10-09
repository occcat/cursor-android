# Cursor Android website

A static, English-first site with an optional Chinese interface and an interactive sample-data
preview. No framework, runtime packages, analytics, or account credentials are required.

## Develop and verify

Requires Node.js 22 or newer. Run from the repository root:

```sh
node --test website/test/*.test.mjs
node --check website/src/app.mjs
node website/scripts/build.mjs --offline
node website/scripts/serve.mjs
```

Open <http://127.0.0.1:4173>. Set `PORT` to change the local port. Generated `website/dist/` is
ignored.
Omit `--offline` to resolve the newest stable GitHub release during the build.

Browser checks: English and Chinese; keyboard tabs and privacy dialog; 320, 390, 768, and 1440 px;
remaining/used values; both pools hidden; normal, low, offline, expired, unknown, and unlimited
states;
notification consistency; language persistence; reduced motion; no horizontal page overflow.

The home-screen widget preview shares the same usage state and controls as the phone preview.
Verify every suggested size, private agent titles before opt-in, and compact versus wide quick
actions. Offline and stale data retain their values; an expired connection clears percentages.
The grid labels are suggestions because launcher cell dimensions vary. Preview shortcut clicks
describe their in-app destinations and never send a task or change device permissions.

## Cloudflare Pages

| Setting | Value |
| --- | --- |
| Project | `cursor-android` |
| Repository | `occcat/cursor-android` |
| Root directory | Repository root |
| Production branch | `main` |
| Build command | `node website/scripts/build.mjs` |
| Output directory | `website/dist` |
| Build environment | `NODE_VERSION=22` |
| Custom domain | `cursor-android.app` |

Git integration builds production on main changes and provides branch previews. Create the custom
domain in **Pages → Custom domains** before changing its DNS. The apex zone must belong to the same
Cloudflare account. The `_headers` file applies the static site's security headers.

Create a production deploy hook named `github-release` targeting `main` in **Pages → Settings →
Builds**. Store its complete URL in the GitHub repository Actions secret
`CLOUDFLARE_PAGES_DEPLOY_HOOK`. Treat the URL as a credential; never commit or print it.

The `Website` GitHub Actions workflow validates each relevant pull request and requests a fresh
production build on release publication, edits, removal, or manual dispatch. Cloudflare fetches the
latest stable release during that build. A successful hook request confirms that the deployment was
queued; inspect Pages for the build's completion and then verify the live domain. It is safe to
rerun
the workflow if a request fails.

The download contract is a stable GitHub release with an asset named
`cursor-android-<version>.apk`, hosted under this repository's release downloads. Drafts,
prereleases,
missing APKs, and external asset URLs never become a download button. Network errors retain a link
to
GitHub Releases. No package version is invented by the website.

## Source references

- [Cloudflare static HTML builds][static-builds]

[static-builds]: https://developers.cloudflare.com/pages/framework-guides/deploy-anything/
- [Cloudflare deploy hooks](https://developers.cloudflare.com/pages/configuration/deploy-hooks/)
- [Cloudflare custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/)
- [Cursor](https://cursor.com/home) for the warm neutral light and dark palettes, which follow
  the system color scheme.
- [Vibe Island](https://vibeisland.app) for the product-preview-led content hierarchy.

This is an independent community project, without Cursor or Anysphere affiliation. The site uses
system fonts and its own code and artwork. Android feature support is documented in the project
README; the illustrated agent messages and usage values on this website are sample data.
