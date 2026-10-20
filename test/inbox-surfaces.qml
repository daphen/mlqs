import QtQuick
import QtTest
import Quickshell
import QsLib
import "."

ShellRoot {
    id: test
    property int phase: 0
    property color darkIdle
    function check(ok, message) { if (!ok) { Qt.quit(); throw new Error(message) } }
    function named(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const hit = named(child, name)
            if (hit) return hit
        }
        return null
    }
    function geometry() {
        const surface = named(index, "mailListSurface")
        const face = named(index, "mailRowFace")
        check(surface && face, "inbox does not use shared TabBar/TabFace")
        const state = named(face.parent, "mailRowStatus")
        const dot = named(state, "mailUnreadDot")
        const sender = named(face.parent, "mailSender")
        check(surface && surface.padding === 6 && surface.implicitHeight === 46, "inbox does not use shared TabBar")
        check(surface.children.some(child => child.cardRadius === 15), "outer inbox radius is not 15")
        check(face.radius === 9 && face.base.toString() === surface.face.toString(), "row does not use shared nested TabFace")
        check(face.height === 58 && face.parent.height === 64, "two-line mail density changed")
        check(Math.abs(face.mapToItem(surface, 0, 0).y - 6) < 0.1, "first row is not inset 6px")
        check(Math.abs(surface.width - face.mapToItem(surface, 0, 0).x - face.width - 6) < 0.1, "right row inset is not 6px")
        check(state.width === 20 && state.x - face.x === 10 && dot.width === 8 && dot.height === 8, "leading status slot differs from rail")
        check(sender.x - state.x - state.width === 6, "sender does not follow status slot by 6px")
        return face
    }
    FloatingWindow {
        id: window
        visible: true; width: 1100; height: 700
        MailIndex { id: index; anchors.fill: parent }
        TestCase { id: input; when: false }
    }
    Timer {
        interval: 220; repeat: true; running: true
        onTriggered: {
            if (test.phase === 0) {
                Theme.mode = "dark"
                Backend.onEvent(JSON.stringify({type:"workspaces",workspaces:[{id:"gmail",name:"gmail"}]}))
                Backend.selectAccount("gmail")
                Backend.onEvent(JSON.stringify({type:"folders",account:"gmail",folders:[{id:"INBOX",name:"Inbox",role:"inbox"}]}))
                Backend.onEvent(JSON.stringify({type:"conversations",account:"gmail",folder:"INBOX",items:[
                    {id:"one",subject:"A message subject",snippet:"The preview stays on its own line",senders:[{name:"Sender",email:"sender@example.test"}],date:"2026-10-20T12:00:00Z",unread:true,folderIds:["INBOX"]},
                    {id:"two",subject:"Read message",snippet:"Read and unread keep their hierarchy",senders:[],date:"2026-10-20T11:00:00Z",unread:false,folderIds:["INBOX"]}
                ]}))
            } else if (test.phase === 1) {
                const face = test.geometry()
                test.check(face.cursor && !face.selected, "normal-mode cursor styling missing")
                test.darkIdle = face.color
                index.visualStart()
            } else if (test.phase === 2) {
                const face = test.geometry()
                test.check(face.selected && face.border.width === 1, "visual range lost selected outline")
                test.check(test.named(face.parent,"mailSelectionBox").visible && !test.named(face.parent,"mailUnreadDot").visible, "visual selection lost its checkbox")
                index.visualEnd()
                Theme.mode = "light"
            } else if (test.phase === 3) {
                const face = test.geometry()
                test.check(face.color.toString() !== test.darkIdle.toString(), "light theme did not reach row")
                test.check(!test.named(face.parent,"mailSelectionBox").visible && test.named(face.parent,"mailUnreadDot").visible, "selection marker did not reset")
                index.move(1)
                test.check(index.current().tid === "two", "mail navigation changed")
                index.active = false
            } else if (test.phase === 4) {
                const face = test.named(index,"mailRowFace")
                const surface = test.named(index,"mailListSurface")
                test.check(face.x === surface.padding && face.radius === 9, "inactive pane loses nested geometry")
                input.mouseClick(face)
            } else {
                test.check(Backend.openConvId === "one", "shared container swallowed the message tap")
                console.log("PASS: shared inbox surfaces in light/dark, 15/9 radii, 6px inset, status slot, selection and navigation")
                Qt.quit()
            }
            test.phase++
        }
    }
}
