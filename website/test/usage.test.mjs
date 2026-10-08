import assert from "node:assert/strict";
import test from "node:test";
import { percent, poolValue, usageView } from "../src/usage.mjs";

test("default remaining and used representations agree across both pools", () => {
    assert.deepEqual(usageView().pools.map(pool => pool.text), ["68%", "39%"]);
    assert.deepEqual(usageView({ mode: "used" }).pools.map(pool => pool.text), ["32%", "61%"]);
    for (const mode of ["used", "remaining"]) {
        for (const pool of usageView({ mode }).pools) {
            assert.equal(pool.width, Number.parseFloat(pool.text));
        }
    }
});

test("unknown values never become zero or a full allowance", () => {
    for (const value of [null, undefined, "", " ", true, false, NaN, Infinity, "3e2", "32%", {}, []]) {
        assert.equal(percent(value), null);
        assert.deepEqual(poolValue(value, "remaining"), { text: "—", width: null });
    }
    assert.equal(percent(" 32.5 "), 32.5);
    assert.equal(percent(120), 100);
    assert.equal(percent(-3), 0);
    assert.equal(usageView({ scenario: "partial" }).pools[1].text, "—");
});

test("offline and expired sessions preserve their last snapshot", () => {
    for (const scenario of ["offline", "expired"]) {
        const view = usageView({ scenario });
        assert.equal(view.status, scenario);
        assert.deepEqual(view.pools.map(pool => pool.text), ["68%", "39%"]);
    }
});

test("unlimited has no fabricated percentage or progress width", () => {
    for (const pool of usageView({ scenario: "unlimited" }).pools) {
        assert.equal(pool.text, "∞");
        assert.equal(pool.width, null);
    }
});

test("both pools may be hidden and partial selection does not reorder them", () => {
    assert.equal(usageView({ cursor: false, other: false }).visible, false);
    const one = usageView({ cursor: false });
    assert.equal(one.visible, true);
    assert.deepEqual(one.pools.filter(pool => pool.enabled).map(pool => pool.name), ["Other Model"]);
});
