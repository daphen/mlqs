pragma Singleton
import QtQuick
import QsLib

// Cockpit's window ground: bgDim lifted 3% toward fg in dark mode.
QtObject {
    readonly property color color: Theme.mode === "dark" ? Qt.tint(Theme.bgDim, Qt.alpha(Theme.fg, 0.03)) : Qt.darker(Theme.bgDim, 1.04)
}
