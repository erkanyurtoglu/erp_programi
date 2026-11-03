import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Modul yan menusunu yalnizca ikonlara daraltan / geri acan dugme. Tercih
// bilgisayarda saklanir ve tum modullerde ortaktir (Theme.yanMenuDar).
Rectangle {
    id: kok
    implicitWidth: 32
    implicitHeight: 32
    radius: Theme.radiusKucuk
    color: alan.containsMouse ? Theme.panelHover : "transparent"
    border.width: alan.containsMouse ? 1 : 0
    border.color: Theme.kenarlik

    ToolTip.visible: alan.containsMouse
    ToolTip.delay: 500
    ToolTip.text: Theme.yanMenuDar ? "Menüyü aç" : "Menüyü daralt"

    ModulIkonu {
        anchors.centerIn: parent
        width: 18
        height: 18
        tur: "menu"
        renk: alan.containsMouse ? Theme.metinBirincil : Theme.metinSoluk
    }

    MouseArea {
        id: alan
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Theme.yanMenuDar = !Theme.yanMenuDar
    }
}
