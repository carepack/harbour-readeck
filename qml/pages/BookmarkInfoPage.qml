import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Reference to the BookmarkDetailPage this info page is attached to.
    // Reading bindings off it keeps reading time / URL / links in sync
    // once the article body finishes loading.
    property var sourcePage

    readonly property string pageTitle: sourcePage ? sourcePage.initialTitle : ""
    readonly property string originalUrl: sourcePage ? sourcePage.initialUrl : ""
    readonly property int readingTime: sourcePage ? sourcePage.initialReadingTime : 0
    readonly property var links: sourcePage ? extractLinks(sourcePage.articleHtml) : []

    // A flat list combining the original source and every further link,
    // so both can share one SilicaListView + delegate.
    readonly property var listItems: {
        var items = []
        if (originalUrl) {
            items.push({ kind: "source", label: qsTr("Original source"), url: originalUrl })
        }
        for (var i = 0; i < links.length; i++) {
            items.push({ kind: "link", label: links[i].label, url: links[i].url })
        }
        return items
    }

    function stripTags(html) {
        var text = html.replace(/<[^>]*>/g, "")
        text = text.replace(/&nbsp;/g, " ")
                   .replace(/&amp;/g, "&")
                   .replace(/&lt;/g, "<")
                   .replace(/&gt;/g, ">")
                   .replace(/&quot;/g, "\"")
                   .replace(/&#39;/g, "'")
        return text.replace(/\s+/g, " ").trim()
    }

    function extractLinks(html) {
        var result = []
        if (!html) {
            return result
        }
        var seen = {}
        var re = /<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi
        var match
        while ((match = re.exec(html)) !== null) {
            var href = match[1]
            if (!href || href.indexOf("http") !== 0 || seen[href]) {
                continue
            }
            seen[href] = true
            result.push({ url: href, label: stripTags(match[2]) || href })
        }
        return result
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: listItems

        header: Column {
            width: listView.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Article info")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: pageTitle
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.primaryColor
                visible: !!pageTitle
            }

            SectionHeader { text: qsTr("Details") }

            DetailItem {
                label: qsTr("Reading time")
                value: readingTime > 0 ? qsTr("%n minute(s)", "", readingTime) : qsTr("Unknown")
            }

            SectionHeader {
                //: Header above the original-source row and any links found within the article body
                text: qsTr("Links")
                visible: listItems.length > 0
                horizontalAlignment: Text.AlignHCenter
            }
        }

        delegate: ListItem {
            id: linkItem
            width: listView.width
            contentHeight: linkRow.height + 2 * Theme.paddingMedium
            onClicked: Qt.openUrlExternally(modelData.url)

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Copy link")
                    onClicked: Clipboard.text = modelData.url
                }
            }

            Row {
                id: linkRow
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Icon {
                    source: modelData.kind === "source" ? "image://theme/icon-m-website" : "image://theme/icon-m-link"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    width: parent.width - Theme.iconSizeSmall - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        width: parent.width
                        text: modelData.label
                        color: modelData.kind === "source" ? Theme.secondaryColor : Theme.highlightColor
                        font.pixelSize: modelData.kind === "source" ? Theme.fontSizeExtraSmall : Theme.fontSizeDefault
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: modelData.url
                        color: modelData.kind === "source" ? Theme.primaryColor : Theme.secondaryColor
                        font.pixelSize: modelData.kind === "source" ? Theme.fontSizeDefault : Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        visible: modelData.kind === "source" || modelData.label !== modelData.url
                    }
                }
            }

            // Subtle separator between entries, matching the bookmark
            // list's own row treatment.
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
                visible: index < listItems.length - 1
            }
        }

        footer: Item {
            width: listView.width
            height: listItems.length === 0 ? noLinksLabel.height + Theme.paddingLarge : 0

            Label {
                id: noLinksLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: qsTr("No further links found in this article")
                color: Theme.secondaryColor
                visible: listItems.length === 0
            }
        }

        VerticalScrollDecorator {}
    }
}
