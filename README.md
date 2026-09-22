# harbour-readeck

An unofficial, open-source [Sailfish OS](https://sailfishos.org/) client for
[Readeck](https://readeck.org), the self-hosted read-it-later / bookmark
application. Native QML + C++ app built with `Sailfish.Silica`.

- Sign in via Readeck's browser-based OAuth2 device-code flow (Readeck
  0.21+), with a manual personal-API-token fallback for older servers
- Browse bookmarks with **Unread / Favorites / Archive / All** filters,
  full-text search, pull-down refresh and infinite scroll — swipe
  left/right anywhere in the list to move between filters, carousel-style
- Native reader view — article HTML rendered directly (no WebView), with
  code blocks and long inline code runs pulled into their own
  horizontally-scrollable monospace boxes so they never overflow the
  screen, and images scaled to fit
- Tap an image in an article to open it full-screen with pinch-to-zoom and
  double-tap-to-zoom
- Toggle favorite / archive, delete, open the original URL in the browser
- Export an article as a formatted, paginated PDF (A4), with images
  embedded and a save-location picker covering Downloads/Documents/
  Pictures/Videos/Music/Public
- Article info page lists the original source and every link found in the
  article body; long-press any of them to copy the link
- Save a new bookmark via the pulley menu, via Sailfish's share sheet from
  any other app, or by capturing a page's rendered content through an
  embedded browser (useful for pages that need a login or JS rendering
  behind Readeck's own fetcher)
- Cover page shows the current unread count and the latest article's image
- Automatically follows the system language (German and English so far;
  falls back to English for anything else)

## Project layout

```
src/                  C++ backend (ReadeckClient REST client, BookmarkListModel, ShareReceiver)
qml/pages/            LoginPage, BookmarksPage, BookmarkDetailPage, BookmarkInfoPage,
                       ImageViewerPage, PdfLocationDialog, AddBookmarkPage,
                       CaptureContentPage, SettingsPage
qml/components/       BookmarkDelegate
qml/cover/            CoverPage
rpm/                  RPM spec + changelog
icons/                86/108/128/172 px app icons, plus a 256px store icon
translations/         harbour-readeck-de.ts (German; English is the source language)
```

## Building

```sh
cd harbour-readeck
sfdk config target SailfishOS-5.1.0.11-armv7hl   # or any installed target
sfdk build
```

Deploy to a device or the SDK emulator:

```sh
sfdk device list
sfdk config device "My Phone"
sfdk deploy --sdk
```

CI: `.github/workflows/build.yml` builds RPMs for armv7hl/aarch64 on every
push via [CODeRUS/github-sfos-build](https://github.com/CODeRUS/github-sfos-build).

## Readeck API notes

- Base URL: `<server>/api`
- OAuth2 device-code flow ([Readeck docs](https://readeck.org/en/docs/external-auth)):
  dynamic client registration (`POST /api/oauth/client`), device
  authorization (`POST /api/oauth/device`), polling token exchange
  (`POST /api/oauth/token`), revocation on sign-out (`POST /api/oauth/revoke`).
  Clients are ephemeral and re-register on every login. The manual-token
  fallback sends `Authorization: Bearer <token>` and verifies it against
  `GET /api/profile`.
- Bookmarks: `GET /api/bookmarks` (filters: `is_archived`, `is_marked`,
  `search`, pagination via `limit`/`offset`, total count in the
  `Total-Count` response header), `POST /api/bookmarks` to save a new URL,
  `PATCH /api/bookmarks/{id}` to update `is_marked`/`is_archived`/labels/etc.,
  `DELETE /api/bookmarks/{id}`, `GET /api/bookmarks/{id}/article` for the
  cleaned article HTML fragment.
- Bookmark IDs are server-generated and constrained server-side to
  `[a-zA-Z0-9]{18,22}`, so they can never contain URL-special characters —
  `ReadeckClient` still percent-encodes them before splicing into request
  paths as defense in depth.
- The session (OAuth access token or manual token) is stored in the app's
  private `QSettings` (ini file under
  `~/.config/harbour-readeck/harbour-readeck.conf` inside the Sailjail
  sandbox) — plaintext, same trust model most FOSS Readeck clients use.
  Sailfish Secrets-backed storage would be a good follow-up.

## Before publishing to Harbour/Chum

- Rename `rpm/harbour-readeck.changes.in` → `harbour-readeck.changes` (or
  wire up `harbour-readeck.changes.run`).
