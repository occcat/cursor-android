import assert from "node:assert/strict";
import test from "node:test";
import { usageView } from "../src/usage.mjs";
import { widgetAgents, widgetPreview, widgetSizes } from "../src/widgets.mjs";

test("all usage widget sizes retain the same shared pool semantics", () => {
    for (const size of widgetSizes.usage) {
        for (const scenario of ["normal", "tight", "offline", "stale", "expired", "partial",
            "unlimited"]) {
            for (const mode of ["remaining", "used"]) {
                const state = { scenario, mode };
                const widget = widgetPreview(state, "usage", size);
                assert.deepEqual(widget.pools, usageView(state).pools);
                assert.equal(widget.status, usageView(state).status);
            }
        }
    }
});

test("hidden pools stay hidden in compact and detailed widgets", () => {
    for (const size of widgetSizes.usage) {
        assert.equal(widgetPreview({ cursor: false, other: false }, "usage", size).pools.length, 0);
        const single = widgetPreview({ cursor: false }, "usage", size);
        assert.deepEqual(single.pools.map(pool => pool.name), ["Other Model"]);
    }
});

test("switching widget families chooses a supported size", () => {
    assert.equal(widgetPreview({}, "agents", "2x1").size, "2x2");
    assert.equal(widgetPreview({}, "actions", "4x2").size, "2x1");
    assert.equal(widgetPreview({}, "unknown", "invalid").family, "usage");
});

test("compact actions retain two readable destinations and wide adds usage and settings", () => {
    assert.deepEqual(widgetPreview({}, "actions", "2x1").actions, ["inbox", "newAgent"]);
    assert.deepEqual(widgetPreview({}, "actions", "4x1").actions,
        ["inbox", "newAgent", "usage", "settings"]);
});

test("recent agent privacy and counts match the compact and wide native layouts", () => {
    assert.ok(widgetAgents().every(agent => agent.titleKey === null));
    assert.ok(widgetAgents(false, true).every(agent => agent.titleKey === null));
    assert.deepEqual(widgetAgents(true).map(agent => agent.titleKey), ["agentOne"]);
    assert.deepEqual(widgetAgents(true, true).map(agent => agent.titleKey),
        ["agentOne", "agentTwo"]);
});
