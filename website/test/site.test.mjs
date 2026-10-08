import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import test from "node:test";
import { translations } from "../src/i18n.mjs";

const source = new URL("../src/", import.meta.url);
const html = await readFile(new URL("index.html", source), "utf8");

test("all user-facing translation keys have Chinese alternatives", () => {
    const keys = [...html.matchAll(/data-i18n(?:-aria)?="([^"]+)"/g)].map(match => match[1]);
    for (const key of [...keys, ...Object.keys(translations.en)]) {
        assert.equal(typeof translations["zh-CN"][key], "string", `Missing Chinese: ${key}`);
    }
    assert.match(html, /<html lang="en">/);
});

test("local assets and fragment links resolve and IDs are unique", async () => {
    const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
    assert.equal(new Set(ids).size, ids.length, "Duplicate IDs");
    const paths = [...html.matchAll(/(?:src|href)="(\/[^"#]+)"/g)].map(match => match[1]);
    for (const path of paths) await access(new URL(`.${path}`, source));
    for (const match of html.matchAll(/href="#([^"]+)"/g)) {
        assert.ok(ids.includes(match[1]), `Unknown fragment: ${match[1]}`);
    }
});

test("demo does not embed credentials, tracking, or live business API calls", async () => {
    const app = await readFile(new URL("app.mjs", source), "utf8");
    assert.deepEqual([...app.matchAll(/fetch\("([^"]+)"/g)].map(match => match[1]), ["/latest.json"]);
    assert.doesNotMatch(html, /<script[^>]+src="https?:/i);
    assert.match(html, /Sample data/);
    assert.match(html, /not affiliated/i);
    const headers = await readFile(new URL("_headers", source), "utf8");
    assert.match(headers, /frame-ancestors 'none'/);
    assert.match(headers, /connect-src 'self'/);
});
