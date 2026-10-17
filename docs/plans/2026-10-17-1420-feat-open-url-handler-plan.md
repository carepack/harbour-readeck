---
title: Open URL Handler - Plan
type: feat
date: 2026-10-17
topic: open-url-handler
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-brainstorm
execution: code
---

# Open URL Handler

**Target repos:** harbour-readeck (this file's home) and harbour-nextmarks. Each unit states which repo it targets; all paths are relative to that unit's own repo root.

## Goal Capsule

- **Objective:** A link encountered anywhere on the device that offers a system "open with" chooser (not only apps with a Share action -- e.g. the Camera app's scanned-barcode link) can be opened directly into harbour-readeck or harbour-nextmarks, landing in the same pre-filled save dialog a shared link already reaches.
- **Means:** Register both apps as system handlers for `http`/`https` links (desktop file `MimeType`), and implement the standard `org.freedesktop.Application` D-Bus `Open` method on each app's existing share D-Bus service so a tap routes into the existing share-handling flow. (KTD1, KTD2)
- **Product authority:** Covers both harbour-readeck and harbour-nextmarks identically -- same mechanism, same decision, applied once per repo. Each repo ships and reviews independently.
- **Open blockers:** None.

## Product Contract

### Summary

Both apps register as system link handlers for `http`/`https` URLs and implement the D-Bus activation interface the system uses to deliver a tapped link. An opened link is funneled into the exact same pre-filled save dialog the existing Share flow already uses, including the queueing fix for a session that is still unlocking.

### Problem Frame

Today the only way a link reaches either app is the Sailfish Share sheet, which an app must explicitly offer. Sources that have no Share action but do offer a system "open with" chooser -- the Camera app's scanned-barcode link being the concrete case that surfaced this -- cannot reach either app at all, even though saving the link is exactly what the user wants to do.

### Requirements

**Registration**

- R1. Both apps' desktop files declare `MimeType=text/html;x-scheme-handler/https;x-scheme-handler/http;`, making them candidates in the system's link-opener chooser everywhere such a chooser appears, not only the barcode scanner.
- R2. Both apps declare `X-DBusActivatable=true` in their desktop file. No new `.service` file or `ExecDBus=` override is needed: each app's existing D-Bus service file already D-Bus-activates the same `main()` entry point a normal launch uses, and that entry point already registers the share D-Bus service unconditionally on every start -- the new interface (R3) registers alongside it.
- R3. Both apps implement the standard `org.freedesktop.Application` D-Bus interface (`Open(QStringList uris, QVariantMap platformData)`), at the object path the spec derives from each app's existing D-Bus service name (dots to slashes, dashes to underscores -- see KTD1), reusing that same running service rather than a second one.

**Behavior**

- R4. Covers R1-R3. An opened URL is delivered to the same function the existing Share flow already uses (`shareInto()` in both apps), including the pending-share queue that waits for an in-progress Secrets unlock before delivering it (`fix/share-before-login`, both repos).
- R5. Opening a link when the app is already running brings it to the foreground with no extra confirmation step before the save dialog appears, matching how Share already behaves.

### Key Decisions

- **Open is routed through the existing Share path, not a new flow.** (session-settled: user-directed -- chosen over a distinct "open and view" behavior: confirmed in dialogue that opening a link should mean the same thing as sharing it.) Governs R4, R5.
- **One D-Bus service, two interfaces, reusing the existing invoker-based `.service` file.** (session-settled: user-approved -- chosen over a second D-Bus service or a custom `ExecDBus=`/`--dbus` launch flag: confirmed during planning that the existing service file already D-Bus-activates the same `main()`, which already registers the share service unconditionally.) Governs R2, R3.

### How This Work Fits Together

<!-- ce-section: work-relationships -->

This plan covers one area: making both apps system link handlers. It does not depend on and is not blocked by the other currently open work in either repo (Secrets, rename-folder, edit-bookmark, copy-link, capture-labels-lost) -- those can land before or after this one.

- Depends on the share-before-login queueing fix already written in both repos (`fix/share-before-login` branches) -- R4 reuses that queue rather than re-solving it.

### Key Flows

- F1. Open a link from the system chooser, app not running
  - **Trigger:** User picks the app from the system's "open with" list for an `http`/`https` link (e.g. after tapping a scanned barcode's link).
  - **Steps:** System D-Bus-activates the app via its existing `.service` file -> `main()` starts, registers both D-Bus interfaces on the same service -> the `Open` call resolves to a URL -> routed into `shareInto()` -> if logged in, the pre-filled save dialog opens; if not yet (session still unlocking), the URL is queued per R4.
  - **Covers:** R1, R2, R3, R4

- F2. Open a link from the system chooser, app already running
  - **Trigger:** Same as F1, app is already in the foreground/background.
  - **Steps:** The already-running process receives the `Open` call on its existing D-Bus connection -> window activates -> `shareInto()` runs immediately (app is already past the login-unlock window in the common case).
  - **Covers:** R3, R4, R5

### Acceptance Examples

- AE1. **Covers R4.** Given the app is logged in and already running, when a link is opened from the system chooser, then the save dialog opens pre-filled with that URL, with no confirmation step.
- AE2. **Covers R4.** Given the app was cold-started by this open (Secrets collection still locked), when the link arrives before login completes, then it is queued and the save dialog opens automatically once login succeeds, instead of the link being lost.
- AE3. **Covers R1.** Given the app is installed, when the user taps any `http`/`https` link anywhere the system offers an "open with" chooser, then the app appears as one of the options -- this is not scoped to the barcode scanner specifically, since the registration is link-type-based, not source-based.

### Scope Boundaries

- Scoping the chooser registration to only barcode-scanned links is not possible with this mechanism (MIME/scheme registration is source-agnostic) and is not attempted; AE3 states this plainly instead.
- No new "are you sure you want to open this in Readeck/Nextmarks" confirmation step -- deferred, since Share has none today and the settled decision treats Open the same way.
- Viewing/reading the link's content directly instead of saving it first is out of scope -- the settled decision routes Open through the existing save flow, not a new one.

### Sources / Research

- Confirmed working reference implementation: [harbour-tooter](https://github.com/poetaster/harbour-tooter) (`harbour-tooterb.desktop`, `src/harbour-tooterb.cpp`, `src/dbusAdaptor.h`) -- a published Harbour app that already registers this way and implements `org.freedesktop.Application.Open`. Its separate `harbour-tooterb-open-url.desktop`/`X-Maemo-*` registration is legacy and commented out in the active desktop file, as is an earlier standalone `Dbus` class in `src/dbus.cpp` (superseded by the live registration directly in `main()`); neither is followed here.
- Authoritative mechanism spec: [freedesktop.org Desktop Entry Specification, "D-Bus Activation"](https://specifications.freedesktop.org/desktop-entry-spec/1.3/ar01s08.html) -- object path = `/` + service name with `.` -> `/` and `-` -> `_`; required interface methods `Activate`, `Open`, `ActivateAction`.
- Existing D-Bus share infrastructure to extend: `src/sharereceiver.h`/`.cpp` (both repos) -- `ShareReceiver::registerService()` already does `bus.registerObject("/share/link", m_target)` then `bus.registerService("harbour-readeck.harbour-readeck")` (readeck) / `"harbour-nextmarks.harbour-nextmarks"` (nextmarks); `ShareAdaptor` is the existing `QDBusAbstractAdaptor` pattern to mirror. `src/main.cpp` calls `shareReceiver.registerService()` unconditionally before `view->show()`.
- Existing D-Bus service files confirmed already invoker-based, no change needed: `dbus/harbour-readeck.harbour-readeck.service`, equivalent in harbour-nextmarks.
- Existing desktop files already carry a working `[X-Sailjail]` section and `X-Share-Methods` registration to extend: `harbour-readeck.desktop`, `harbour-nextmarks.desktop`.

---

## Planning Contract

### Key Technical Decisions

- KTD1. **D-Bus object path derived per the freedesktop spec's dot/dash substitution rule, not a hand-picked path.** readeck: service `harbour-readeck.harbour-readeck` -> object path `/harbour_readeck/harbour_readeck`. nextmarks: service `harbour-nextmarks.harbour-nextmarks` -> object path `/harbour_nextmarks/harbour_nextmarks`. Governs R3.
- KTD2. **New adaptor class reuses `ShareReceiver`'s existing `bookmarkShared(url, title)` signal instead of introducing a second signal.** QML's existing `Connections { target: shareReceiver; onBookmarkShared: ... }` handler (and the share-before-login queueing logic that already lives in `shareInto()`) needs no changes -- only `ShareReceiver` gains a second registered object/interface that emits the same signal. (session-settled: user-approved -- chosen over a parallel `urlOpened` signal plus a second QML handler: keeps QML untouched and avoids duplicating the queueing logic R4 depends on.) Governs R3, R4.
- KTD3. **`Open`'s `uris` list is reduced to its first `http`/`https` entry; anything else in the list is ignored.** The spec allows multiple URIs per call; this app's save flow handles one URL at a time, matching how Share already behaves (single resource). Governs R3, R4.

### Assumptions

- The system's "open with" chooser enumerates desktop files by `MimeType` the same way it does for the existing `X-Share-Methods` registration -- both are standard freedesktop/Sailfish desktop-file mechanisms, and R1 only changes which chooser surfaces the app, not how either mechanism is read. Verified at implementation time by the manual device check in each repo's Unit verification.

---

## Implementation Units

### U1. Add the `org.freedesktop.Application` interface to `ShareReceiver` (harbour-readeck)

- **Goal:** `ShareReceiver` registers a second D-Bus object implementing `Open(QStringList uris, QVariantMap platformData)` on the same service, emitting the existing `bookmarkShared` signal for the first `http`/`https` URI.
- **Requirements:** R2, R3, R4, R5. KTD1, KTD2, KTD3.
- **Dependencies:** None.
- **Files:**
  - `src/sharereceiver.h` -- declare the new adaptor class and the object path constant; add a private method on `ShareReceiver` to handle an incoming `Open` call.
  - `src/sharereceiver.cpp` -- register the new object at `/harbour_readeck/harbour_readeck` inside `registerService()` (same method, after the existing `/share/link` registration and before `registerService(...)` claims the bus name, matching the existing ordering comment); implement the handler: pick the first URI whose scheme is `http`/`https`, extract an optional title from `platformData` if present, then route through the same `m_ready`/pending-queue logic `handleShare()` already uses (reuse that logic directly rather than duplicating it -- consider extracting the shared "deliver or queue" step both handlers call).
- **Approach:**
  1. Add an `AppActivationAdaptor : public QDBusAbstractAdaptor` class (same shape as the existing `ShareAdaptor`) with `Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application")` and a `Q_NOREPLY void Open(const QStringList &uris, const QVariantMap &platformData)` slot.
  2. In `ShareReceiver::registerService()`, create a second target `QObject` (or reuse `m_target` if one object can carry both adaptors -- `QDBusAbstractAdaptor` children attach to a `QObject`, and `registerObject` is called once per distinct path, so two separate target objects, one per path, is the simpler shape to follow the existing pattern), attach the new adaptor, and `bus.registerObject("/harbour_readeck/harbour_readeck", ...)`.
  3. Add `ShareReceiver::handleOpenUrl(const QString &url)` (or inline in the adaptor callback) that reuses the exact "if `m_ready`, emit now; else set `m_pendingUrl`/`m_hasPending`" logic `handleShare()` already has -- factor that shared block into one private helper both call, rather than copying it.
- **Patterns to follow:** `ShareAdaptor`/`ShareReceiver::handleShare()` (`src/sharereceiver.h`/`.cpp`) for the adaptor-plus-handler shape; `src/main.cpp`'s existing unconditional `shareReceiver.registerService()` call needs no change since this unit's registration lives inside that same method.
- **Test scenarios:**
  - Happy path: `Open(["https://example.com/article"], {})` while `m_ready` is true emits `bookmarkShared("https://example.com/article", "")` immediately. Covers AE1.
  - Happy path: same call while `m_ready` is false sets the pending state instead of emitting, and `setReady()` afterward flushes it -- matching `handleShare()`'s existing queued-share behavior. Covers AE2.
  - Edge case: `uris` contains a non-http(s) scheme first (e.g. `mailto:...`) followed by an `https://` URL -- the https one is used, not the first list entry verbatim.
  - Edge case: `uris` is empty -- no signal emitted, no crash (`Q_NOREPLY` means no error can be returned to the caller, so this must fail silently the same way `handleShare()`'s empty-resources case does).
  - Integration: a real D-Bus `Open` call (via `qdbus`/`gdbus call` against the running service) while the app is already foregrounded brings the window to front and opens the pre-filled save dialog. Covers AE1.
- **Verification:** Build succeeds. Manually confirmed on a real device: (a) the app appears in the system "open with" chooser for an `http`/`https` link once installed (confirms R1, which ships with this unit's desktop-file counterpart in U2); (b) tapping it from a cold start lands in the pre-filled save dialog; (c) tapping it while the app is already open brings it to the foreground with the same dialog, no confirmation step.

### U2. Desktop file registration (harbour-readeck)

- **Goal:** `harbour-readeck.desktop` declares the MIME types and D-Bus-activatable flag needed for the system chooser to list the app and activate it via U1's interface.
- **Requirements:** R1, R2.
- **Dependencies:** U1 (the interface must exist before advertising D-Bus activation for it makes sense, though the two can be reviewed together).
- **Files:** `harbour-readeck.desktop`.
- **Approach:** Add `MimeType=text/html;x-scheme-handler/https;x-scheme-handler/http;` and `X-DBusActivatable=true` to the `[Desktop Entry]` section, alongside the existing `X-Share-Methods=link` line (both registrations coexist; neither replaces the other).
- **Patterns to follow:** The existing `X-Share-Methods=link` + `[X-Share Method link]` block in the same file shows the established style for this file.
- **Test scenarios:** `Test expectation: none -- pure declarative config, no behavior of its own; its effect is exercised by U1's device-verification steps.`
- **Verification:** `desktop-file-validate harbour-readeck.desktop` (already run by the existing `desktop-file-install` build step) passes; U1's on-device chooser check confirms the entry is picked up.

### U3. Add the `org.freedesktop.Application` interface to `ShareReceiver` (harbour-nextmarks)

- **Goal:** Mirrors U1 for harbour-nextmarks: `ShareReceiver` registers `Open` at `/harbour_nextmarks/harbour_nextmarks` on the `harbour-nextmarks.harbour-nextmarks` service, routing into the existing `shareInto()`/pending-share queue via the `bookmarkShared` signal.
- **Requirements:** R2, R3, R4, R5. KTD1, KTD2, KTD3.
- **Dependencies:** None (independent of U1/U2 -- separate repo).
- **Files:** `src/sharereceiver.h`, `src/sharereceiver.cpp` (harbour-nextmarks).
- **Approach:** Identical to U1's three steps, with the nextmarks service name and object path substituted.
- **Patterns to follow:** Same as U1, within harbour-nextmarks' own `src/sharereceiver.h`/`.cpp`.
- **Test scenarios:** Same five scenarios as U1, against harbour-nextmarks' `ShareReceiver` and `shareInto()`.
- **Verification:** Same as U1's verification, run against harbour-nextmarks.

### U4. Desktop file registration (harbour-nextmarks)

- **Goal:** Mirrors U2 for harbour-nextmarks.
- **Requirements:** R1, R2.
- **Dependencies:** U3.
- **Files:** `harbour-nextmarks.desktop`.
- **Approach:** Same as U2: add `MimeType=` and `X-DBusActivatable=true` alongside the existing `X-Share-Methods=link` block.
- **Patterns to follow:** Same file's existing `X-Share-Methods=link` block.
- **Test scenarios:** `Test expectation: none -- pure declarative config; exercised by U3's device-verification steps.`
- **Verification:** Same as U2, run against harbour-nextmarks.

---

## Verification Contract

Neither repo has an automated test suite (confirmed throughout prior work this session) -- verification is build success plus the manual device scenarios each unit lists.

| Check | Applies to | Command / method |
|---|---|---|
| Build | U1-U4 | `sfdk build -d` (both repos) |
| Desktop file validity | U2, U4 | `desktop-file-validate <name>.desktop` (already part of the existing build's `desktop-file-install` step) |
| On-device chooser + open flow | U1-U4 | Manual: install the built RPM, tap a scanned-barcode link (or any `http`/`https` link elsewhere the system offers a chooser), confirm the app is listed, confirm tapping it opens the pre-filled save dialog, both cold-start and already-running |

## Definition of Done

- U1-U4 complete and built successfully on both repos.
- The manual on-device verification in U1/U3 passed for both apps: app appears in the system link chooser, opening a link (cold start and already-running) lands in the pre-filled save dialog with no confirmation step, and a link opened during an in-progress Secrets unlock is not lost.
- No leftover dead code from the shared "deliver or queue" extraction mentioned in U1/U3's Approach if that refactor was attempted and abandoned.
