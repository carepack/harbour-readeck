import QtQuick 2.0
import Sailfish.Silica 1.0

ListItem {
    id: delegate
    width: ListView.view ? ListView.view.width : 0
    // A 2-line title must not be squeezed into a fixed row height -- that
    // pushed the subtitle (site/reading time) below the delegate's own
    // bounds and into the next row. Growing with the actual text keeps
    // every row tall enough for its own content.
    contentHeight: Math.max(Theme.itemSizeLarge, infoColumn.implicitHeight + 2 * Theme.paddingSmall)

    signal openBookmark(string bookmarkId)
    signal toggleFavorite(string bookmarkId, bool marked)
    signal toggleArchive(string bookmarkId, bool archived)
    signal deleteBookmark(string bookmarkId)

    Image {
        id: thumb
        width: Theme.itemSizeLarge
        height: Theme.itemSizeLarge
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        source: model.imageUrl ? model.imageUrl : ""
        fillMode: Image.PreserveAspectCrop
        clip: true
        visible: status === Image.Ready
        asynchronous: true
    }

    Icon {
        anchors.centerIn: thumb
        source: "image://theme/icon-m-document"
        visible: !thumb.visible
    }

    Column {
        id: infoColumn
        anchors {
            left: thumb.right
            leftMargin: Theme.paddingMedium
            right: favIcon.left
            rightMargin: Theme.paddingSmall
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.paddingSmall / 2

        Label {
            width: parent.width
            text: model.title || model.url
            truncationMode: TruncationMode.Fade
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            color: delegate.highlighted ? Theme.highlightColor : (model.isArchived ? Theme.secondaryColor : Theme.primaryColor)
        }

        Label {
            width: parent.width
            text: [model.siteName, model.readingTime > 0 ? qsTr("%1 min").arg(model.readingTime) : ""]
                  .filter(function (s) { return !!s }).join(" · ")
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: delegate.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }

    Icon {
        id: favIcon
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        source: "image://theme/icon-s-favorite-selected"
        visible: model.isMarked === true
    }

    // Subtle separator so consecutive entries read as distinct rows
    // rather than one continuous block, without adding a heavier visual
    // element (background tint, card outline, ...).
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: Theme.horizontalPageMargin
            rightMargin: Theme.horizontalPageMargin
        }
        height: 1
        color: Theme.rgba(Theme.primaryColor, 0.15)
    }

    menu: ContextMenu {
        MenuItem {
            text: model.isMarked ? qsTr("Remove from favorites") : qsTr("Add to favorites")
            onClicked: delegate.toggleFavorite(model.bookmarkId, !model.isMarked)
        }
        MenuItem {
            text: model.isArchived ? qsTr("Mark as unread") : qsTr("Archive")
            onClicked: delegate.toggleArchive(model.bookmarkId, !model.isArchived)
        }
        MenuItem {
            text: qsTr("Delete")
            onClicked: remorseItem.execute(delegate, qsTr("Deleting"), function () {
                delegate.deleteBookmark(model.bookmarkId)
            })
        }
    }

    RemorseItem { id: remorseItem }

    onClicked: delegate.openBookmark(model.bookmarkId)
}
