# Android home-screen widgets

The widget extension adds three separate families: **Usage**, **Recent Agents**, and
**Quick Actions**. Widgets share the app's account-scoped data and local preferences.
English is the default; Chinese follows the selected app language.
The [validation record](../validation.md) distinguishes design, fixture checks,
launcher/device checks, and live-account verification.

The [website widget showcase](https://cursor-android.app/#widgets) uses fictional
preview data; it is distinct from native launcher verification.

## Native capture evidence

These are actual API 36 Glance RemoteViews rendered in the debug AppWidgetHostView,
captured in the light system theme. The figures and Agent summaries are injected
synthetic fixtures, not production account data. The files are unedited full-screen
captures (1080 × 1920 px, 320 × 569 dp); open them to inspect the widget at its recorded
dimensions. The line above each widget is the debug host's fixture label; that host does
not inset its content, so the label sits under the emulator's status bar. Dark-theme
variants come from the same device job as part of its `device-screens` artifact. The
captures do not establish behavior on every launcher or replace a live-account check.

| Capture | What it verifies visually |
| --- | --- |
| [Compact Usage, 160×80 dp](../assets/widget-usage-160x80.png) | Both values and the metric/fetch timestamp |
| [Detailed Usage, 320×180 dp](../assets/widget-usage-320x180.png) | Bars, freshness, supplementary pace/reset, and visible Refresh |
| [Wide Recent Agents](../assets/widget-agents-wide.png) | Two side-by-side cards with private placeholder titles |
| [Chinese Usage](../assets/widget-usage-chinese.png) | Selected Chinese and used values 32% / 61% |
| [Compact Usage at 1.3× font](../assets/widget-large-text-160x80.png) | Readable values, English preference, and complete timestamp |

## Information and layout

| Family | Purpose | Compact layout | More space |
| --- | --- | --- | --- |
| Usage | Two account pools | 2×1 / 4×1: values, metric, and timestamp | 2×2 / 4×2: bars and Refresh |
| Recent Agents | Cached Agent state | 2×2: one Agent | 4×2: two; tall 4×3: up to three |
| Quick Actions | Native app entries | 2×1: Inbox + New Agent | 4×1: also Usage + Settings |

Cell counts describe the launcher's grid, not universal physical dimensions. A
launcher can choose different spacing, padding, and resize increments. Android 12+
`targetCellWidth` / `targetCellHeight` are hints; older launchers use minimum dp sizes.
Keep supported resize bounds honest and let layout respond to available space.
See Google's [widget sizing guide](https://developer.android.com/develop/ui/compose/glance/create-app-widget).

On the tested Pixel 8 API 36 emulator at 420 dpi, Pixel Launcher's picker labels
Usage **2×2** despite the one-row target hint, to accommodate its 80 dp minimum
height and launcher geometry. The dp bounds below define the available layouts;
nominal grid labels do not guarantee a particular cell count on every launcher.

The app uses a small set of responsive layouts with Jetpack Glance. Glance has
its own components and is limited by AppWidget/RemoteViews; the app's ordinary
Material 3 composables cannot simply be placed into a home-screen widget.
Do not shrink text until it becomes unreadable to force a large layout into a small
cell. Hide optional detail first, retain clear actions, and preserve touch targets.
See [responsive Glance UI](https://developer.android.com/develop/ui/compose/glance/build-ui).

The native responsive layouts use these dp bounds; grid labels above remain approximate:

| Provider | Responsive layout bounds |
| --- | --- |
| Usage | 160×80, 320×80, 160×180, 320×180 dp |
| Recent Agents | 160×180, 320×180, 320×300 dp |
| Quick Actions | 160×80, 320×80 dp |

Compact Usage omits the redundant heading: two pool rows sit above a combined
metric/timestamp line, such as `Left · 10-09 01:35`. Detailed Usage retains the full
Remaining/Used heading. Usage detail bars appear only for finite, known values with
a connected web session. Unknown and unlimited states do not draw misleading
percentage bars. The wide 180 dp Agent layout uses two cards side by side; the
300 dp layout uses up to three rows. Larger text reduces the tall layout to two
rows and omits supplementary target/reset text from detailed Usage before shrinking
essential content. The 1.3× font-scale check covers this adaptive behavior.

## Usage semantics

The [capsule contract](cursor-android-ui.md) also governs widget numbers: Cursor Model
uses autoPercentUsed, Other Model uses apiPercentUsed, and remaining is the default.
The widget must not independently recategorize models or calculate percentages from
currency/token counts. The same setting controls used/remaining across all surfaces.

Keep unknown distinct from zero, unlimited distinct from 100%, and stale snapshots
visibly labeled. A cycle that has ended does not locally reset a widget to zero.
When both pools are hidden, show an intentional settings/hidden state rather than an
empty decorative card. A web session is required for account usage; having only an
API key does not establish that web session.

## Agent status and actions

An Agent's ACTIVE/IDLE/ARCHIVED lifecycle differs from the current Run's execution
status. A widget that only has Agent summaries must label them as Agent state, not
claim every ACTIVE Agent is currently RUNNING. Run-based counts require actual Run
state. Recent data is cached, scoped to the connected account, and not a guarantee
that all historical web conversations are visible through the public API.

Recent Agent rows open the exact native detail using a validated Agent ID. Compact
Quick Actions opens Inbox or New Agent; the wide layout adds Usage and Settings.
A **New Agent** action opens the composer; it does not send a prompt, consume paid
usage, or start an old draft without confirmation. Account-bound actions validate
the current connection rather than reusing another account's cached target.
Use the platform's activity-start action
for navigation, not an indirect service launch that can fail under background rules.
See [Glance interactions](https://developer.android.com/develop/ui/compose/glance/user-interaction).

## Refresh and privacy

Compact Usage opens the native usage panel, where a refresh action is available;
the larger detail layout also exposes Refresh directly. Timestamps use persisted
cache fetch times, displayed as `MM-dd HH:mm`. Data older than 30 minutes is marked
stale; expiry and missing data retain their separate states.

Render the last available snapshot quickly. Share refresh scheduling with the app;
do not create one network polling loop per widget instance. User-triggered refresh
can request synchronization, but loading/failure must not replace known data with
fake zeros. Preferences and successful cache changes should update relevant instances.

Android's periodic widget update interval is at least 30 minutes; WorkManager can
schedule 15-minute periodic work, inexactly. Neither is a real-time guarantee, and
minute-by-minute background refresh wastes battery. The app may update widgets
immediately while awake after a meaningful state change.
See [widget updates](https://developer.android.com/develop/ui/compose/glance/glance-app-widget).

The widget contains display data and app actions, not API keys, cookies, signed URLs,
or Secret values. Disconnecting or switching accounts clears/replaces old account
content and rejects late responses. Agent titles are private by default. Users can
explicitly enable their display in Settings; enabled titles are visible on the home
screen. Widget placement and title disclosure are separate deliberate choices.
A widget does not require the separate overlay permission.

## Acceptance

- Add each family, resize across supported bounds, and reopen the launcher.
- Verify English default and selected Chinese, long labels, large text, and theme.
- Compare two-pool values/metric with the app and notification using the same fixture.
- Verify unknown, partial, unlimited, hidden, offline, and expired-session states.
- Test cold/warm navigation to Inbox, usage, settings, the composer, and exact Agent details.
- Confirm New Agent only opens the composer and never submits by itself.
- Switch/disconnect accounts with in-flight work; no previous-account content persists.
- Remove/re-add widgets and handle multiple instances without duplicate polling.
- Record actual launcher/API/device coverage. A host test or screenshot does not
  establish behavior on every vendor launcher.
