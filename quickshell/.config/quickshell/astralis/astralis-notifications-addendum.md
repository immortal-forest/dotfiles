# ASTRALIS — Notifications Addendum
### Extends the astralis Quickshell dynamic-island build (adds Agent I: notifications)

> Standalone add-on to `astralis-quickshell-rice-spec.md`. Covers the notification
> system that the main spec underplayed. Two pieces: **toasts that morph the pill**
> (the island-correct pattern) and a **notification-center surface**. Paste Part B
> into Claude Code as a new sub-agent; it slots in parallel with agents E/F/G and
> depends on the pill engine (Agent D) already existing.

---

## PART A — Implementation doc

For a dynamic island, notifications should not be a separate corner popup — the pill
itself *becomes* the notification, then morphs back. That's the iOS-island behavior and
it reuses the morph engine you already built.

### A.1 Toasts = a `toast` mode of the pill
Add `toast` to `Pill.qml`'s mode ladder, right beside `osd`, positioned **below `held`**
so a pinned or surface-open pill is never interrupted. When a notification arrives the
pill morphs to a toast face — icon tile, app eyebrow, summary, body, action pills,
dismiss glyph — gated on `morphCloseness` exactly like every other face.

- **Auto-expire** ~6s. Snapshot the deadline **once** on `Component.onCompleted`; do not
  bind the timer interval to a live map or an unrelated incoming notification will drift
  or restart every existing toast's lifetime.
- **Critical urgency persists** (no expiry timer).
- **Click body** → `Notifs.activateNotif(n)` + `Notifs.removePopup(n)`.
- **`+N` counter** in a corner when several are queued.
- The toast draws no background of its own — the pill body behind it provides the
  material; the face is just content.

```qml
// inside Pill.qml — mode ladder (excerpt)
readonly property string mode:
      surfaceOpen && surfaces[surface] ? surface
    : held        ? "hover"           // pinned/open never yields to a toast
    : osdActive   ? "osd"
    : toastActive ? "toast"           // ← incoming notification morphs the pill
    : expanded    ? "hover"
    : "rest"
readonly property bool toastActive: Notifs.popups.length > 0

// toast face (stacked, opacity-gated on morphCloseness like the others)
Loader {
  active: pill.toastActive
  anchors.fill: parent
  opacity: pill.mode === "toast" ? Math.pow(pill.morphCloseness, 1.2) : 0
  visible: opacity > 0.01
  sourceComponent: Toast { s: pill.s; notif: Notifs.popups[Notifs.popups.length - 1] }
}
```

```qml
// Toast.qml — deadline snapshotted once, critical persists
property double deadline: 0
Component.onCompleted: deadline = Notifs.expireAt[notif.id] || (Date.now() + 6000)
Timer {
  interval: Math.max(300, root.deadline - Date.now())
  running: root.deadline > 0 && notif.urgency !== NotificationUrgency.Critical
  onTriggered: Notifs.removePopup(root.notif)
}
```

### A.2 Notification center = a surface (`surfaces.notifications`)
History as one more latch-once Loader surface. Group by `appName`, coalesce duplicate
summary/body pairs into a count, sort newest-first, separate criticals, per-app
expand/clear + clear-all. Unread dot on the hover-row inbox icon reads `Notifs.unread`.
Add the IPC verb so a keybind opens it: `qs ipc call pill notifications`.

Adding it is the standard two lines: one `surfaces[]` entry + one Loader (see the main
spec Part 3.3), plus the `IpcHandler` function.

### A.3 Backend — `services/Notifications.qml`
QS owns the freedesktop notification server itself.
```qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
  id: root

  NotificationServer {
    id: server
    keepOnReload: true                 // survive shell hot-reload
    actionsSupported: true
    bodySupported: true
    bodyMarkupSupported: true
    imageSupported: true
    actionIconsSupported: true
    onNotification: (n) => {
      n.tracked = true;                 // keep it alive in trackedNotifications
      root.recordArrival(n);            // arrivalMs[n.id] = Date.now(); push to popups
    }
  }

  readonly property var tracked: server.trackedNotifications.values
  property var popups: []               // currently-showing toasts
  property var history: []              // dismissed/expired backlog
  property var arrivalMs: ({})
  property var seenIds: ({})
  property var expireAt: ({})
  property bool dnd: false

  readonly property int unread: {
    let u = 0;
    for (let i = 0; i < tracked.length; i++) if (!seenIds[tracked[i].id]) u++;
    return u;
  }

  // groups: [{ app, count, newest, preview, criticals[], entries[] }] with duplicate
  //   summary/body coalescing — see Ricelin pill/Singletons/Notifs.qml for the exact
  //   grouping + coalesce() logic to port.

  function iconFor(n) { /* n.image → image://icon/ ; else appIcon/desktopEntry/appName
                           via Quickshell.iconPath(name, true) */ }
  function removePopup(n)   { /* splice from popups, move to history */ }
  function activateNotif(n) { /* n.actions default invoke, or n.expire() */ }
}
```
Consumers: `Notifs.popups` (pill toast face), `Notifs.groups` (center surface),
`Notifs.unread` (inbox dot). Wire DND from your flags:
`Binding { target: Notifs; property: "dnd"; value: Flags.dnd }`.

