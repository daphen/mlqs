import QtQuick
import QsLib

// Cockpit's raised, bevelled sheet (chin, cards, pickers).
Item {
    id: sheet
    property int radius: 18
    readonly property color cardTop: Theme.mode === "light" ? "#FFFFFF" : Qt.lighter(Theme.surface0, 1.25)
    readonly property color cardBottom: Theme.mode === "light" ? "#FDFDFD" : Qt.lighter(Theme.surface0, 1.2)
    ContrastCard {
        anchors.fill: parent
        cardRadius: sheet.radius
        faceTop: Theme.mode === "light" ? sheet.cardBottom : sheet.cardTop
        faceUpper: faceTop
        faceMid: sheet.cardBottom
        faceBottom: faceMid
    }
    LightKey {
        anchors.fill: parent
        visible: Theme.mode === "light"
        radius: sheet.radius
        outline: Qt.alpha(Theme.fg, 0.16)
    }
}
