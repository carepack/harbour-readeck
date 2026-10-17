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

## Goal Capsule

- **Objective:** A link encountered anywhere on the device that offers a system "open with" chooser (not only apps with a Share action -- e.g. the Camera app's scanned-barcode link) can be opened directly into harbour-readeck or harbour-nextmarks, landing in the same pre-filled save dialog a shared link already reaches.
- **Means:** Register both apps as system handlers for `http`/`https` links (desktop file `MimeType`), and implement the standard `org.freedesktop.Application` D-Bus `Open` method so a tap routes into the existing share-handling flow.
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
- R2. Both apps declare `X-DBusActivatable=true` and an `ExecDBus=` line in `[X-Sailjail]`, so picking the app from the chooser can cold-start it via D-Bus activation.
- R3. Both apps implement the standard `org.freedesktop.Application` D-Bus interface (`Open(QStringList uris, QVariantMap platformData)` at object path `/`), reusing the Sailjail-derived `OrganizationName.ApplicationName` service identity each app's existing `ShareReceiver` already owns -- one running process, a second interface on it, not a second service.

**Behavior**

- R4. Covers R1-R3. An opened URL is delivered to the same function the existing Share flow already uses (`shareInto()` in both apps), including the pending-share queue that waits for an in-progress Secrets unlock before delivering it (see `fix/share-before-login`, both repos).
- R5. Opening a link when the app is already running brings it to the foreground with no extra confirmation step before the save dialog appears, matching how Share already behaves.

### Key Decisions

- **Open is routed through the existing Share path, not a new flow.** (session-settled: user-directed -- chosen over a distinct "open and view" behavior: confirmed in dialogue that opening a link should mean the same thing as sharing it.) Governs R4, R5.
- **One D-Bus service, two interfaces.** The new `org.freedesktop.Application` interface is added to the process each app's existing share D-Bus service already runs, rather than standing up a second service. Governs R3.

### How This Work Fits Together

<!-- ce-section: work-relationships -->

This plan covers one area: making both apps system link handlers. It does not cover and is not blocked by the other currently open work in either repo (the Secrets, rename-folder, edit-bookmark, copy-link, share-before-login, and capture-labels-lost branches) -- those can land before or after this one.

- Depends on the share-before-login queueing fix already written in both repos (uncommitted-plan-time state: `fix/share-before-login` branches) -- R4 reuses that queue rather than re-solving it.

### Key Flows

- F1. Open a link from the system chooser, app not running
  - **Trigger:** User picks the app from the system's "open with" list for an `http`/`https` link (e.g. after tapping a scanned barcode's link).
  - **Steps:** System D-Bus-activates the app via its `.service` file -> app starts, registers both D-Bus interfaces -> the `Open` call (or the launch argument, whichever arrives) resolves to a URL -> routed into `shareInto()` -> if logged in, the pre-filled save dialog opens; if not yet (session still unlocking), the URL is queued per R4.
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

- Confirmed working reference implementation: [harbour-tooter](https://github.com/poetaster/harbour-tooter) (`harbour-tooterb.desktop`, `src/dbus.cpp`, `src/dbusAdaptor.h`, `config/de.poetaster.harbour.tooterb.service`) -- a published Harbour app that already registers this way and implements `org.freedesktop.Application.Open`.
- Existing D-Bus share infrastructure to extend, not duplicate: `src/sharereceiver.h`/`.cpp` (harbour-readeck and harbour-nextmarks) -- single-instance handling, cold-start queuing pattern (`setReady()`/pending state), `QDBusAbstractAdaptor`-based adaptor class.
- Existing desktop files: `harbour-readeck.desktop`, `harbour-nextmarks.desktop` -- both already carry a working `[X-Sailjail]` section and `X-Share-Methods` registration to extend.
