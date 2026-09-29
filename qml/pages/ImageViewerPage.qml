import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string imageSource: ""

    // Bounds how far in/out a pinch or double-tap can zoom -- 1.0 is
    // "fitted to the screen", matching image.fillMode below.
    readonly property real minScale: 1.0
    readonly property real maxScale: 4.0

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: Math.max(width, image.width * image.scale)
        contentHeight: Math.max(height, image.height * image.scale)
        clip: true

        PullDownMenu {
            MenuItem {
                text: qsTr("Open in browser")
                onClicked: Qt.openUrlExternally(page.imageSource)
            }
        }

        PinchArea {
            width: flick.contentWidth
            height: flick.contentHeight
            pinch.target: image
            pinch.minimumScale: page.minScale
            pinch.maximumScale: page.maxScale
            pinch.dragAxis: Pinch.NoDrag

            onPinchUpdated: {
                // Keeps the point under the fingers stationary while
                // scaling, instead of always zooming from the image's
                // top-left corner -- flick.contentX/Y are adjusted by
                // the same amount the pinch center moved due to the new
                // scale.
                var before = mapToItem(flick.contentItem, pinch.center.x, pinch.center.y)
                image.scale = Math.max(page.minScale, Math.min(page.maxScale, image.scale * (pinch.scale / pinch.previousScale)))
                var after = mapToItem(flick.contentItem, pinch.center.x, pinch.center.y)
                flick.contentX += before.x - after.x
                flick.contentY += before.y - after.y
            }

            Image {
                id: image
                width: flick.width
                height: flick.height
                source: page.imageSource
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                transformOrigin: Item.TopLeft

                MouseArea {
                    anchors.fill: parent
                    onDoubleClicked: {
                        image.scale = image.scale > page.minScale ? page.minScale : 2.0
                        flick.contentX = 0
                        flick.contentY = 0
                    }
                }
            }
        }

        VerticalScrollDecorator {}
        HorizontalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: image.status === Image.Loading
        visible: running
    }

    Label {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.secondaryColor
        text: qsTr("Could not load the image")
        visible: image.status === Image.Error
    }
}
