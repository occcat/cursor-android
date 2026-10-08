export const scenarios = Object.freeze({
    normal: { cursor: 32, other: 61, status: "current" },
    tight: { cursor: 91, other: 98, status: "current" },
    offline: { cursor: 32, other: 61, status: "offline" },
    expired: { cursor: 32, other: 61, status: "expired" },
    partial: { cursor: 32, other: null, status: "current" },
    unlimited: { cursor: null, other: null, status: "unlimited" },
});

export function percent(value) {
    if (typeof value !== "number" && typeof value !== "string") return null;
    if (typeof value === "string" && !/^\d+(?:\.\d+)?$/.test(value.trim())) return null;
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : null;
}

export function poolValue(value, mode, unlimited = false) {
    if (unlimited) return { text: "∞", width: null };
    const used = percent(value);
    if (used === null) return { text: "—", width: null };
    const display = mode === "used" ? used : 100 - used;
    return { text: `${Math.round(display)}%`, width: display };
}

export function usageView({ scenario = "normal", mode = "remaining", cursor = true,
    other = true } = {}) {
    const data = scenarios[scenario] ?? scenarios.normal;
    return {
        status: data.status,
        visible: cursor || other,
        pools: [
            { id: "cursor", name: "Cursor Model", enabled: cursor, used: data.cursor },
            { id: "other", name: "Other Model", enabled: other, used: data.other },
        ].map(pool => ({ ...pool, ...poolValue(pool.used, mode, data.status === "unlimited") })),
    };
}
