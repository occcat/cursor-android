import assert from "node:assert/strict";
import test from "node:test";
import { triggerDeployment } from "../scripts/deploy-hook.mjs";

const hook = "https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/test-secret";

test("production deploy uses only the configured Cloudflare POST hook", async () => {
    let called = false;
    await triggerDeployment(hook, async (url, options) => {
        called = true;
        assert.equal(url.href, hook);
        assert.equal(options.method, "POST");
        assert.equal(options.redirect, "error");
        return { ok: true, json: async () => ({ success: true }) };
    });
    assert.equal(called, true);
});

test("absent and off-origin hooks fail before any network request", async () => {
    for (const url of [undefined, "bad-url", "https://example.com/secret",
        "https://api.cloudflare.com/wrong-endpoint"] ) {
        await assert.rejects(triggerDeployment(url, () => assert.fail("Must not send")));
    }
});

test("request errors never expose the secret hook URL", async () => {
    for (const fetcher of [
        async () => { throw new Error(`Failed to fetch ${hook}`); },
        async () => ({ ok: false, status: 500 }),
        async () => ({ ok: true, json: async () => ({ success: false }) }),
        async () => ({ ok: true, json: async () => { throw new Error("Invalid JSON"); } }),
    ]) {
        await assert.rejects(triggerDeployment(hook, fetcher), error => {
            assert.ok(!error.message.includes(hook));
            assert.ok(!error.message.includes("test-secret"));
            return true;
        });
    }
});
