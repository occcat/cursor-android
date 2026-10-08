import { translations } from "./i18n.mjs";
import { usageView } from "./usage.mjs";
import { widgetAgents, widgetPreview, widgetSizes } from "./widgets.mjs";

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const original = new Map();
for (const node of $$("[data-i18n]")) {
    const text = [...node.childNodes]
        .map(child => child.nodeName === "BR" ? "\n" : child.textContent)
        .join("").replace(/[ \t]*\n[ \t]+/g, " ").trim();
    original.set(node.dataset.i18n, text);
}
for (const node of $$("[data-i18n-aria]")) {
    original.set(node.dataset.i18nAria, node.getAttribute("aria-label"));
}
let language = "en";
try { if (localStorage.getItem("cursor-android-language") === "zh-CN") language = "zh-CN"; }
catch { /* Language remains usable when browser storage is unavailable. */ }
const state = { scenario: "normal", mode: "remaining", cursor: true, other: true };
let release;
let widgetFamily = "usage";
let widgetSize = "2x2";
let widgetAction = null;
let widgetShowTitles = false;
const t = key => translations[language][key] ?? original.get(key) ?? translations.en[key] ?? key;

function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
}

function renderUsage() {
    const view = usageView(state);
    $$("[data-scenario]").forEach(node => { node.value = state.scenario; });
    $$("[data-pool]").forEach(node => { node.checked = state[node.dataset.pool]; });
    const capsule = $("#capsule");
    const rows = $("#pool-rows");
    const notification = $("#notification-values");
    capsule.replaceChildren();
    rows.replaceChildren();
    notification.replaceChildren();
    const modeText = t(state.mode === "remaining" ? "remainingCycle" : "usedCycle");
    $$("[data-mode-label]").forEach(node => { node.textContent = modeText; });
    capsule.setAttribute("aria-label", modeText);
    capsule.hidden = !view.visible;
    $("#status-icon").hidden = !view.visible;
    $("#capsule-hidden").hidden = view.visible;
    $("#pool-empty").hidden = view.visible;
    $("#usage-notification").hidden = !view.visible;
    $("#notification-hidden").hidden = view.visible;
    $("#cycle-card").hidden = ["unlimited", "expired"].includes(view.status) || !view.visible;
    $("#usage-plan").hidden = view.status === "expired";
    for (const pool of view.pools.filter(pool => pool.enabled)) {
        const pill = element("span");
        pill.append(element("i", `dot ${pool.id}`),
            element("span", "", pool.id === "cursor" ? "Cursor" : "Other"),
            element("b", "", pool.text));
        capsule.append(pill);
        const row = element("div", "pool-row");
        const top = element("div", "pool-row-top");
        const label = element("span");
        label.append(element("i", `dot ${pool.id}`), document.createTextNode(pool.name));
        top.append(label, element("strong", "", pool.text));
        row.append(top);
        if (pool.width !== null) {
            const track = element("div", `pool-track ${pool.id}`);
            const fill = element("span");
            fill.style.width = `${pool.width}%`;
            track.append(fill);
            track.setAttribute("aria-hidden", "true");
            row.append(track);
            const opposite = state.mode === "remaining" ? pool.used : 100 - pool.used;
            const suffix = t(state.mode === "remaining" ? "usedDetail" : "remainingDetail");
            row.append(element("small", "", `${Math.round(opposite)}% ${suffix}`));
        } else if (view.status !== "unlimited") {
            const hint = view.status === "expired" ? "reconnectForUsage" : "unavailable";
            row.append(element("small", "", t(hint)));
        }
        rows.append(row);
        const value = element("span");
        value.append(element("i", `dot ${pool.id}`), document.createTextNode(pool.name),
            element("b", "", pool.text));
        notification.append(value);
    }
    const note = t(`${view.status}Note`);
    $("#state-note").textContent = note;
    const warning = ["offline", "stale", "expired"].includes(view.status);
    $("#state-note").classList.toggle("warning", warning);
    $("#notification-state").textContent = note;
    renderWidgets();
}

function renderWidgets() {
    const view = widgetPreview(state, widgetFamily, widgetSize);
    const preview = $("#widget-preview");
    preview.replaceChildren();
    preview.dataset.family = view.family;
    preview.dataset.size = view.size;
    const heading = element("div", "home-widget-heading");
    const title = view.family === "usage" ? "Cursor Usage"
        : t(view.family === "agents" ? "recentAgents" : "quickActions");
    heading.append(element("strong", "", title), element("span", "widget-mark", "◈"));
    preview.append(heading);
    if (view.family === "usage") {
        preview.append(element("p", "home-widget-mode",
            t(state.mode === "remaining" ? "remainingCycle" : "usedCycle")));
        const pools = element("div", "home-widget-pools");
        for (const pool of view.pools) {
            const item = element("div", "home-widget-pool");
            const label = element("span", "home-widget-pool-label");
            label.append(element("i", `dot ${pool.id}`), document.createTextNode(pool.name));
            item.append(label, element("strong", "", pool.text));
            if (view.detailed && pool.width !== null) {
                const track = element("div", `pool-track ${pool.id}`);
                const fill = element("span");
                fill.style.width = `${pool.width}%`;
                track.setAttribute("aria-hidden", "true");
                track.append(fill);
                item.append(track);
            }
            pools.append(item);
        }
        if (!view.pools.length) pools.append(element("p", "widget-empty", t("widgetEmpty")));
        preview.append(pools, element("p", "home-widget-status", view.status === "current"
            ? t("widgetSnapshot") : t(`${view.status}Note`)));
    } else if (view.family === "agents") {
        preview.append(element("p", "home-widget-mode", t("widgetCached")));
        for (const agent of widgetAgents(widgetShowTitles, view.wide)) {
            const row = element("div", "home-widget-agent");
            row.append(element("span", "widget-agent-icon", "◈"));
            const body = element("div");
            const title = agent.titleKey ? t(agent.titleKey)
                : `${t("widgetPrivateTitle")} ${agent.number}`;
            body.append(element("strong", "", title),
                element("span", "", t("widgetActive")));
            row.append(body);
            preview.append(row);
        }
    } else {
        const actions = element("div", "home-widget-actions");
        const icons = { inbox: "▤", newAgent: "+", usage: "◔", settings: "⚙" };
        for (const action of view.actions) {
            const button = element("button");
            button.type = "button";
            button.dataset.widgetAction = action;
            const label = `widget${action[0].toUpperCase()}${action.slice(1)}Action`;
            button.append(element("span", "", icons[action]), element("strong", "", t(label)));
            button.addEventListener("click", () => {
                widgetAction = action;
                renderWidgetFeedback();
            });
            actions.append(button);
        }
        preview.append(actions);
    }
    $("#widget-usage-controls").hidden = view.family !== "usage";
    $("#widget-agent-controls").hidden = view.family !== "agents";
    renderWidgetFeedback();
}

