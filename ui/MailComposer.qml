import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "."

// Compose / reply overlay. Ctrl+Enter sends, Esc discards,
// Ctrl+O attaches the file path currently on the clipboard.
Rectangle {
    id: comp
    visible: false
    anchors.centerIn: parent
    width: Math.min(parent.width - 120, 760)
    height: Math.min(parent.height - 100, 640)
    radius: Theme.radius
    color: Theme.bg_alt
    border.width: 1
    border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, Theme.mode === "light" ? 0.15 : 0.10)

    property string mode: "new"      // "new" | "reply"
    property string replyToId: ""
    property string convId: ""
    property var paths: []
    signal closed()

    function composeNew() {
        mode = "new"; replyToId = ""; convId = ""; paths = []
        toField.text = ""; ccField.text = ""; subjField.text = ""; bodyArea.text = ""
        visible = true
        toField.forceActiveFocus()
    }

    // reply to the newest message; all=true adds every recipient minus self
    function reply(all) {
        const msgs = Backend.messages
        if (msgs.length === 0) return
        const m = msgs[msgs.length - 1]
        mode = "reply"; replyToId = m.id; convId = Backend.openConvId; paths = []
        toField.text = m.from ? m.from.email : ""
        let cc = []
        if (all) {
            const self = (Backend.workspaces.find(w => w.id === Backend.currentAccount) || {}).email || ""
            const rest = (m.to || []).concat(m.cc || [])
                .map(a => a.email).filter(e => e && e !== self && e !== toField.text)
            cc = [...new Set(rest)]
        }
        ccField.text = cc.join(", ")
        const subj = m.subject || Backend.openConvSubject
        subjField.text = subj.match(/^re:/i) ? subj : "Re: " + subj
        bodyArea.text = ""
        visible = true
        bodyArea.forceActiveFocus()
    }

    function doSend() {
        if (toField.text.trim() === "") { Backend.toast("no recipient"); return }
        Backend.sendMail({
            to: toField.text, cc: ccField.text, subject: subjField.text,
            body: bodyArea.text, replyTo: replyToId, conv: convId, paths: paths
        })
        close()
    }

    function close() { visible = false; closed() }

    function attachClipboardPath() { clipPath.running = true }
    Process {
        id: clipPath
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p.startsWith("/") || p.startsWith("~")) {
                    comp.paths = comp.paths.concat([p])
                } else Backend.toast("clipboard is not a file path")
            }
        }
    }

    // shared keys for every field in the composer
    function handleKeys(e) {
        const ctrl = e.modifiers & Qt.ControlModifier
        if (e.key === Qt.Key_Escape) { close(); e.accepted = true; return true }
        if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { doSend(); e.accepted = true; return true }
        if (ctrl && e.key === Qt.Key_O) { attachClipboardPath(); e.accepted = true; return true }
        return false
    }

    component LabeledField: Rectangle {
        property alias text: input.text
        property alias input: input
        property string label: ""
        width: parent.width; height: 34
        radius: Theme.radiusSm
        color: Theme.mode === "light" ? Theme.bg : Theme.surface2
        border.width: 1; border.color: Theme.hairline
        Row {
            anchors.fill: parent; anchors.leftMargin: 10
            spacing: 8
            Text {
                renderType: Text.NativeRendering
                text: label; color: Theme.fg_muted
                width: 56
                font.family: Theme.fontFamily; font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            TextField {
                id: input
                width: parent.width - 74; height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: 13
                background: null
                Keys.onPressed: e => comp.handleKeys(e)
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text {
            renderType: Text.NativeRendering
            text: comp.mode === "reply" ? "Reply" : "New message"
            color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: 600
        }

        LabeledField { id: toField; label: "To" }
        LabeledField { id: ccField; label: "Cc" }
        LabeledField { id: subjField; label: "Subject" }

        Rectangle {
            width: parent.width
            height: parent.height - y - (attachRow.visible ? 34 : 0) - 30
            radius: Theme.radiusSm
            color: Theme.mode === "light" ? Theme.bg : Theme.surface1
            border.color: bodyArea.activeFocus ? Theme.fg_muted : Theme.hairline; border.width: 1
            Flickable {
                id: bodyFlick
                anchors.fill: parent; anchors.margins: 10
                contentHeight: bodyArea.implicitHeight; clip: true
                function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                }
                TextArea {
                    id: bodyArea
                    width: bodyFlick.width
                    onCursorRectangleChanged: bodyFlick.ensureVisible(cursorRectangle)
                    wrapMode: TextArea.Wrap
                    color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 13
                    background: null
                    Keys.onPressed: e => comp.handleKeys(e)
                }
            }
        }

        Row {
            id: attachRow
            visible: comp.paths.length > 0
            spacing: 6
            Repeater {
                model: comp.paths
                Rectangle {
                    required property var modelData
                    required property int index
                    width: chip.implicitWidth + 26; height: 22
                    radius: 11; color: Theme.surface2
                    Text {
                        id: chip
                        renderType: Text.NativeRendering
                        anchors.left: parent.left; anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰁦 " + modelData.split("/").pop()
                        color: Theme.fg_secondary
                        font.family: Theme.fontFamily; font.pixelSize: 11
                    }
                    TapHandler { onTapped: comp.paths = comp.paths.filter((_, i) => i !== index) }
                }
            }
        }

        Text {
            renderType: Text.NativeRendering
            text: "Ctrl+Enter send · Esc discard · Ctrl+O attach clipboard path"
            color: Theme.fg_muted
            font.family: Theme.fontFamily; font.pixelSize: 11
        }
    }
}
