export const repository = "occcat/cursor-android";
export const releasesUrl = `https://github.com/${repository}/releases`;

export function releaseMetadata(release) {
    if (!release || release.draft || release.prerelease) {
        return { status: "unpublished", releasesUrl };
    }
    const asset = (Array.isArray(release.assets) ? release.assets : []).find(item =>
        /^cursor-android-\d+\.\d+\.\d+(?:[.-][a-zA-Z0-9.]+)?\.apk$/.test(item.name ?? "")
        && typeof item.browser_download_url === "string"
        && item.browser_download_url.startsWith(`${releasesUrl}/download/`));
    if (!asset || typeof release.tag_name !== "string") {
        return { status: "unpublished", releasesUrl };
    }
    return {
        status: "available",
        version: release.tag_name,
        downloadUrl: asset.browser_download_url,
        releasesUrl,
        publishedAt: release.published_at ?? null,
    };
}

export async function latestRelease(fetcher = fetch) {
    try {
        const response = await fetcher(`https://api.github.com/repos/${repository}/releases/latest`, {
            headers: { Accept: "application/vnd.github+json", "User-Agent": "cursor-android-website" },
            signal: AbortSignal.timeout(10000),
        });
        if (response.status === 404) return releaseMetadata(null);
        if (!response.ok) return { status: "unavailable", releasesUrl };
        return releaseMetadata(await response.json());
    } catch {
        return { status: "unavailable", releasesUrl };
    }
}
