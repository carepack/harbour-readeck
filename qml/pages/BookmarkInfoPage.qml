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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
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

            // The source this article was saved from -- visually its own,
            // distinct kind of row (a website glyph, no highlight color)
            // so it doesn't read as just one more entry in the "further
            // links" list below it.
            BackgroundItem {
                width: parent.width
                height: sourceRow.height + 2 * Theme.paddingMedium
                visible: !!originalUrl
                onClicked: Qt.openUrlExternally(originalUrl)

                Row {
                    id: sourceRow
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingMedium

                    Icon {
                        source: "image://theme/icon-m-website"
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - Theme.iconSizeSmall - Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            width: parent.width
                            text: qsTr("Original source")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                        }
                        Label {
                            width: parent.width
                            text: originalUrl
                            truncationMode: TruncationMode.Fade
                            color: Theme.primaryColor
                        }
                    }
                }
            }

            SectionHeader {
                //: Links found within the article body, as opposed to the single "original source" link above
                text: qsTr("Further links in this article")
                visible: links.length > 0
                horizontalAlignment: Text.AlignHCenter
            }

            Column {
                width: parent.width
                visible: links.length > 0

                Repeater {
                    model: links
                    delegate: BackgroundItem {
                        width: parent.width
                        height: linkRow.height + 2 * Theme.paddingMedium
                        onClicked: Qt.openUrlExternally(modelData.url)

                        Row {
                            id: linkRow
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingMedium

                            Icon {
                                source: "image://theme/icon-m-link"
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
                                    color: Theme.highlightColor
                                    truncationMode: TruncationMode.Fade
                                }
                                Label {
                                    width: parent.width
                                    text: modelData.url
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                    truncationMode: TruncationMode.Fade
                                    visible: modelData.label !== modelData.url
                                }
                            }
                        }

                        // Subtle separator between entries, matching the
                        // bookmark list's own row treatment.
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
                            visible: index < links.length - 1
                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: qsTr("No further links found in this article")
                color: Theme.secondaryColor
                visible: links.length === 0
            }
        }

        VerticalScrollDecorator {}
    }
}
