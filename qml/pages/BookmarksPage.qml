import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.readeck 1.0
import "../components"

Page {
    id: page
    allowedOrientations: Orientation.All

    property string currentFilter: "unread"
    property string searchText: ""
    property int offset: 0
    property bool hasMore: true
    property bool _loaded: false

    readonly property var categoryKeys: ["unread", "favorites", "archive", "all"]

    function nextCategory() {
        var idx = (categoryKeys.indexOf(currentFilter) + 1) % categoryKeys.length
        setFilter(categoryKeys[idx])
    }

    function prevCategory() {
        var idx = (categoryKeys.indexOf(currentFilter) - 1 + categoryKeys.length) % categoryKeys.length
        setFilter(categoryKeys[idx])
    }

    function reload() {
        offset = 0
        hasMore = true
        readeckClient.loadBookmarks(currentFilter, searchText, 0, true)
    }

    function loadMore() {
        if (!hasMore || readeckClient.busy) {
            return
        }
        offset += 30
        readeckClient.loadBookmarks(currentFilter, searchText, offset, false)
    }

    function setFilter(filterName) {
        if (currentFilter === filterName) {
            return
        }
        currentFilter = filterName
        reload()
    }

    onStatusChanged: {
        if (status === PageStatus.Active && !_loaded) {
            _loaded = true
            reload()
            readeckClient.refreshUnreadCount()
            readeckClient.loadCoverBookmarks()
        }
    }

    Connections {
        target: readeckClient

        onBookmarksReceived: {
            if (reset) {
                bookmarkModel.resetItems(items)
            } else {
                bookmarkModel.appendItems(items)
            }
            hasMore = bookmarkModel.count < totalCount
        }

        onBookmarksFailed: {
            //: Placeholder shown when the bookmark list could not be loaded
            errorBanner.text = message
            errorBanner.visible = true
        }

        onBookmarkUpdated: {
            bookmarkModel.updateItem(bookmarkId, changes)
            readeckClient.refreshUnreadCount()
            readeckClient.loadCoverBookmarks()
        }

        onBookmarkUpdateFailed: {
            errorBanner.text = message
            errorBanner.visible = true
        }

        onBookmarkDeleted: {
            bookmarkModel.removeItem(bookmarkId)
            readeckClient.refreshUnreadCount()
            readeckClient.loadCoverBookmarks()
        }

        onBookmarkDeleteFailed: {
            errorBanner.text = message
            errorBanner.visible = true
        }

        onBookmarkCreated: {
            reload()
            readeckClient.refreshUnreadCount()
            readeckClient.loadCoverBookmarks()
        }

        onBookmarkCreateFailed: {
            errorBanner.text = message
            errorBanner.visible = true
        }
    }

    BookmarkListModel { id: bookmarkModel }

    // Horizontal-only gesture detector wrapping the real page content,
    // which stays put and only ever scrolls vertically as normal --
    // Qt Quick resolves a drag on nested Flickables to whichever one's
    // configured axis it actually matches, so a vertical drag here
    // passes straight through untouched to the SilicaListView below,
    // and only a clearly horizontal drag is captured by this one. A
    // content width of 3x the page lets the drag go one full page-width
    // either side of center before hitting the end of this virtual
    // space; onMovementEnded checks how far past center it got, cycles
    // the category (wrapping past either end, like a carousel) if it
    // crossed the threshold, and always snaps back to center -- the
    // real content never actually needs to move, only the category
    // (and therefore the list underneath it) changes.
    //
    // The header (title/tabs/search) stays inside the SilicaListView's
    // own header: -- pulling it out into a separate fixed sibling once
    // broke PullDownMenu's positioning (it assumes it's attached to the
    // page's actual, only, scrollable view) and made the search field
    // permanently pinned instead of scrolling away with the list as
    // usual. Instead, the header gets a counter-transform that exactly
    // cancels out the horizontal pan while a swipe is in progress, so
    // visually only the delegate items appear to move -- the header
    // still scrolls normally with the list vertically, still owns the
    // one real PullDownMenu, and nothing about that relationship changes.
    SilicaFlickable {
        id: swipeArea
        anchors.fill: parent
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: width * 3
        contentHeight: height
        contentX: width

        onMovementEnded: {
            var delta = contentX - width
            if (delta > width * 0.25) {
                page.nextCategory()
            } else if (delta < -width * 0.25) {
                page.prevCategory()
            }
            contentX = width
        }

    Item {
        x: swipeArea.width
        width: swipeArea.width
        height: swipeArea.height

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: bookmarkModel
        currentIndex: -1

        PullDownMenu {
            MenuItem {
                text: qsTr("Add bookmark")
                onClicked: pageStack.push(Qt.resolvedUrl("AddBookmarkPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
        }

        header: Item {
            id: headerWrapper
            width: listView.width
            height: headerColumn.height

            // The counter-shift transform lives on this inner Column,
            // not on headerWrapper itself (the thing actually assigned
            // to ListView's header:) -- a transform on the header item
            // ListView/PullDownMenu directly measure fed back into a
            // real QML "Binding loop detected" warning (confirmed
            // live), since PullDownMenu's own bindings target the same
            // flickable's contentHeight/bottomMargin. headerWrapper's
            // height is a plain, transform-independent binding, so
            // ListView's layout math never sees anything move.
            Column {
                id: headerColumn
                width: parent.width
                transform: Translate { x: swipeArea.contentX - swipeArea.width }

                PageHeader { title: qsTr("Readeck") }

                Row {
                    width: parent.width
                    height: Theme.itemSizeExtraSmall

                    Repeater {
                        model: [
                            { key: "unread", label: qsTr("Unread") },
                            { key: "favorites", label: qsTr("Favorites") },
                            { key: "archive", label: qsTr("Archive") },
                            { key: "all", label: qsTr("All") }
                        ]

                        BackgroundItem {
                            width: parent.width / 4
                            height: parent.height
                            highlighted: down || page.currentFilter === modelData.key

                            Label {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: page.currentFilter === modelData.key
                                       ? Theme.highlightColor
                                       : (parent.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor)
                            }

                            onClicked: page.setFilter(modelData.key)
                        }
                    }
                }

                SearchField {
                    id: searchField
                    width: parent.width
                    placeholderText: qsTr("Search bookmarks")
                    onTextChanged: {
                        page.searchText = text
                        searchDebounce.restart()
                    }
                }
            }
        }

        delegate: BookmarkDelegate {
            onOpenBookmark: pageStack.push(Qt.resolvedUrl("BookmarkDetailPage.qml"), {
                bookmarkId: bookmarkId,
                initialTitle: model.title,
                initialUrl: model.url,
                initialSiteName: model.siteName,
                initialIsMarked: model.isMarked,
                initialIsArchived: model.isArchived,
                initialReadingTime: model.readingTime
            })
            onToggleFavorite: readeckClient.updateBookmark(bookmarkId, { "is_marked": marked })
            onToggleArchive: readeckClient.updateBookmark(bookmarkId, { "is_archived": archived })
            onDeleteBookmark: readeckClient.deleteBookmark(bookmarkId)
        }

        footer: Item {
            width: listView.width
            height: (readeckClient.busy && bookmarkModel.count > 0) ? Theme.itemSizeMedium : 0

            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Small
                running: parent.height > 0
                visible: running
            }
        }

        onAtYEndChanged: if (atYEnd) { page.loadMore() }

        VerticalScrollDecorator {}
    }

    ViewPlaceholder {
        enabled: bookmarkModel.count === 0 && !readeckClient.busy
        text: currentFilter === "unread" ? qsTr("No unread bookmarks")
              : currentFilter === "favorites" ? qsTr("No favorites yet")
              : currentFilter === "archive" ? qsTr("Archive is empty")
              : qsTr("No bookmarks yet")
        hintText: qsTr("Pull down to add one")
    }

    } // Item
    } // SilicaFlickable (swipeArea)

    Timer {
        id: searchDebounce
        interval: 500
        onTriggered: page.reload()
    }

    // Simple transient error banner instead of a full notification system.
    Rectangle {
        id: errorBanner
        property alias text: errorLabel.text

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: visible ? errorLabel.implicitHeight + 2 * Theme.paddingMedium : 0
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)
        visible: false

        Label {
            id: errorLabel
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: Theme.horizontalPageMargin
            }
            wrapMode: Text.WordWrap
            color: Theme.errorColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: errorBanner.visible = false
        }

        Timer {
            running: errorBanner.visible
            interval: 4000
            onTriggered: errorBanner.visible = false
        }
    }
}
