// `?` from any non-insert mode: a full keybind reference across every mode.
// Built on the QsLib Modal shell (scrim / panel / scroll / keys / chrome live
// there); this file owns only the content and the `/` fuzzy-filter. Responsive
// column count.
import QtQuick
import "."
import QsLib

Modal {
    id: sheet
    z: 100
    panelWidth: Math.min(sheet.colCount === 1 ? 460 : sheet.colCount === 2 ? 680 : 960, sheet.width - 60)
    maxHeightFrac: 0.85

    property string query: ""
    property bool searching: false

    function resetSearch() { searching = false; query = "" }
    onOpenChanged: if (!open) resetSearch()

    // Filter keys run before the scaffold defaults (accept → keep out of the
    // shell's scroll/close handling). `/` enters search; while searching, typing
    // edits the query and esc clears it; `?` toggles the sheet shut.
    onKeyPressed: e => {
        if (e.key === Qt.Key_Slash && !searching) { searching = true; e.accepted = true }
        else if (searching) {
            if (e.key === Qt.Key_Escape) { resetSearch(); e.accepted = true }
            else if (e.key === Qt.Key_Backspace) { query = query.slice(0, -1); e.accepted = true }
            else if (e.text && e.text.length === 1 && e.text.charCodeAt(0) >= 0x20) { query += e.text; e.accepted = true }
        } else if (e.text === "?") { close(); e.accepted = true }
    }

    // Flat ordered sections: { title, rows: [ [ [keys…], description ] … ] }.
    readonly property var sections: [
        { title: "Normal", rows: [
            [["j"], "Down (count: 8j)"], [["k"], "Up"],
            [["↵"], "Open conversation"], [["l"], "Open / focus index"],
            [["h"], "Focus sidebar"], [["g", "g"], "Jump to top"], [["⇧g"], "Jump to bottom"],
            [["x"], "Star"], [["e"], "Archive"], [["d", "d"], "Trash"], [["u"], "Undo last remove"],
            [["v"], "Visual select"], [["r"], "Toggle read"], [["⇧r"], "Refresh"],
            [["⇧u"], "Apply update (when available)"],
            [["n"], "Compose"], [["/"], "Search"], [["q"], "Hide window"],
        ]},
        { title: "Go to", rows: [
            [["⇧i"], "Inbox"], [["⇧t"], "Threads"], [["⇧c"], "Calendar"],
            [["g", "i"], "Inbox"], [["g", "⇧i"], "Starred"], [["g", "s"], "Sent"],
            [["g", "⇧s"], "Spam"], [["g", "d"], "Drafts"], [["g", "t"], "Threads"],
            [["g", "⇧t"], "Trash"], [["g", "c"], "Calendar"],
        ]},
        { title: "Conversation", rows: [
            [["j"], "Scroll down"], [["k"], "Scroll up"],
            [["⇧j"], "Next message"], [["⇧k"], "Previous message"],
            [["↵"], "Cursor in message"], [["v"], "Visual select in message"],
            [["y"], "Yank hints (invites: accept)"], [["⇧y"], "Copy whole message"],
            [["m"], "RSVP tentative"], [["n"], "RSVP decline"],
            [["i"], "Reply"], [["a"], "Toggle reply-all"], [["r"], "Reply to focused"],
            [["⇧f"], "Forward"], [["f"], "Link hints"], [["o"], "Open in browser"],
            [["e"], "Archive"], [["d", "d"], "Trash"],
            [["h"], "Close"], [["q"], "Back to inbox"],
        ]},
        { title: "Visual — index", rows: [
            [["j", "k"], "Extend selection"], [["e"], "Archive selection"],
            [["d"], "Trash selection"], [["r"], "Mark read"], [["x"], "Star"],
            [["⌃d", "⌃u"], "Half-page (extends)"], [["esc"], "Exit"],
        ]},
        { title: "Message cursor", rows: [
            [["↵"], "Enter message (auto if single)"],
            [["h", "l"], "Char left / right"], [["j", "k"], "Line down / up (counts: 12j)"],
            [["w", "b", "e"], "Word forward / back / end"],
            [["⇧w", "⇧b", "⇧e"], "WORD (whitespace-delimited)"],
            [["0", "^", "$"], "Line start / first char / end"], [["g", "⇧g"], "Text start / end"],
            [["v"], "Visual select"], [["⇧v"], "Line select"],
            [["⌃d", "⌃u"], "Half-page cursor move"], [["⌃e", "⌃y"], "Scroll view"],
            [["o"], "Swap anchor / cursor"],
            [["y"], "Yank selection / image / token hints"],
            [["y", "y"], "Copy whole message"], [["⇧y"], "Copy whole message"],
            [["esc"], "Drop selection / back"],
        ]},
        { title: "Yank mode", rows: [
            [["a", "s", "d", "…"], "Pick a label to copy it"],
            [["y"], "Copy whole message"],
            [["esc"], "Cancel"],
        ]},
        { title: "Calendar", rows: [
            [["j", "k"], "Move"], [["↵"], "Open event"], [["o"], "Open in browser"],
            [["y", "m", "n"], "RSVP"], [["⇧n"], "New event"], [["s"], "Cycle span"],
            [["⇥"], "Filter calendar (⇧⇥ back)"], [["x"], "Hide / show filtered calendar"],
            [["r"], "Refresh"],
        ]},
        { title: "Global", rows: [
            [["⌃d", "⌃u"], "Half-page down / up"], [["⌃h", "⌃l"], "Sidebar / index"],
            [["⌃s"], "Account menu (j/k, ↵)"], [["⌃⇧h", "⌃⇧l"], "Prev / next account"],
            [["⌃⇧r"], "Check for updates"], [["?"], "This cheat sheet"],
        ]},
        { title: "Insert", rows: [
            [["⌃↵"], "Send"], [["⌃o"], "Attach clipboard path"], [["esc"], "Discard / exit"],
        ]},
    ]

    // Sections with rows filtered by the query (match description or any key);
    // sections with no surviving rows drop out.
    readonly property var filtered: {
        const q = query.trim().toLowerCase()
        if (!q) return sections
        const out = []
        for (const s of sections) {
            const rows = s.rows.filter(r =>
                r[1].toLowerCase().indexOf(q) >= 0
                || r[0].some(k => k.toLowerCase().indexOf(q) >= 0)
                || s.title.toLowerCase().indexOf(q) >= 0)
            if (rows.length) out.push({ title: s.title, rows: rows })
        }
        return out
    }

    // Responsive: 1 / 2 / 3 columns by available width, sections packed into the
    // currently-shortest column (balanced by row count) so it reflows cleanly.
    readonly property int colCount: sheet.width < 620 ? 1 : sheet.width < 940 ? 2 : 3
    readonly property var laidOut: {
        const cols = [], load = []
        for (let i = 0; i < colCount; i++) { cols.push([]); load.push(0) }
        for (const s of filtered) {
            let t = 0
            for (let i = 1; i < colCount; i++) if (load[i] < load[t]) t = i
            cols[t].push(s)
            load[t] += s.rows.length + 2   // +2 ≈ title + spacing weight
        }
        return cols
    }

    header: Item {
        width: parent.width
        height: 40
        Column {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: "Keyboard shortcuts"
                color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: 18; font.weight: 600
            }
            Text {
                text: sheet.searching ? "type to filter · esc to clear" : "/ to search · esc or ? to close"
                color: Theme.fg_muted
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
        }
        Rectangle {
            readonly property bool showField: sheet.searching || sheet.query.length > 0
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: showField ? 220 : 0
            height: 30; radius: 8; clip: true
            color: Theme.surface1
            border.width: showField ? 1 : 0
            border.color: Theme.hairline
            visible: width > 1
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Text {   // display-only: onKeyPressed edits sheet.query
                anchors.fill: parent; anchors.margins: 8
                verticalAlignment: Text.AlignVCenter
                text: sheet.query.length ? sheet.query : "filter…"
                color: sheet.query.length ? Theme.fg : Theme.fg_muted
                font.family: Theme.fontFamily; font.pixelSize: 13
                elide: Text.ElideLeft
            }
        }
    }

    Row {
        id: cols
        width: parent.width
        spacing: 28

        Repeater {
            model: sheet.laidOut
            Column {
                required property var modelData
                width: (cols.width - cols.spacing * (sheet.colCount - 1)) / sheet.colCount
                spacing: 18

                Repeater {
                    model: parent.modelData
                    Column {
                        required property var modelData
                        width: parent.width
                        spacing: 5

                        Text {
                            text: modelData.title
                            color: Theme.fg_muted
                            font.family: Theme.fontFamily; font.pixelSize: 11
                            font.weight: 600; font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                        }
                        Repeater {
                            model: modelData.rows
                            Row {
                                required property var modelData
                                width: parent.width
                                spacing: 8
                                Row {
                                    id: keysRow
                                    spacing: 3
                                    Repeater {
                                        model: modelData[0]
                                        KeyCap {
                                            required property var modelData
                                            text: modelData
                                            small: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                                Text {
                                    width: parent.width - keysRow.width - parent.spacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[1]
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily; font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // empty-state when a filter matches nothing
    Text {
        visible: sheet.laidOut.length === 0 || sheet.filtered.length === 0
        text: "no shortcuts match “" + sheet.query + "”"
        color: Theme.fg_muted
        font.family: Theme.fontFamily; font.pixelSize: 13
    }
}
