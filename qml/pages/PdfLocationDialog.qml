import QtQuick 2.0
import Sailfish.Silica 1.0
import Qt.labs.folderlistmodel 2.1

// A small file-browser for choosing a PDF export destination, confirmed
// with Silica's standard Dialog accept gesture (swipe right-to-left
// over the page) -- no separate "confirm" button needed beyond that.
//
// The starting ("home") view lists the folder trees the app's
// "UserDirs" Sailjail permission actually grants read/write access to
// (Downloads, Documents, Pictures, Videos, Music, Public -- see
// /etc/sailjail/permissions/UserDirs.permission on-device), using the
// exact same row style as real subfolder browsing below them, so it
// reads as one continuous file browser rather than a separate picker
// screen. There is no permission for arbitrary access to the rest of
// $HOME (Sailjail whitelists specific trees only), so a literal, full
// $HOME listing isn't possible under the sandbox -- everything outside
// these six trees would just show up empty/inaccessible, which would
// be more confusing, not less.
Dialog {
    id: dialog

    property var roots: [
        { name: qsTr("Downloads"), path: readeckClient.downloadsPath() },
        { name: qsTr("Documents"), path: readeckClient.documentsPath() },
        { name: qsTr("Pictures"), path: readeckClient.picturesPath() },
        { name: qsTr("Videos"), path: readeckClient.videosPath() },
        { name: qsTr("Music"), path: readeckClient.musicPath() },
        { name: qsTr("Public"), path: readeckClient.publicPath() }
    ]

    // "" means: still at the synthetic root list above, nothing
    // concrete chosen yet.
    property string folder: ""
    readonly property bool atRoot: folder === ""

    function isRootPath(path) {
        for (var i = 0; i < roots.length; i++) {
            if (roots[i].path === path) {
                return true
            }
        }
        return false
    }

    canAccept: !atRoot

    SilicaListView {
        id: listView
        anchors.fill: parent

        header: Column {
            width: parent.width
            DialogHeader {
                title: qsTr("Save location")
                acceptText: qsTr("Save here")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: dialog.atRoot ? qsTr("Home") : dialog.folder
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        model: dialog.atRoot ? dialog.roots : folderModel

        FolderListModel {
            id: folderModel
            // Always points at a real, valid folder (even while atRoot,
            // when it's simply unused) so it never has to load an empty
            // path.
            folder: dialog.atRoot ? dialog.roots[0].path : dialog.folder
            showDirsFirst: true
            showFiles: false
            showDotAndDotDot: false
            sortField: FolderListModel.Name
        }

        delegate: ListItem {
            contentHeight: Theme.itemSizeSmall
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingMedium

                Icon {
                    source: "image://theme/icon-m-folder"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width - Theme.iconSizeSmall - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    text: dialog.atRoot ? modelData.name : fileName
                    truncationMode: TruncationMode.Fade
                    color: Theme.primaryColor
                }
            }
            onClicked: dialog.folder = dialog.atRoot ? modelData.path : filePath
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Up one level")
                visible: !dialog.atRoot
                onClicked: {
                    if (dialog.isRootPath(dialog.folder)) {
                        dialog.folder = ""
                    } else {
                        var parts = dialog.folder.split("/")
                        parts.pop()
                        dialog.folder = parts.join("/")
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: !dialog.atRoot && folderModel.count === 0
            text: qsTr("No subfolders here")
        }

        VerticalScrollDecorator {}
    }
}
