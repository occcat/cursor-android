# Capsule and Android status bar

Two pools, one snapshot: **Cursor Model** and **Other Model**. English is the default;
Chinese can be selected. This document is a design contract; consult the
[project status](../../README.md) for the implemented subset.
The [interactive prototype](cursor-android-prototype.html) uses fictional data only.

## Visual language

Warm neutral surfaces, hairline dividers, one orange accent, regular-weight headings, and
readable tabular numbers follow the visual language of [Cursor](https://cursor.com): colors,
type rhythm, radii, and motion only. No Cursor logo, proprietary font, or site artwork is used.
Light and dark both follow the system setting; there is no in-app theme switch.
The Android implementation uses dp/sp, rather than copying browser CSS pixels.

| Token | Light | Dark |
| --- | --- | --- |
| Background | `#f7f7f4` | `#14120b` |
| Text | `#26251e` | `#edecec` |
| Secondary text | `#676660` | `#969592` |
| Card | `#f2f1ed` | `#1b1913` |
| Raised (secondary buttons, tracks, widget tiles) | `#e6e5e0` | `#26241e` |
| Divider | `#e2e2df` | `#2a2822` |
| Accent (graphics, focus, busy bar) | `#f54e00` | `#f54e00` |
| Accent text | `#c43e00` | `#f54e00` |
| Cursor pool | `#f54e00` | `#f54e00` |
| Other pool | `#82817c` | `#767470` |
| Success | `#17775a` | `#3fb68b` |
| Warning | `#a46700` | `#f1b467` |
| Error | `#b8244a` | `#e5506f` |

Buttons are pills: ink fill for the primary action, the raised tone for secondary actions.
Cards are 8 dp with no shadow, inputs 8 dp, dialogs 12 dp, and sheets 16 dp at the top.
Small section labels are monospace capitals. Color changes take 140 ms and progress changes
250 ms with a spring-like ease; system animation scale and reduced motion are respected.
The same tokens live in `CursorTheme.kt`, `res/values*/colors.xml`, and the website stylesheet.

Pool identity colors stay fixed. Low quota, stale data, and errors use words/icons,
not two indistinguishable red bars. Small body text must retain sufficient contrast;
`CursorThemeTest` checks text roles against AA and graphics against 3:1 in both themes.
Support large type, TalkBack, dark mode, rotation, split-screen, and ≥48 dp touch targets.

## Capsule, details, and notification

![Capsule and notification design](../assets/cursor-android-ui.svg)

*Design illustration. Values are fictional; this is not a screenshot of a live account.*

The default compact capsule reads **Cursor 68% · Other 39%**, with a visible or spoken
**remaining** label. Visual size is approximately 156 × 40 dp inside a ≥48 dp target.
At large font sizes, allow growth or two lines. An optional mini-bar variant is
176 × 48 dp, with 60 × 6 dp bars. A dual-ring variant is future design, not a combined
quota score. Tap opens details; drag must not accidentally activate a tap.

A details sheet uses 16 dp padding and a tablet maximum around 400 dp. Each fixed slot
shows full pool name, primary metric, secondary used value, a 6 dp rounded progress
bar, pace marker, and textual pace. The footer shows cycle/reset time in the local
timezone, last successful update, freshness, and refresh action. Unknown pools retain
their slot with `—`; both disabled hides the capsule entirely.

A normal Android **status bar has only a monochrome small icon**. The notification
**drawer** shows the two values; arbitrary colored quota bars cannot be placed inside
the system status bar. Standard notification layout is the reliable baseline:

```text
Cursor Usage · Remaining
Cursor 68% · Other 39%
Resets Oct 31 · Updated 14:32
[Refresh]  [View usage]
```

Lock-screen content hides private values and repository names by default. Usage is a
quiet channel; run completion/failure can use a separate channel. The system controls
small-icon visibility and notification layout. API 33+ requires notification permission.
An overlay is a separate permission-gated surface below the status bar and IME;
it is not a way to replace the system status bar.

## Data contract

GET `https://cursor.com/api/usage-summary` uses the **web session**, not the public
API key. The audit observed a 200 with these fields. The reference client's mapping:

| UI | Source |
| --- | --- |
| Cursor Model used | `individualUsage.plan.autoPercentUsed` |
| Other Model used | `individualUsage.plan.apiPercentUsed` |
| Cycle start/end | `billingCycleStart`, `billingCycleEnd` |
| Unlimited | `isUnlimited === true` |
| Membership label | `membershipType` |

```text
displayUsed = clamp(rawUsed, 0, 100)
remaining = 100 - displayUsed
```

Accept finite numbers and valid numeric strings. Reject empty/null/boolean/non-finite
values. Preserve raw values for overage explanation while clamping geometry.
Do not divide plan.used by plan.limit, convert dollars/tokens, classify by selected
model name, or derive one pool from totalPercentUsed.

With used values 32 and 61, every surface defaults to remaining 68 and 39. Switching
to used changes **numbers, bars, labels, and markers together**. Missing membership
hides the badge. Unlimited displays `∞` without pace/reset countdown. No individual
pools in a team response means unavailable, not invented team percentages.

## Pace and reset behavior

Use UTC timestamps for arithmetic and local timezone for display. `day = 86400000`:

```text
span = cycleEnd - cycleStart
targetUsed = min(1, (floor((now - cycleStart) / day) + 1) * day / span) * 100
delta = usedPercent - targetUsed
```

The marker is the target at the **end of the current billing day**, not local midnight
and not a hard limit. Above +5 percentage points is faster, below −5 is slower,
otherwise on pace. Remaining mode uses `100 - targetUsed` for its marker.
Use a valid 1–32 day server cycle; if deriving the start from the end, subtract a
calendar month with month-end clamping and label the cycle estimated. Missing end,
future start, or invalid cycle suppresses misleading pace. A seven-segment design
means seven equal parts of the whole cycle, not seven days.

When the cycle ends without a new response, preserve old values and show **Waiting
for sync**. Never locally reset to zero. At most one refresh is scheduled for the
same expired end; a new end rearms it. Background scheduling is inexact.

## State matrix

| State | Capsule | Details / notification |
| --- | --- | --- |
| Loading | `···` | Skeleton, not 0% |
| Fresh | Two values | Cycle and successful update time |
| Low remaining | Value and warning | Name the pool and explain threshold/pace |
| One pool absent | `—` in that slot | Other pool stays readable |
| No individual usage | Two unknown values | Explain missing individual pool data |
| Unlimited | `∞` | No pace or reset countdown |
| Offline / failed refresh | Cached values, stale indicator | Exact last successful update and retry |
| Expired cycle | Old values, pending sync | No fabricated new cycle |
| Paused | Pause indicator | Cached data remains; manual refresh allowed |
| Expired authentication | Reconnect | Hide private values and stop retry storms |
| Both pools hidden | Hidden | Explicit preference state, no empty shell |

Authentication failure outranks stale data. 403 must distinguish policy/permission
from an actual expired session. “Pool exhausted” does not mean every request stops;
account on-demand or other-pool policies can still apply. Suggested 20%/10% alerts
are product preferences, not official Cursor rules; deduplicate per pool and cycle.

## Home-screen widgets

Usage, Recent Agents, and Quick Actions have separate resizable home-screen widgets.
They reuse account-scoped cache, usage preferences, freshness, and language.
Widget placement does not require overlay permission. Agent titles are private by
default; enable them explicitly in Settings. The [widget guide](home-screen-widgets.md)
contains size targets, action boundaries, and launcher constraints.

## Local versus account settings

Local DataStore settings: English/Chinese, theme, pool visibility, used/remaining,
pace display, foreground interval, pause, notifications, and optional overlay placement.
Server settings: default model, branch prefix, automatic PR, CI follow-up, egress,
remote control, private workers, and quick actions. These must use the web patch
contract or be explicitly opened on the website; a local toggle cannot pretend to
update the Cursor account. Team locks and unavailable permissions remain visible.

The prototype's navigation is for reviewing usage, settings, and notification states;
it is not a promise that every design control is implemented in the Android release.
For platform restrictions and integration sequencing, read the
[implementation plan](../android-implementation-plan.md).
