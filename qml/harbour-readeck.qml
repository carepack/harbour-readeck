import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow {
    id: appWindow

    initialPage: Qt.resolvedUrl(readeckClient.isLoggedIn ? "pages/BookmarksPage.qml" : "pages/LoginPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Warms Qt's image cache for the cover's article image while the app
    // is still in the foreground and actually rendering. The cover
    // (cover/CoverPage.qml) shares this same QML engine/image cache, but
    // it is only painted once, at the moment the app is backgrounded --
    // if the cover's own Image is still downloading/decoding at that
    // instant (freshly changed after an auto-refresh, e.g. right after
    // adding a bookmark), that single paint misses it and the old image
    // sticks until the next full foreground/background cycle gives the
    // cover another chance to paint. Loading the same URL here, in the
    // window that keeps rendering, means it is already cached by the
    // time the user backgrounds the app.
    Image {
        visible: false
        asynchronous: true
        source: readeckClient.coverBookmarks.length > 0
            ? (readeckClient.coverBookmarks[readeckClient.coverIndex].imageUrl || "")
            : ""
    }

    // Set while a share arrived before readeckClient.isLoggedIn became
    // true -- e.g. a cold D-Bus-activated start where restoreSession()
    // is still waiting on an interactive Secrets unlock. Consumed by
    // onLoginSucceeded below once that resolves, instead of the share
    // being silently lost.
    property string pendingShareUrl: ""
    property string pendingShareTitle: ""

    // Delivers a share/open link that was queued during login, strictly
    // after the login-success signal's synchronous slot calls have all
    // returned. LoginPage.qml listens to the same readeckClient
    // loginSucceeded signal to replace itself with BookmarksPage; Qt
    // calls connected slots in connection order, and this window's own
    // Connections exists (and so connects) before LoginPage is even
    // loaded, so without this deferral the two race -- the save dialog
    // gets pushed first, then LoginPage's replace() clobbers it right
    // back off the stack (confirmed live on-device). interval: 0 defers
    // to the next event-loop pass, after every synchronous listener
    // (including LoginPage's replace) has already run.
    Timer {
        id: pendingShareDeliveryTimer
        interval: 0
        property string url: ""
        property string title: ""
        onTriggered: appWindow.shareInto(url, title)
    }

    // Retries shareInto() shortly when the page stack hasn't finished
    // loading its initialPage yet -- confirmed live: a D-Bus-delivered
    // Open()/share call can be processed (isLoggedIn already true, no
    // interactive unlock needed) before Silica's own initialPage has
    // loaded, landing the push on an empty stack (pageStack.depth went
    // to 1 from 0, not 2) where it then gets silently overwritten the
    // moment initialPage actually loads. Polling is the only option --
    // there's no public "page stack ready" signal to wait on instead.
    Timer {
        id: pageStackRetryTimer
        interval: 50
        property string url: ""
        property string title: ""
        onTriggered: appWindow.shareInto(url, title)
    }

    // Called when a link was shared to the app (see src/sharereceiver.h
    // for why this is a hand-rolled D-Bus receiver in C++ rather than
    // the stock Sailfish.Share QML ShareProvider). AddBookmarkPage has
    // its own "provide page content manually" toggle, so there is
    // nothing further to decide here.
    function shareInto(url, title) {
        console.log("readeck share: shareInto called url=" + url + " title=" + title)
        if (!readeckClient.isLoggedIn) {
            console.log("readeck share: not logged in yet, queuing until login completes")
            pendingShareUrl = url
            pendingShareTitle = title
            return
        }
        if (!shareReceiver.pageStackReady || pageStack.busy) {
            // pageStackReady alone isn't enough -- it's set once the
            // initial page reaches PageStatus.Active (Component.onCompleted
            // fires too early, confirmed live: Silica's own "cannot push
            // while transition is in progress" warning fired when a push
            // raced that transition). busy guards every later transition
            // too, e.g. LoginPage's own replace() to BookmarksPage on
            // login success, which is a second, separate transition this
            // push could just as easily race.
            console.log("readeck share: page stack not ready yet, retrying")
            pageStackRetryTimer.url = url
            pageStackRetryTimer.title = title
            pageStackRetryTimer.start()
            return
        }
        pageStack.push(Qt.resolvedUrl("pages/AddBookmarkPage.qml"), {
            initialUrl: url,
            initialTitle: title
        })
        console.log("readeck share: pageStack.push done, depth=" + pageStack.depth)
    }

    Connections {
        target: shareReceiver
        onBookmarkShared: {
            console.log("readeck share: QML onBookmarkShared received url=" + url + " title=" + title)
            // A share (or an opened link, routed through the same signal
            // per KTD2) can arrive while the app is behind something else.
            appWindow.activate()
            appWindow.shareInto(url, title)
        }
        // A plain org.freedesktop.Application Activate() call (e.g. a
        // normal launch via the system once X-DBusActivatable=true is
        // set, with no link to open) -- just raise the window.
        onActivateRequested: appWindow.activate()
    }

    Connections {
        target: readeckClient
        // Opening the OAuth login URL lives in QML (Qt.openUrlExternally)
        // rather than C++ QDesktopServices -- see readeckclient.h.
        onOauthLoginUrlReady: Qt.openUrlExternally(url)

        // Fires on manual login and on a background Secrets unlock
        // completing -- either way, deliver a share that arrived too
        // early instead of leaving it stuck in pendingShareUrl forever.
        onLoginSucceeded: {
            if (pendingShareUrl.length === 0) {
                return
            }
            pendingShareDeliveryTimer.url = pendingShareUrl
            pendingShareDeliveryTimer.title = pendingShareTitle
            pendingShareUrl = ""
            pendingShareTitle = ""
            pendingShareDeliveryTimer.start()
        }
    }

    Connections {
        target: Qt.application
        onActiveChanged: {
            if (!Qt.application.active) {
                return
            }

            // A share sometimes only works once per app run, then needs
            // the app force-closed before it works again -- the app's
            // D-Bus name appears to get dropped (e.g. after losing
            // focus) with nothing re-claiming it. Re-registering here is
            // idempotent and cheap, so it costs nothing to do on every
            // foreground transition as a defensive measure.
            shareReceiver.registerService()

            // The user may have just finished (or abandoned) the OAuth
            // login's browser step; the poll timer can miss ticks while
            // backgrounded, so check immediately on return rather than
            // waiting for its next scheduled tick.
            if (readeckClient.oauthInProgress) {
                readeckClient.pollOAuthLogin()
            }

            // Refresh on every foreground transition -- cover tap, icon
            // tap, or being brought forward for a share -- so the cover
            // and an already-open bookmarks list never show stale data.
            if (readeckClient.isLoggedIn) {
                readeckClient.refreshUnreadCount()
                readeckClient.loadCoverBookmarks()
                if (pageStack.currentPage && pageStack.currentPage.reload) {
                    pageStack.currentPage.reload()
                }
            }

            // If the user browsed to an article via the cover's "next"
            // action and then taps the cover (or reopens the app) to
            // read it, jump straight there. coverSelectionPending is a
            // one-shot flag set by coverNext() and consumed here, so a
            // plain app resume never forces navigation on its own.
            if (!readeckClient.coverSelectionPending) {
                return
            }
            readeckClient.coverSelectionPending = false
            var items = readeckClient.coverBookmarks
            var item = items[readeckClient.coverIndex]
            if (item && item.id) {
                pageStack.push(Qt.resolvedUrl("pages/BookmarkDetailPage.qml"), {
                    bookmarkId: item.id,
                    initialTitle: item.title,
                    initialUrl: item.url,
                    initialSiteName: item.site_name,
                    initialIsMarked: item.is_marked,
                    initialIsArchived: item.is_archived,
                    initialReadingTime: item.reading_time
                })
            }
        }
    }
}
