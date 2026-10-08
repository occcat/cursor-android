import assert from "node:assert/strict";
import test from "node:test";
import { latestRelease, releaseMetadata, releasesUrl } from "../scripts/release.mjs";

const stable = {
    tag_name: "v0.1.1", draft: false, prerelease: false,
    assets: [{ name: "cursor-android-0.1.1.apk",
        browser_download_url: `${releasesUrl}/download/v0.1.1/cursor-android-0.1.1.apk` }],
};

test("only a real matching stable APK enables direct download", () => {
    assert.equal(releaseMetadata(stable).status, "available");
    assert.equal(releaseMetadata(stable).version, "v0.1.1");
    for (const release of [null, { ...stable, draft: true }, { ...stable, prerelease: true },
        { ...stable, assets: [] }, { ...stable, assets: [{ name: "app-debug.apk" }] },
        { ...stable, assets: [{ name: "cursor-android-0.1.1.apk",
            browser_download_url: "https://untrusted.example/app.apk" }] }]) {
        assert.equal(releaseMetadata(release).status, "unpublished");
    }
});

test("release absence, API limits and network failure retain honest fallback links", async () => {
    assert.equal((await latestRelease(async () => ({ status: 404 }))).status, "unpublished");
    const limited = await latestRelease(async () => ({ status: 403, ok: false }));
    assert.equal(limited.status, "unavailable");
    const offline = await latestRelease(async () => { throw new Error("Offline"); });
    assert.equal(offline.status, "unavailable");
    assert.equal((await latestRelease(async () => ({ ok: true, json: async () => stable })))
        .downloadUrl, stable.assets[0].browser_download_url);
});
