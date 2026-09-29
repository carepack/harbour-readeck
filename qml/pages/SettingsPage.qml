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
                    text: qsTr("Server")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: readeckClient.endpoint
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Item { width: parent.width; height: Theme.paddingMedium }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingSmall / 2

                Label {
                    width: parent.width
                    text: qsTr("Username")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    width: parent.width
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

            SectionHeader { text: qsTr("Reading") }

            TextSwitch {
                text: qsTr("Justify article text")
                description: qsTr("Align text evenly on both edges instead of only the left")
                checked: readeckClient.justifyArticleText
                onCheckedChanged: readeckClient.justifyArticleText = checked
            }

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
