import { pathToFileURL } from "node:url";

export async function triggerDeployment(hook, fetcher = fetch) {
    if (!hook) throw new Error("CLOUDFLARE_PAGES_DEPLOY_HOOK is not configured.");
    let url;
    try { url = new URL(hook); }
    catch { throw new Error("The Pages deploy hook is not a valid URL."); }
    if (url.origin !== "https://api.cloudflare.com" || url.username || url.password
        || !url.pathname.startsWith("/client/v4/pages/webhooks/deploy_hooks/")) {
        throw new Error("The deploy hook must use the official Cloudflare Pages endpoint.");
    }
    let response;
    try {
        response = await fetcher(url, {
            method: "POST",
            redirect: "error",
            signal: AbortSignal.timeout(30000),
        });
    } catch {
        throw new Error("The Pages deploy hook request failed. Retry the workflow.");
    }
    if (!response.ok) {
        throw new Error(`Cloudflare rejected the deployment request (HTTP ${response.status}).`);
    }
    const result = await response.json().catch(() => null);
    if (result?.success !== true) {
        throw new Error("Cloudflare did not confirm the deployment request.");
    }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    try {
        await triggerDeployment(process.env.CLOUDFLARE_PAGES_DEPLOY_HOOK);
        console.log("Cloudflare Pages deployment requested for the configured production branch.");
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
