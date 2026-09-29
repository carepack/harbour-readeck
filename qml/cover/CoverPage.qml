import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    readonly property var currentItem: readeckClient.coverBookmarks.length > 0
        ? readeckClient.coverBookmarks[readeckClient.coverIndex]
        : null
    readonly property string currentImageUrl: currentItem ? (currentItem.imageUrl || "") : ""

    Image {
        id: articleImage
        anchors.fill: parent
        source: currentImageUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
        clip: true
    }

    // Darkens the lower part of the article image so the title and
    // unread count stay legible over any photo.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: parent.height * 0.6
        visible: articleImage.visible
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba(Theme.overlayBackgroundColor, 0.0) }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.overlayBackgroundColor, 0.85) }
        }
    }

    Label {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.verticalCenter
            bottomMargin: Theme.paddingSmall
            margins: Theme.paddingMedium
        }
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        truncationMode: TruncationMode.Fade
        text: currentItem ? (currentItem.title || currentItem.url) : "Readeck"
        font.pixelSize: currentItem ? Theme.fontSizeSmall : Theme.fontSizeLarge
        color: Theme.primaryColor
    }

    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.verticalCenter
            topMargin: Theme.paddingSmall
        }
        visible: readeckClient.isLoggedIn
        text: readeckClient.unreadCount > 0
              ? qsTr("%1 unread").arg(readeckClient.unreadCount)
              : qsTr("All caught up")
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: readeckClient.coverNext()
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-sync"
            onTriggered: readeckClient.refreshUnreadCount()
        }
    }
}
