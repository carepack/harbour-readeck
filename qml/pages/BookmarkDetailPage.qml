import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string bookmarkId
    property string initialTitle
    property string initialUrl
    property string initialSiteName
    property bool initialIsMarked
    property bool initialIsArchived
    property int initialReadingTime: 0

    property bool isMarked: initialIsMarked
    property bool isArchived: initialIsArchived
    property string articleHtml: ""
    property bool articleLoaded: false
    property bool articleError: false
    property bool _infoPagePushed: false
    property var articleSegments: []

    // Qt's rich text engine (used for textFormat: Text.RichText below)
    // does not scale embedded <img> tags to fit -- there is no working
    // "max-width: 100%" here like in a real browser, so any image wider
    // than the label renders past the right edge. Forcing an explicit
    // width (height follows automatically, preserving aspect ratio, when
    // only width is set) is the reliable fix across the Qt version
    // Sailfish OS ships. Confirmed live against Readeck's actual article
    // HTML: images are plain self-closing tags with width/height
    // attributes already present but too large; the trailing "/" of the
    // original tag has to be dropped before appending a replacement
    // width, or the rebuilt tag is malformed and Qt silently falls back
    // to the image's natural size.
    function fixImages(html, maxWidth) {
        return html.replace(/<img([^>]*)>/gi, function (match, attrs) {
            var cleaned = attrs
                .replace(/\s(width|height)\s*=\s*("[^"]*"|'[^']*')/gi, "")
                .replace(/\/\s*$/, "")
            return "<img" + cleaned + " width=\"" + maxWidth + "\"/>"
        })
    }

    function stripTags(html) {
        return html.replace(/<[^>]*>/g, "")
    }

    // Readeck's article HTML typically already wraps a captured image in
    // <a href="...full-size.jpg">...<img .../>...</a> ("click to see it
    // bigger" in a real browser) -- those keep their own href untouched,
    // which onLinkActivated below re-routes into the in-app zoom viewer
    // instead of the external browser. A bare <img> with no surrounding
    // link isn't tappable at all otherwise, so it gets a synthetic
    // <a href="its own src"> wrapper here. Already-linked images are
    // matched and set aside first (as placeholder tokens) so the second,
    // "wrap anything still bare" pass can't double-wrap them.
    function wrapImages(html) {
        var linked = []
        var protectedHtml = html.replace(/<a\b[^>]*>[\s\S]*?<img\b[^>]*>[\s\S]*?<\/a>/gi, function (match) {
            linked.push(match)
            return "\u0000L" + (linked.length - 1) + "\u0000"
        })
        var wrapped = protectedHtml.replace(/<img\b[^>]*\ssrc\s*=\s*["']([^"']+)["'][^>]*>/gi, function (match, src) {
            return "<a href=\"" + src + "\">" + match + "</a>"
        })
        return wrapped.replace(/\u0000L(\d+)\u0000/g, function (m, idx) {
            return linked[Number(idx)]
        })
    }

    function isImageUrl(url) {
        return /\.(jpe?g|png|gif|webp|bmp|svg)(\?.*)?$/i.test(url)
    }

    // Source sites often ship their own inline text coloring (a
    // hardcoded "color: ..." style attribute, or a legacy <font
    // color="..."> attribute) on prose that isn't a link at all --
    // pull-quotes, headings, etc. Qt's rich text engine honors it and
    // it overrides this page's own "color: Theme.primaryColor" below,
    // so it's stripped for general prose text too, independent of the
    // link-specific fix in styleLinks() below.
    function stripInlineColors(html) {
        return html
            .replace(/\scolor\s*=\s*("[^"]*"|'[^']*')/gi, "")
            .replace(/(style\s*=\s*")([^"]*)(")/gi, function (match, pre, styleBody, post) {
                var cleaned = styleBody.replace(/(^|;)\s*color\s*:[^;]*/gi, "$1").replace(/^;+/, "").trim()
                return pre + cleaned + post
            })
    }

    // The QML Text/Label "linkColor" property (used below to try to
    // theme link color via "linkColor: Theme.highlightColor") was only
    // added in Qt 5.14 -- this Sailfish OS target ships Qt 5.6.3
    // (confirmed via "rpm -q qt5-qtdeclarative" on-device), so that
    // property assignment was always a silent no-op there, and every
    // link actually rendered in Qt's own built-in default anchor color
    // (a fixed blue, independent of ambience/theme) the whole time --
    // explaining why stripping the *source* HTML's inline colors alone
    // never changed anything, since nothing in the source HTML was
    // actually responsible. The only way to control link color on this
    // Qt version is to put the color directly into the HTML itself, as
    // an inline style on every <a> tag, which QTextDocument's HTML
    // parser does honor regardless of Qt version.
    function styleLinks(html) {
        var hex = "" + Theme.highlightColor
        var rgb = hex.length === 9 ? ("#" + hex.substring(3)) : hex
        var linkStyle = "color:" + rgb + ";text-decoration:underline;"
        return html.replace(/<a\b([^>]*)>/gi, function (match, attrs) {
            var cleanedAttrs = attrs.replace(/\sstyle\s*=\s*("[^"]*"|'[^']*')/gi, "")
            return "<a" + cleanedAttrs + " style=\"" + linkStyle + "\">"
        })
    }

    function decodeEntities(text) {
        return text
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&#34;/g, "\"")
            .replace(/&#39;/g, "'")
            .replace(/&nbsp;/g, " ")
            .replace(/&amp;/g, "&")
    }

    // Code blocks (config samples, install one-liners, long IPs/URLs
    // with no natural break point) kept overflowing past the right edge
    // no matter what was tried to make them wrap: stripping the
    // syntax-highlighting <span> Readeck wraps around almost every token
    // in a code block, and even manually inserting real space characters
    // (not just zero-width ones) every 20 characters into long runs --
    // confirmed live, still overflowed regardless. Wrapping arbitrary
    // code inside a RichText Label depends on Qt's line-breaking
    // treating that content the way regular prose is treated, and on
    // this Qt version, for whatever reason, it measurably does not, no
    // matter how the content is reshaped.
    //
    // The fix that sidesteps needing that to ever work: don't wrap code
    // at all. A <pre> block is pulled out of the flowing article text
    // and rendered in its own horizontally scrollable, fixed-layout
    // element (plain monospace text, Text.NoWrap) instead of forcing it
    // into the same wrapping RichText flow as prose -- which is also
    // arguably more correct for code anyway: inserting a line break
    // *inside* a shell command or a config line changes what it means,
    // so wrapping it was never really the right behavior even if Qt's
    // renderer had cooperated. This is shape-driven (splits on <pre>,
    // not on any specific article's content), so it applies the same
    // way to whatever future article's code blocks contain.
    // Splits only on <pre> blocks, which sit as standalone top-level
    // elements between paragraphs in Readeck's article HTML -- never
    // nested inside a <p>. Cutting there keeps every resulting "html"
    // segment a complete, well-formed chunk of markup.
    //
    // An earlier version also pulled long/multi-word inline <code> runs
    // (e.g. "nmcli con show") out of the middle of paragraphs the same
    // way. That doesn't just extract the code -- it slices the enclosing
    // <p>...</p> in half, leaving one fragment with an unclosed <p> and
    // the other with a stray closing </p> and no opening tag. Confirmed
    // live: Qt's RichText parser handles that broken markup by rendering
    // the affected paragraph completely differently from every other one
    // in the same article (both the "Raspberry" character-loss bug and
    // the missing-right-margin bug traced back to exactly this -- the
    // *only* paragraphs affected were ones containing inline <code>).
    // Removing that step trades back a narrower, cosmetic issue (a very
    // long inline code phrase can still overflow slightly) for correct,
    // well-formed HTML in every paragraph.
    function extractSegments(html) {
        var segments = []
        var lastIndex = 0
        var re = /<pre\b[^>]*>([\s\S]*?)<\/pre>/gi
        var m
        while ((m = re.exec(html)) !== null) {
            if (m.index > lastIndex) {
                segments.push({ type: "html", content: html.substring(lastIndex, m.index) })
            }
            segments.push({ type: "code", content: decodeEntities(stripTags(m[1])) })
            lastIndex = re.lastIndex
        }
        if (lastIndex < html.length) {
            segments.push({ type: "html", content: html.substring(lastIndex) })
        }
        return segments
    }

    function rebuildSegments() {
        if (!articleHtml) {
            articleSegments = []
            return
        }
        var maxWidth = Math.floor(page.width - 2 * Theme.horizontalPageMargin)
        articleSegments = extractSegments(fixImages(styleLinks(wrapImages(stripInlineColors(articleHtml))), maxWidth))
    }

    onArticleHtmlChanged: rebuildSegments()

    onStatusChanged: {
        if (status === PageStatus.Active && !articleLoaded && !articleError) {
            readeckClient.loadArticle(bookmarkId)
        }
        // Swipe from the right edge to peek at reading time, the original
        // URL and any further links found in the article body. Deferred to
        // the Active transition (rather than Component.onCompleted): the
        // push that creates this very page is still in progress right
        // after construction, and pushAttached() throws if called while
        // another stack operation is running. Sailfish OS ships Qt 5.6, so
        // Qt.callLater() (added in Qt 5.8) is not an option here.
        if (status === PageStatus.Active && !_infoPagePushed) {
            _infoPagePushed = true
            pageStack.pushAttached(Qt.resolvedUrl("BookmarkInfoPage.qml"), { sourcePage: page })
        }
    }

    Connections {
        target: readeckClient
        onArticleReceived: {
            if (bookmarkId === page.bookmarkId) {
                articleHtml = html
                articleLoaded = true
            }
        }
        onArticleFailed: {
            if (bookmarkId === page.bookmarkId) {
                articleError = true
            }
        }
        onBookmarkUpdated: {
            if (bookmarkId === page.bookmarkId) {
                if (changes.is_marked !== undefined) { isMarked = changes.is_marked }
                if (changes.is_archived !== undefined) { isArchived = changes.is_archived }
            }
        }
        onBookmarkDeleted: {
            if (bookmarkId === page.bookmarkId) {
                pageStack.pop()
            }
        }
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: isMarked ? qsTr("Remove from favorites") : qsTr("Add to favorites")
                onClicked: readeckClient.updateBookmark(bookmarkId, { "is_marked": !isMarked })
            }
            MenuItem {
                text: isArchived ? qsTr("Mark as unread") : qsTr("Mark as read / archive")
                onClicked: readeckClient.updateBookmark(bookmarkId, { "is_archived": !isArchived })
            }
            MenuItem {
                text: qsTr("Open in browser")
                onClicked: Qt.openUrlExternally(initialUrl)
            }
            MenuItem {
                text: qsTr("Export as PDF")
                visible: articleLoaded
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("PdfLocationDialog.qml"))
                    dialog.accepted.connect(function() {
                        var path = readeckClient.exportArticlePdf(initialTitle || initialUrl, articleHtml, dialog.folder)
                        if (path) {
                            exportBanner.color = Theme.rgba(Theme.secondaryHighlightColor, 0.9)
                            exportBanner.text = qsTr("Saved to %1").arg(path)
                        } else {
                            exportBanner.color = Theme.rgba(Theme.highlightBackgroundColor, 0.9)
                            exportBanner.text = readeckClient.lastError
                        }
                        exportBanner.visible = true
                    })
                }
            }
            MenuItem {
                text: qsTr("Delete")
                onClicked: remorse.execute(qsTr("Deleting bookmark"), function () {
                    readeckClient.deleteBookmark(bookmarkId)
                })
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            // Left without a title: PageHeader itself only ever shows one
            // truncated line, so it can't be the actual title display for
            // a long headline -- it's still required at the top of every
            // page per Sailfish convention, just empty here rather than
            // showing a second, truncated copy of the title right above
            // the full one below.
            PageHeader {}

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                text: initialTitle || initialUrl
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeLarge
                visible: !!initialTitle
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: initialSiteName
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: !!initialSiteName
            }

            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Icon {
                    source: "image://theme/icon-s-favorite-selected"
                    visible: isMarked
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                }
                Label {
                    text: isArchived ? qsTr("Archived") : qsTr("Unread")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: !articleLoaded && !articleError
                visible: running
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                text: qsTr("Could not load the article. You can still open it in the browser from the pulley menu.")
                visible: articleError
            }

            Repeater {
                model: articleLoaded ? articleSegments : []

                // A plain delegate (both branches always instantiated,
                // only one made visible) instead of Loader/Component --
                // Loader creates its item dynamically, and for a very
                // large RichText document that delegate's width binding
                // was measurably not settled in time for Qt's initial text
                // layout pass (confirmed: this page's original, known-good
                // version, 0.1.0-8, declared its article Label directly as
                // a Column child with no Loader indirection, and never hit
                // the wrapping/margin bugs seen here). A plain Item avoids
                // that dynamic-creation timing entirely.
                delegate: Item {
                    width: column.width
                    height: modelData.type === "code" ? codeBox.height : htmlLabel.height

                    Label {
                        id: htmlLabel
                        visible: modelData.type !== "code"
                        // Text.WordWrap, not Text.Wrap: WordWrap only ever
                        // breaks at word boundaries and, when a word
                        // doesn't fit, simply moves it whole to the next
                        // line (worst case: that one word overflows uncut
                        // if it's longer than the whole line). Text.Wrap
                        // additionally *forces* a mid-word break when
                        // needed, and that forced break is where a
                        // confirmed Qt/Sailfish bug on this Qt version
                        // silently drops a character right at the break
                        // point (reproduced twice: "Raspberry" and
                        // "getdocker.sh" each lost one letter exactly at
                        // the wrap boundary, with no fix found despite
                        // extensive testing). Never forcing that kind of
                        // break avoids the bug entirely.
                        clip: true
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignJustify
                        textFormat: Text.RichText
                        color: Theme.primaryColor
                        text: modelData.type !== "code" ? modelData.content : ""
                        onLinkActivated: {
                            if (isImageUrl(link)) {
                                pageStack.push(Qt.resolvedUrl("ImageViewerPage.qml"), { imageSource: link })
                            } else {
                                Qt.openUrlExternally(link)
                            }
                        }
                    }

                    Item {
                        id: codeBox
                        visible: modelData.type === "code"
                        clip: true
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        height: modelData.type === "code" ? codeLabel.height + 2 * Theme.paddingMedium : 0

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.rgba(Theme.primaryColor, 0.06)
                        }

                        Label {
                            id: codeLabel
                            x: Theme.paddingMedium
                            y: Theme.paddingMedium
                            width: parent.width - 2 * Theme.paddingMedium
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeExtraSmall
                            wrapMode: Text.WordWrap
                            color: Theme.primaryColor
                            text: modelData.type === "code" ? modelData.content : ""
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    RemorsePopup { id: remorse }

    // Simple transient banner instead of a full notification system --
    // mirrors the same pattern used elsewhere in this app.
    Rectangle {
        id: exportBanner
        property alias text: exportBannerLabel.text

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: visible ? exportBannerLabel.implicitHeight + 2 * Theme.paddingMedium : 0
        visible: false

        Label {
            id: exportBannerLabel
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: Theme.horizontalPageMargin
            }
            wrapMode: Text.WordWrap
            color: Theme.primaryColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: exportBanner.visible = false
        }

        Timer {
            running: exportBanner.visible
            interval: 4000
            onTriggered: exportBanner.visible = false
        }
    }
}
