import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Settings") }

            SectionHeader { text: qsTr("Account") }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall / 2

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Server")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    text: readeckClient.endpoint
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall / 2

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Username")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    text: readeckClient.username
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Item { width: parent.width; height: Theme.paddingLarge }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Sign out")
                onClicked: {
                    readeckClient.logout()
                    pageStack.pop(null, PageStackAction.Immediate)
                    pageStack.replace(Qt.resolvedUrl("LoginPage.qml"), {}, PageStackAction.Immediate)
                }
            }

            Item { width: parent.width; height: Theme.paddingLarge }

            SectionHeader { text: qsTr("About") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("An unofficial, open-source Sailfish OS client for Readeck (readeck.org).")
            }
        }

        VerticalScrollDecorator {}
    }
}