function renderWidgetFeedback() {
    const key = widgetFamily === "actions" && widgetAction
        ? `widget${widgetAction[0].toUpperCase()}${widgetAction.slice(1)}Result` : "widgetIdle";
    $("#widget-feedback").textContent = t(key);
}

function renderWidgetSizes() {
    const select = $("#widget-size");
    select.replaceChildren();
    if (!widgetSizes[widgetFamily].includes(widgetSize)) widgetSize = widgetSizes[widgetFamily][0];
    for (const size of widgetSizes[widgetFamily]) {
        const option = element("option", "", size.replace("x", " × "));
        option.value = size;
        select.append(option);
    }
    select.value = widgetSize;
}

function renderRelease() {
    if (!release) return;
    const prefix = "https://github.com/occcat/cursor-android/releases/download/";
    if (release.status === "available" && typeof release.downloadUrl === "string"
        && release.downloadUrl.startsWith(prefix)) {
        $("#download-link").href = release.downloadUrl;
        $("#download-label").textContent = t("downloadApk");
        $("#release-status").textContent = t("releaseAvailable")
            .replace("{version}", release.version);
    } else {
        $("#release-status").textContent = t(release.status === "unpublished"
            ? "releaseMissing" : "releaseFallback");
    }
}

function renderLanguage() {
    document.documentElement.lang = language;
    $$("[data-i18n]").forEach(node => { node.textContent = t(node.dataset.i18n); });
    $$("[data-i18n-aria]").forEach(node => {
        node.setAttribute("aria-label", t(node.dataset.i18nAria));
    });
    $("#language").textContent = language === "en" ? "中文" : "EN";
    $("#language").lang = language === "en" ? "zh-CN" : "en";
    $("#language").setAttribute("aria-label", language === "en" ? "Switch to Chinese" : "切换到英语");
    renderUsage();
    renderRelease();
}

$("#language").addEventListener("click", () => {
    language = language === "en" ? "zh-CN" : "en";
    try { localStorage.setItem("cursor-android-language", language); }
    catch { /* Optional preference. */ }
    renderLanguage();
});
$$("[data-scenario]").forEach(select => select.addEventListener("change", event => {
    state.scenario = event.target.value;
    renderUsage();
}));
$$("[data-mode]").forEach(button => button.addEventListener("click", () => {
    state.mode = button.dataset.mode;
    $$("[data-mode]").forEach(node => {
        node.setAttribute("aria-pressed", String(node.dataset.mode === state.mode));
    });
    renderUsage();
}));
$$("[data-pool]").forEach(input => input.addEventListener("change", event => {
    state[input.dataset.pool] = event.target.checked;
    renderUsage();
}));
$$("[data-widget-family]").forEach(button => button.addEventListener("click", () => {
    widgetFamily = button.dataset.widgetFamily;
    widgetAction = null;
    $$("[data-widget-family]").forEach(node => {
        node.setAttribute("aria-pressed", String(node.dataset.widgetFamily === widgetFamily));
    });
    renderWidgetSizes();
    renderWidgets();
}));
$("#widget-size").addEventListener("change", event => {
    widgetSize = event.target.value;
    renderWidgets();
});
$("#widget-show-titles").addEventListener("change", event => {
    widgetShowTitles = event.target.checked;
    renderWidgets();
});
const tabs = $$("[data-tab]");
function selectTab(button) {
    tabs.forEach(tab => {
        const selected = tab === button;
        tab.setAttribute("aria-selected", String(selected));
        tab.tabIndex = selected ? 0 : -1;
        $(`#panel-${tab.dataset.tab}`).hidden = !selected;
    });
}
tabs.forEach((button, index) => {
    button.addEventListener("click", () => selectTab(button));
    button.addEventListener("keydown", event => {
        let next;
        if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
        if (event.key === "ArrowLeft") next = (index + tabs.length - 1) % tabs.length;
        if (event.key === "Home") next = 0;
        if (event.key === "End") next = tabs.length - 1;
        if (next === undefined) return;
        event.preventDefault();
        selectTab(tabs[next]);
        tabs[next].focus();
    });
});
$("#privacy-link").addEventListener("click", event => {
    event.preventDefault();
    $("#privacy-dialog").showModal();
});
renderWidgetSizes();
renderLanguage();
fetch("/latest.json", { cache: "no-cache" })
    .then(response => response.ok ? response.json()
        : Promise.reject(new Error("Metadata unavailable")))
    .then(metadata => { release = metadata; renderRelease(); })
    .catch(() => { /* The static GitHub release link remains available. */ });
