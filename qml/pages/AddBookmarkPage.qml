import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog
    canAccept: urlField.text.trim().length > 0

    // Pre-filled when opened from the share sheet (see harbour-readeck.qml
    // shareInto()); empty when opened from the pulley menu.
    property string initialUrl: ""
    property string initialTitle: ""
    property bool initialProvideHtml: false

    onAccepted: {
        var labels = labelsField.text.split(",")
            .map(function (s) { return s.trim() })
            .filter(function (s) { return s.length > 0 })
        var html = provideHtmlSwitch.checked ? htmlField.text : ""
        readeckClient.createBookmark(urlField.text.trim(), titleField.text.trim(), labels, html)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                title: qsTr("Save bookmark")
                acceptText: qsTr("Save")
            }

            TextField {
                id: urlField
                width: parent.width
                text: initialUrl
                label: qsTr("URL")
                placeholderText: qsTr("https://example.com/article")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                focus: initialUrl.length === 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: titleField.focus = true
            }

            TextField {
                id: titleField
                width: parent.width
                text: initialTitle
                label: qsTr("Title (optional)")
                placeholderText: qsTr("Custom title")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: labelsField.focus = true
            }

            TextField {
                id: labelsField
                width: parent.width
                label: qsTr("Labels (optional)")
                placeholderText: qsTr("comma, separated, labels")
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            TextSwitch {
                id: provideHtmlSwitch
                width: parent.width
                checked: initialProvideHtml
                text: qsTr("Provide page content manually")
                //: Explains why you'd paste HTML instead of letting the server fetch the URL
                description: qsTr("By default the server fetches the URL itself. If the page is behind a paywall or login it can't reach, use the button below to open it in the app's own browser and capture it there, or paste the page's HTML source here yourself (e.g. from the browser's \"View page source\").")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Capture page in embedded browser")
                onClicked: {
                    // CaptureContentPage.qml loads the URL in our own
                    // WebView (so the user can log in past a paywall if
                    // needed) and emits contentCaptured() with the
                    // live-rendered document.documentElement.outerHTML --
                    // see qml/js/extractcontent.js for the frame-script
                    // side of this.
                    var capturePage = pageStack.push(Qt.resolvedUrl("CaptureContentPage.qml"), {
                        initialUrl: urlField.text.trim()
                    })
                    capturePage.contentCaptured.connect(function (url, title, html) {
                        urlField.text = url
                        if (title.length > 0) {
                            titleField.text = title
                        }
                        htmlField.text = html
                        provideHtmlSwitch.checked = true
                    })
                }
            }

            TextArea {
                id: htmlField
                width: parent.width
                visible: provideHtmlSwitch.checked
                height: visible ? Theme.itemSizeLarge * 3 : 0
                label: qsTr("Page HTML")
                placeholderText: qsTr("Paste the page's HTML source here")
                focus: initialProvideHtml
            }
        }

        VerticalScrollDecorator {}
    }
}
