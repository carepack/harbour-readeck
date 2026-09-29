import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Manual API-token entry is a fallback for Readeck servers predating
    // 0.21 (no OAuth support) -- see readeckclient.h's startOAuthLogin().
    property bool useTokenFallback: false

    Connections {
        target: readeckClient
        onLoginSucceeded: pageStack.replace(Qt.resolvedUrl("BookmarksPage.qml"))
        onLoginFailed: {
            errorLabel.text = message
            errorLabel.visible = true
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Sign in to Readeck") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: qsTr("You'll be taken to your server's own login page in the browser -- this app never sees your password.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: !useTokenFallback
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: qsTr("Readeck apps authenticate with a personal API token, not your account password. In the Readeck web interface, open Profile → API tokens, create a new token and paste it below.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: useTokenFallback
            }

            TextField {
                id: serverField
                width: parent.width
                label: qsTr("Server address")
                placeholderText: qsTr("https://readeck.example.com")
                text: readeckClient.endpoint
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                enabled: !readeckClient.busy && !readeckClient.oauthInProgress
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: useTokenFallback ? tokenField.focus = true : doLogin()
            }

            TextArea {
                id: tokenField
                width: parent.width
                label: qsTr("API token")
                placeholderText: qsTr("Paste the token generated in Profile → API tokens")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                visible: useTokenFallback
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: doLogin()
            }

            Label {
                id: errorLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                visible: false
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (readeckClient.busy || readeckClient.oauthInProgress) ? qsTr("Signing in…") : qsTr("Sign in")
                enabled: !readeckClient.busy && !readeckClient.oauthInProgress
                         && serverField.text.length > 0
                         && (!useTokenFallback || tokenField.text.length > 0)
                onClicked: doLogin()
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: readeckClient.busy || readeckClient.oauthInProgress
                visible: running
            }

            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                visible: readeckClient.oauthInProgress

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.secondaryColor
                    text: qsTr("Waiting for you to finish logging in in the browser…")
                }

                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    //: Shown only if the browser didn't already pre-fill this code
                    text: readeckClient.oauthUserCode
                    visible: !!readeckClient.oauthUserCode
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Cancel")
                    onClicked: readeckClient.cancelOAuthLogin()
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: useTokenFallback ? qsTr("Sign in with browser instead") : qsTr("Sign in with an API token instead")
                visible: !readeckClient.oauthInProgress && !readeckClient.busy
                onClicked: {
                    useTokenFallback = !useTokenFallback
                    errorLabel.visible = false
                }
            }
        }

        VerticalScrollDecorator {}
    }

    function doLogin() {
        errorLabel.visible = false
        if (useTokenFallback) {
            readeckClient.loginWithToken(serverField.text, tokenField.text)
        } else {
            readeckClient.startOAuthLogin(serverField.text)
        }
    }
}
