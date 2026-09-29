import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

// Embedded browser used to grab a page's rendered HTML for the "provide
// page content manually" option in AddBookmarkPage.qml. Sailfish's
// share sheet only ever hands a receiving app the URL and title (see
// src/sharereceiver.h) -- unlike iOS Safari Share Extensions, there is
// no platform hook that lets a share target read the DOM of a page
// shown in the *stock* browser. Loading the page again here, in our own
// embedded WebView, lets the user log in if needed (e.g. past a
// paywall) and then read the exact same document.documentElement that a
// "View page source" copy-paste would have produced, without the
// manual copy-paste.
WebViewPage {
    id: page
    allowedOrientations: Orientation.All

    property string initialUrl: ""

    // Emitted with the captured html once the user taps "Use this page".
    // The caller (AddBookmarkPage.qml) connects to this on the object
    // pageStack.push() returns and pops this page itself once done.
    signal contentCaptured(string url, string title, string html)

    // Guards against handling "readeck:contentExtracted" more than once.
    // Observed live: tapping "Use this page's content" led to FOUR
    // "cannot pop while transition is in progress" warnings back to back,
    // followed by a SIGSEGV in the Gecko worker thread -- i.e. the
    // message arrived (or was otherwise triggered) more than once, and
    // popping this WebViewPage repeatedly while Gecko was still
    // mid-callback tore the view down out from under it. Once "captured"
    // is set, any further message/click is ignored.
    property bool captured: false

    Column {
        id: header
        width: parent.width

        PageHeader {
            title: qsTr("Capture page content")
        }

        TextField {
            id: urlField
            width: parent.width
            text: initialUrl
            label: qsTr("URL")
            placeholderText: qsTr("https://example.com/article")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: page.navigate()
        }
    }

    WebView {
        id: webView
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            bottom: toolbar.top
        }

        Component.onCompleted: {
            webView.loadFrameScript(Qt.resolvedUrl("../js/extractcontent.js"))
            webView.addMessageListener("readeck:contentExtracted")
            if (initialUrl.length > 0) {
                page.navigate()
            }
        }

        // Not "onRecvAsyncMessage:" directly on this WebView instance:
        // WebView.qml's own implementation already has a recvAsyncMessage
        // handler (for pickers, popups, text selection, link clicks --
        // see /usr/lib/qt5/qml/Sailfish/WebView/WebView.qml). Assigning
        // the signal handler again here would replace that one instead
        // of adding to it. Connections attaches an independent listener.
        Connections {
            target: webView
            onRecvAsyncMessage: {
                if (message === "readeck:contentExtracted" && !page.captured) {
                    page.captured = true
                    page.contentCaptured(data.url, data.title, data.html)
                    // Deferred rather than an immediate pageStack.pop():
                    // this handler runs on the stack of a Gecko message
                    // dispatch, and popping (which destroys this
                    // WebViewPage and its WebView) from inside that
                    // callback is what produced the crash described
                    // above. A zero-interval Timer lets that dispatch
                    // unwind first.
                    popTimer.start()
                }
            }
        }
    }

    Timer {
        id: popTimer
        interval: 0
        onTriggered: pageStack.pop()
    }

    BusyIndicator {
        anchors.centerIn: webView
        size: BusyIndicatorSize.Large
        running: webView.loading
        visible: running
    }

    // An always-visible action bar rather than a PullDownMenu: pulley
    // menus need their parent to behave like a SilicaFlickable to catch
    // the pull-down drag, which the Gecko-based WebView does not, so a
    // PullDownMenu placed on/in it is effectively unreachable.
    Item {
        id: toolbar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: Theme.paddingMedium
        }
        height: Theme.itemSizeMedium

        IconButton {
            id: reloadButton
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            icon.source: "image://theme/icon-m-refresh"
            onClicked: webView.reload()
        }

        Button {
            anchors {
                left: parent.left
                right: reloadButton.left
                rightMargin: Theme.paddingSmall
                verticalCenter: parent.verticalCenter
            }
            //: Reads the currently displayed page and sends it back to the add-bookmark form
            text: qsTr("Use this page's content")
            enabled: !page.captured && !webView.loading && webView.url.toString().length > 0
            onClicked: webView.sendAsyncMessage("readeck:extractContent", {})
        }
    }

    function navigate() {
        var target = urlField.text.trim()
        if (target.length === 0) {
            return
        }
        if (target.indexOf("://") < 0) {
            target = "https://" + target
        }
        webView.url = target
    }
}
