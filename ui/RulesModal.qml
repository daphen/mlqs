import QtQuick
import "."
import QsLib

// Filter rules: review, delete, and add. Rules hide matching mail from the list
// AND from notifications (the daemon owns matching, so both are covered).
//
// Opened bare with `z` to review; opened with a seed (from `m` on a row, or `F` on
// a selection) it shows candidates first, each with how much it would hide — which
// is the difference between hiding one bot and hiding all of GitHub.
Modal {
    id: rm
    panelWidth: Math.round(Math.min(680, rm.width - 64))
    maxHeightFrac: 0.8
    panelColor: Theme.bg
    chinBar: true

    readonly property string titleFont: Qt.fontFamilies().indexOf("Sigurd") >= 0 ? "Sigurd" : "Instrument Serif"

    property var rules: Backend.rules
    property var candidates: []       // [{label, senderEmail, senderName, subject, exact}]
    property var seedRows: []         // the rows a candidate is measured against
    property string note: ""         // why there are no AI candidates, when there aren't

    // Nav space: [candidates…, rules…, the add row]. One integer cursor over the
    // whole thing, same shape as SummarizeSetup.
    property int sel: 0
    readonly property int nCand: candidates.length
    readonly property int nRule: (rules || []).length
    readonly property int addRow: nCand + nRule
    readonly property int navCount: nCand + nRule + 1

    function showFor(rows) {
        seedRows = rows || []
        candidates = Backend.localCandidates(seedRows)
        note = ""
        sel = 0
        show()
        if (seedRows.length > 1) Backend.suggestRules(seedRows)   // the model adds fuzzier ones
    }
    function showAll() { seedRows = []; candidates = []; note = ""; sel = 0; show() }

    Connections {
        target: Backend
        function onRuleCandidates(cands, n) {
            if (!rm.open) return
            // merge the model's suggestions after the local ones, skipping duplicates
            const seen = {}
            const key = c => (c.senderEmail || "") + "|" + (c.senderName || "") + "|" + (c.subject || "")
            const out = []
            for (const c of rm.candidates) { seen[key(c)] = true; out.push(c) }
            for (const c of (cands || [])) if (!seen[key(c)]) out.push(c)
            rm.candidates = out
            rm.note = n || ""
        }
    }

    function addCandidate(c) {
        Backend.addRule({ senderEmail: c.senderEmail || "", senderName: c.senderName || "",
                          subject: c.subject || "", exact: !!c.exact })
        rm.close()
    }
    function activate() {
        if (rm.sel < rm.nCand) { rm.addCandidate(rm.candidates[rm.sel]); return }
        if (rm.sel < rm.addRow) { Backend.deleteRule(rm.rules[rm.sel - rm.nCand].id); return }
        rm.addManual()
    }
    function addManual() {
        const e = emailInput.text.trim(), n = nameInput.text.trim(), s = subjInput.text.trim()
        if (!e.length && !n.length && !s.length) return   // never save a rule that hides everything
        Backend.addRule({ senderEmail: e, senderName: n, subject: s, exact: false })
        emailInput.text = ""; nameInput.text = ""; subjInput.text = ""
        rm.close()
    }

    // Inert while a field has focus — without this guard the Modal's own defaults
    // eat typing (`q` closes it, `j`/`k` scroll it).
    onKeyPressed: e => {
        if (emailInput.activeFocus || nameInput.activeFocus || subjInput.activeFocus) return
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down)    { rm.sel = Math.min(rm.sel + 1, rm.navCount - 1); e.accepted = true }
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { rm.sel = Math.max(rm.sel - 1, 0); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { rm.activate(); e.accepted = true }
        else if (e.key === Qt.Key_I) { emailInput.forceActiveFocus(); e.accepted = true }
        else if (e.key === Qt.Key_D && rm.sel >= rm.nCand && rm.sel < rm.addRow) {
            Backend.deleteRule(rm.rules[rm.sel - rm.nCand].id); e.accepted = true
        }
    }

    header: Item {
        width: parent.width; height: 40
        Text {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: -2
            text: "Filters"; color: Theme.fg
            font.family: rm.titleFont; font.pixelSize: 30; font.weight: 400
            font.capitalization: Font.AllUppercase; font.letterSpacing: -0.3
        }
        Text {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
            text: rm.nRule + " rule" + (rm.nRule === 1 ? "" : "s")
            color: Theme.fg_muted
            font.family: Theme.fontFamily; font.pixelSize: 12
        }
    }

    // one-line description of a rule/candidate's fields
    function describe(r) {
        const p = []
        if (r.senderEmail) p.push("from " + r.senderEmail)
        if (r.senderName) p.push("named " + r.senderName)
        if (r.subject) p.push('subject "' + r.subject + '"')
        return p.join("  ·  ") || "(empty)"
    }

    component RowBox: Rectangle {
        property bool on: false
        width: parent.width; height: 46
        radius: Theme.radiusSm
        color: on ? Theme.selection : "transparent"
        border.width: 1
        border.color: on ? Theme.fg_muted : Theme.hairline
    }

    Column {
        width: parent.width
        spacing: 14

        // ── candidates (only when seeded from a row or a selection) ──────────
        Column {
            width: parent.width; spacing: 6
            visible: rm.nCand > 0
            Text {
                text: rm.seedRows.length > 1
                      ? "What these " + rm.seedRows.length + " messages have in common"
                      : "Hide mail like this"
                color: Theme.fg_secondary
                font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: 600
            }
            Repeater {
                model: rm.candidates
                RowBox {
                    required property var modelData
                    required property int index
                    on: rm.sel === index
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: modelData.label || rm.describe(modelData)
                            color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: 500
                        }
                        Text {
                            text: rm.describe(modelData)
                            color: Theme.fg_muted
                            font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    // blast radius, computed locally and instantly
                    Text {
                        readonly property var reach: Backend.candidateReach(modelData, rm.seedRows)
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: reach.sel + "/" + reach.selTotal + " selected  ·  hides " + reach.view + " in view"
                        color: reach.view > reach.sel ? Theme.yellow : Theme.fg_muted
                        font.family: Theme.fontFamily; font.pixelSize: 11
                    }
                    TapHandler { onTapped: rm.addCandidate(modelData) }
                }
            }
            Text {
                visible: rm.note !== ""
                width: parent.width
                text: rm.note
                color: Theme.fg_muted
                font.family: Theme.fontFamily; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        // ── existing rules ──────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 6
            Text {
                text: "Active filters"
                color: Theme.fg_secondary
                font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: 600
            }
            Text {
                visible: rm.nRule === 0
                text: "None yet — select some mail and press F, or add one below."
                color: Theme.fg_muted
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
            Repeater {
                model: rm.rules
                RowBox {
                    required property var modelData
                    required property int index
                    on: rm.sel === rm.nCand + index
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: rm.describe(modelData) + (modelData.exact ? "   (exact)" : "")
                        color: Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    KeyCap {
                        text: "d"; small: true; ghost: true
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rm.sel === rm.nCand + index
                    }
                    TapHandler { onTapped: Backend.deleteRule(modelData.id) }
                }
            }
        }

        // ── add by hand ─────────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 6
            Text {
                text: "Add a filter  ·  fields are combined (all must match)"
                color: Theme.fg_secondary
                font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: 600
            }
            RowBox {
                on: rm.sel === rm.addRow
                height: 112
                Column {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 6
                    Field { id: emailInput; label: "From" }
                    Field { id: nameInput; label: "Name" }
                    Field { id: subjInput; label: "Subject" }
                }
            }
        }
    }

    component Field: Rectangle {
        property alias text: fi.text
        property string label: ""
        width: parent.width; height: 28
        radius: Theme.radiusSm
        color: Theme.mode === "light" ? Theme.bg : Theme.surface2
        border.width: 1
        border.color: fi.activeFocus ? Theme.fg_muted : Theme.hairline
        Text {
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 54
            text: label; color: Theme.fg_muted
            font.family: Theme.fontFamily; font.pixelSize: 11
        }
        TextInput {
            id: fi
            anchors.left: parent.left; anchors.leftMargin: 66
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: 12
            selectByMouse: true
            Keys.onEscapePressed: { fi.focus = false; rm.sel = rm.addRow }
            onAccepted: rm.addManual()
        }
    }

    footer: Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 5
        KeyCap { anchors.verticalCenter: parent.verticalCenter; small: true; text: "j/k" }
        CapLabel { anchors.verticalCenter: parent.verticalCenter; text: "move" }
        Item { width: 9; height: 1 }
        KeyCap { anchors.verticalCenter: parent.verticalCenter; small: true; text: "↵" }
        CapLabel { anchors.verticalCenter: parent.verticalCenter; text: "apply" }
        Item { width: 9; height: 1 }
        KeyCap { anchors.verticalCenter: parent.verticalCenter; small: true; text: "i" }
        CapLabel { anchors.verticalCenter: parent.verticalCenter; text: "fields" }
        Item { width: 9; height: 1 }
        KeyCap { anchors.verticalCenter: parent.verticalCenter; small: true; text: "d" }
        CapLabel { anchors.verticalCenter: parent.verticalCenter; text: "delete" }
    }
}
