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

    // Called when a link was shared to the app (see src/sharereceiver.h
    // for why this is a hand-rolled D-Bus receiver in C++ rather than
    // the stock Sailfish.Share QML ShareProvider). AddBookmarkPage has
    // its own "provide page content manually" toggle, so there is
    // nothing further to decide here.
    function shareInto(url, title) {
        console.log("readeck share: shareInto called url=" + url + " title=" + title)
        if (!readeckClient.isLoggedIn) {
            console.log("readeck share: not logged in, ignoring")
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
            // A share can arrive while the app is behind something else.
            appWindow.activate()
            appWindow.shareInto(url, title)
        }
    }

    // Opening the OAuth login URL lives in QML (Qt.openUrlExternally)
    // rather than C++ QDesktopServices -- see readeckclient.h.
    Connections {
        target: readeckClient
        onOauthLoginUrlReady: Qt.openUrlExternally(url)
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