### A.4 The gotcha that silently kills it
Only **one** process may own the DBus name `org.freedesktop.Notifications`. If
mako / dunst / swaync is running — most often left in a Hyprland `exec-once` — QS's
`NotificationServer` never binds and you get **zero notifications with no error**.
Remove every other notification daemon before testing.

Reference: `Gakuseei/Ricelin` → `configs/quickshell/pill/Singletons/Notifs.qml`
(grouping/coalescing/critical/icon logic) and `configs/quickshell/pill/Toast.qml`
(the toast face). Port these; they're the answer key.

---

## PART B — Paste into Claude Code (new sub-agent)

```
New workstream for the astralis build (extends astralis-quickshell-rice-spec.md).
Read astralis-notifications-addendum.md Part A in full first, then dispatch this as a
sub-agent. It DEPENDS ON Agent D (pill-engine) already existing and runs in PARALLEL
with agents E/F/G. Run it on Claude Fable 5 (model: claude-fable-5). Stop for my
verification when done, same as the other stages.

Agent I — "notifications": [model: claude-fable-5]
  Build the notification system for the dynamic-island pill:

  1. services/Notifications.qml — a singleton wrapping Quickshell.Services.Notifications
     NotificationServer (keepOnReload: true; actionsSupported, bodySupported,
     bodyMarkupSupported, imageSupported, actionIconsSupported all true). Expose:
     tracked, popups[], history[], unread, dnd, groups (app-grouped + duplicate
     summary/body coalesced into counts, newest-first, criticals separated), iconFor(n)
     (via Quickshell.iconPath), removePopup(n), activateNotif(n). Bind dnd from Flags.
     Port the grouping/coalesce logic from Gakuseei/Ricelin pill/Singletons/Notifs.qml.

  2. Pill.qml — add a `toast` face to the mode ladder, positioned BELOW `held` so a
     pinned/open pill is never interrupted, and gated on morphCloseness like every other
     face. Toast content (port Ricelin pill/Toast.qml): icon tile, app eyebrow, summary,
     body, action pills, dismiss glyph. Auto-expire ~6s with the deadline SNAPSHOTTED
     ONCE on Component.onCompleted (do not bind interval to a live map). Critical urgency
     persists (no timer). Click body → activateNotif + removePopup. Show a +N counter
     when popups.length > 1. Read Notifs.popups.

  3. Hover row — add the inbox icon with an unread dot bound to Notifs.unread.

  4. Notification-center surface — surfaces.notifications as a latch-once Loader
     (one surfaces[] entry + one Loader + IpcHandler verb `notifications`): grouped,
     coalesced history reading Notifs.groups, per-app expand, clear / clear-all,
     newest-first, criticals surfaced. Colors from the Colors singleton, motion from
     the Motion singleton — no hard-coded values.

  CRITICAL FIRST STEP: check my Hyprland exec-once and running processes for any other
  notification daemon (mako, dunst, swaync). If present, tell me and remove it — QS's
  NotificationServer cannot bind the DBus name otherwise and notifications silently fail.

  VERIFY: `notify-send "Test" "body"` → pill morphs into a toast and expires ~6s;
  `notify-send -u critical …` persists until dismissed; several at once show +N; the
  center surface (via `qs ipc call pill notifications`) lists grouped/coalesced history
  with working clear; the inbox unread dot tracks count; everything recolors on retheme.
```

---

### One decision for you
Toasts-in-the-pill (above) is the island-correct default. If you'd rather have toasts as
a **separate top-corner popup window** (more conventional, doesn't tie up the pill while
you're mid-hover), say so and I'll swap Part A.1 for a standalone `NotificationToasts`
PanelWindow on `WlrLayer.Overlay` instead — the backend singleton and center surface stay
identical, only the toast presentation changes.
