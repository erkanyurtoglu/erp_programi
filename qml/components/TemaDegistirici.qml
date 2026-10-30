import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Acik / koyu tema anahtari: solda gunes, sagda ay; mavi topuz secili temanin
// uzerine kayar. Tiklaninca Main.qml yumusak gecisle temayi degistirir
// (bkz. Theme.degistirmeIstendi).
Rectangle {
    id: kok
    implicitWidth: 64
    implicitHeight: 32
    radius: height / 2
    color: alan.containsMouse ? Theme.panelHover : Theme.panel
    border.width: 1
    border.color: alan.containsMouse ? Theme.kenarlikVurguSoluk : Theme.kenarlik

    ToolTip.visible: alan.containsMouse
    ToolTip.delay: 500
    ToolTip.text: Theme.koyuMod ? "Açık temaya geç" : "Koyu temaya geç"

    Rectangle {
        id: topuz
        y: 3
        x: Theme.koyuMod ? kok.width - width - 3 : 3
        width: kok.height - 6
        height: width
        radius: width / 2
        color: Theme.vurgu

        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    ModulIkonu {
        x: topuz.width / 2 + 3 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        tur: "gunes"
        renk: Theme.koyuMod ? Theme.metinSoluk : "#ffffff"
    }

    ModulIkonu {
        x: kok.width - topuz.width / 2 - 3 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        tur: "ay"
        renk: Theme.koyuMod ? "#ffffff" : Theme.metinSoluk
    }

    MouseArea {
        id: alan
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Theme.degistirmeIstendi()
    }
}
