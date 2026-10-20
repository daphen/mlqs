import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    function check(ok, message) { if (!ok) { Qt.quit(); throw new Error(message) } }
    function feed(event) { Backend.onEvent(JSON.stringify(event)) }
    function row(id, date) { return {id:id, subject:id, date:date || "2026-10-19T12:00:00Z", senders:[], unread:true, folderIds:["INBOX"]} }
    function list(account, items, cached, next) {
        feed({type:"conversations", account:account, folder:"INBOX", items:items, cached:!!cached, next:next || ""})
    }
    function failure(account, operation) {
        feed({type:"toast", account:account, operation:operation || "conversations", text:"request failed"})
    }
    FloatingWindow {
        visible:true; width:600; height:600
        MailIndex { id: index; anchors.fill:parent }
    }
    Timer {
        interval:200; running:true; repeat:true
        onTriggered: {
            if (test.phase === 0) {
                test.feed({type:"workspaces",workspaces:[{id:"gmail",name:"gmail"},{id:"work",name:"work"}]})
                Backend.selectUnified()
                for (const account of ["gmail","work"])
                    test.feed({type:"folders",account:account,folders:[{id:"INBOX",name:"Inbox",role:"inbox",unread:10}]})
                test.list("gmail",[test.row("g1"),test.row("g2","2026-10-19T11:00:00Z")],true)
                test.check(Backend.convs.count === 2 && Backend.loadingConvs, "cached mail waits for the other account")
            } else if (test.phase === 1) {
                index.toTop(); index.move(1)
                test.check(index.current().tid === "g2", "cannot select cached row")
                test.list("work",[test.row("g1","2026-10-19T13:00:00Z")])
                test.check(Backend.convs.count === 3 && !Backend.loadingConvs, "partial cached/fresh results missing")
            } else if (test.phase === 2) {
                test.check(index.current().tid === "g2", "arriving account moved the selection to another message")
                Backend.setLocalRead("g1",true,"gmail")
                test.list("gmail",[test.row("g1"),test.row("g2","2026-10-19T11:00:00Z")])
                test.check(!Backend.convs.get(Backend.findRow("g1","gmail")).unread, "fresh results undo read grace")
                test.check(Backend.convs.get(Backend.findRow("g1","work")).unread, "colliding account IDs share read state")
                test.list("gmail",[test.row("late-cache")],true)
                test.check(Backend.convs.count === 3 && Backend.findRow("late-cache","gmail") < 0, "late cache overwrites fresh rows")
                test.failure("gmail")
                test.check(Backend.convs.count === 3 && !Backend.loadingConvs, "error discards cached results")
                Backend.selectUnified()
                test.list("gmail",[test.row("g1")])
                test.check(Backend.convs.count === 1 && Backend.loadingConvs, "fresh first account is hidden")
                test.failure("work","markread")
                test.check(Backend.loadingConvs, "unrelated operation completes a list request")
                test.failure("work")
                test.check(Backend.convs.count === 1 && !Backend.loadingConvs, "failed account blocks successful results")
                Backend.selectUnified()
                test.list("gmail",[test.row("g1")])
                test.feed({type:"authRequired",account:"work",operation:"conversations"})
                test.check(Backend.convs.count === 1 && !Backend.loadingConvs, "expired account blocks successful results")
                Backend.selectAccount("gmail")
                test.feed({type:"folders",account:"gmail",folders:[{id:"INBOX",name:"Inbox",role:"inbox"}]})
                test.list("gmail",[test.row("g1"),test.row("g2")],true)
                test.check(Backend.convs.count === 2 && !Backend.loadingConvs, "single account ignores cache")
            } else if (test.phase === 3) {
                index.toTop(); index.move(1)
                test.list("gmail",[test.row("g0"),test.row("g1"),test.row("g2")],false,"page2")
            } else if (test.phase === 4) {
                test.check(index.current().tid === "g2", "single-account refresh changes selected message to " + index.current().tid)
                Backend.loadMore()
                test.list("gmail",[test.row("g2"),test.row("g3")])
                test.check(Backend.convs.count === 4 && Backend.findRow("g3") >= 0 && !Backend.loadingConvs, "pagination duplicates or drops rows")
                Backend.loadMore()
                test.failure("gmail")
                test.check(!Backend.loadingConvs && Backend.convs.count === 4, "single-account error drops rows or hangs")
                test.list("gmail",[])
                test.list("gmail",[test.row("stale-empty")],true)
                test.check(Backend.convs.count === 0, "late cache repopulates a fresh empty folder")
                Backend.selectUnified()
                test.list("gmail",[test.row("g1")],false,"page2")
                test.list("work",[test.row("w1")])
                Backend.loadMore()
                test.failure("gmail")
                Backend.loadMore()
                test.check(Backend.convs.count === 2, "failed merged page discards existing mail")
                test.list("gmail",[test.row("g3")])
                test.check(Backend.convs.count === 3 && !Backend.loadingConvs, "merged page retry drops existing rows")
                console.log("PASS: immediate cached/partial mail, failed and expired accounts, stable cursor/read grace, late cache and pagination")
                Qt.quit()
            }
            test.phase++
        }
    }
}
