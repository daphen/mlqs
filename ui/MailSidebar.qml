import QtQuick
import "."

Rectangle {
    id: bar
    color: Theme.bg_alt
    property bool active: false
    property int sel: 0

    readonly property var roleGlyph: ({
        inbox: "󰚇", starred: "", sent: "󰗍", drafts: "󰙏",
        spam: "󱚝", trash: "󰩺", label: "󰓹"
    })

    function move(d) {
        if (Backend.folders.length === 0) return
        sel = Math.max(0, Math.min(Backend.folders.length - 1, sel + d))
        list.positionViewAtIndex(sel, ListView.Contain)
    }
    function choose() {
        const f = Backend.folders[sel]
        if (f) Backend.selectFolder(f.id, f.name)
    }
    // keep visual selection tracking the open folder when it changes elsewhere
    Connections {
        target: Backend
        function onCurrentFolderIdChanged() {
            const i = Backend.folders.findIndex(f => f.id === Backend.currentFolderId)
            if (i >= 0) bar.sel = i
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        // account header
        Item {
            width: parent.width; height: 40
            Text {
                renderType: Text.NativeRendering
                anchors.left: parent.left; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const w = Backend.workspaces.find(x => x.id === Backend.currentAccount)
                    return w ? (w.email || w.name) : "mlqs"
                }
                color: Theme.fg; font.family: Theme.fontFamily
                font.hintingPreference: Font.PreferNoHinting
                font.pixelSize: 13; font.weight: 600
                elide: Text.ElideRight; width: bar.width - 24
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 50
            model: Backend.folders
            clip: true
            spacing: 1
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width; height: 30
                radius: Theme.radiusSm
                readonly property bool isOpen: modelData.id === Backend.currentFolderId
                readonly property bool isSel: bar.active && index === bar.sel
                color: isSel ? Theme.surface3 : isOpen ? Theme.surface2 : "transparent"

                Row {
                    anchors.left: parent.left; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        renderType: Text.NativeRendering
                        text: bar.roleGlyph[modelData.role] || "󰓹"
                        color: modelData.role === "starred" ? Theme.yellow : Theme.fg_muted
                        font.family: Theme.fontFamily; font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        renderType: Text.NativeRendering
                        text: modelData.role === "label" ? modelData.name : (modelData.name.charAt(0) + modelData.name.slice(1).toLowerCase())
                        color: modelData.unread > 0 ? Theme.fg : Theme.fg_secondary
                        font.family: Theme.fontFamily
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: 13
                        font.weight: modelData.unread > 0 ? 600 : 400
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, list.width - 90)
                    }
                }

                Rectangle {
                    visible: modelData.unread > 0
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(badgeText.implicitWidth + 10, 20); height: 16
                    radius: 8; color: Theme.orange
                    Text {
                        id: badgeText
                        renderType: Text.NativeRendering
                        anchors.centerIn: parent
                        text: modelData.unread > 9999 ? "9999+" : modelData.unread
                        color: Theme.ink
                        font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: 700
                    }
                }

                TapHandler {
                    onTapped: { bar.sel = index; bar.choose() }
                }
            }
        }
    }
}
