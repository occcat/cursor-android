# Cursor Android documentation

English is the default for the app, website, and documentation. The original
[Chinese research](zh-CN/README.md) is retained as a dated reference.

Start with the [project README](../README.md) for the current delivery status.
These documents explain the API evidence, implementation boundaries, and UI design.
Research began on October 8 and concluded on October 9, 2026.

| Read | Purpose |
| --- | --- |
| [Web API inventory](cursor-api-inventory.md) | Agents, settings, usage, Connect, files, terminal, desktop |
| [Public API reference](cursor-public-api.md) | All 33 v1, 12 worker/pool, and 12 legacy operations reviewed |
| [Android implementation plan](android-implementation-plan.md) | Architecture, authentication, state, offline behavior |
| [Capsule and status bar](design/cursor-android-ui.md) | Two-pool data contract, visual states, Android constraints |
| [Interactive prototype](design/cursor-android-prototype.html) | Fictional data; no Cursor requests or credentials |
| [Endpoint evidence](api/cursor-web-endpoints.json) | Per-route methods, type-only shapes, bundle references |
| [Protocol evidence](api/cursor-web-services.json) | Connect, Tmux, PTY, and protobuf field descriptors |
| [Test plan](testing.md) | Automated, browser, account, and device acceptance gates |
| [Validation record](validation.md) | Executed checks, pending checks, and evidence |
| [Deployment](deployment.md) | Pages, the custom domain, and release refreshes |

## What the research establishes

- Official v1 uses separate Agent and Run resources, SSE, artifacts, environments,
  and Secrets. A documented API is not proof of account entitlement or live integration.
- The web app also uses POST JSON, Connect streams, blobs, VM WebSockets, and VNC.
  **857 route candidates** were found in **428 public JavaScript chunks**. Network
  observation covered **123 distinct paths**, including **120 with responses**.
  Shared dashboard code is included; this is not an exhaustive server API claim.
- Cursor Model maps to `individualUsage.plan.autoPercentUsed`; Other Model maps to
  `individualUsage.plan.apiPercentUsed`. These are account pools, not a guess based
  on model names, token counts, or currency.
- A normal Android status bar shows a monochrome notification icon. Two values fit
  in the notification drawer; a full capsule belongs in the app or a permitted overlay.

## Evidence handling

The ego audit inspected Agents, existing Changes/Desktop/Files views, personal and
Cloud Agent settings, environments, MCP/plugins, integrations, keys, Automations,
Codebase, Usage, Spending, and Billing. Durable evidence contains paths and types,
not cookies, keys, Secret values, VM credentials, or private conversation content.

Opening the new-automation editor automatically created one disabled empty draft.
That draft was deleted and the empty list was verified. No Agent prompt, terminal
command, file save, or desktop takeover was executed during the audit. Unexecuted
writes, team permissions, and Android login remain separate validation concerns.

## Preview the design

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design
```

Open [the local prototype](http://127.0.0.1:8765/cursor-android-prototype.html).
The prototype does not make business API requests or store account settings.
