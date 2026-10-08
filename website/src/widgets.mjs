import { usageView } from "./usage.mjs";

export const widgetSizes = Object.freeze({
    usage: ["2x1", "4x1", "2x2", "4x2"],
    agents: ["2x2", "4x2"],
    actions: ["2x1", "4x1"],
});

export function widgetPreview(state, family = "usage", size = "2x2") {
    const safeFamily = Object.hasOwn(widgetSizes, family) ? family : "usage";
    const safeSize = widgetSizes[safeFamily].includes(size) ? size : widgetSizes[safeFamily][0];
    const usage = usageView(state);
    return {
        family: safeFamily,
        size: safeSize,
        detailed: safeSize.endsWith("x2"),
        wide: safeSize.startsWith("4x"),
        status: usage.status,
        pools: usage.pools.filter(pool => pool.enabled),
        actions: safeSize.startsWith("4x")
            ? ["inbox", "newAgent", "usage", "settings"] : ["inbox", "newAgent"],
    };
}

export function widgetAgents(showTitles = false, wide = false) {
    const keys = wide ? ["agentOne", "agentTwo", "agentThree"] : ["agentOne", "agentTwo"];
    return keys.map((key, index) => ({ titleKey: showTitles ? key : null, number: index + 1 }));
}
