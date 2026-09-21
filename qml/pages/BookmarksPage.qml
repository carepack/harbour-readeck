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

        header: Column {
            width: listView.width

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
