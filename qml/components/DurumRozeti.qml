import QtQuick
import QtQuick.Controls
import erp_programi

// Durum etiketi (hap seklinde). Rengi metne gore SatinalmaBicim'den gelir,
// isteyen cagiran taraf "renk" ile ezer.
Rectangle {
    id: kok

    property string metin: ""
    property color renk: Theme.metinIkincil
    property bool dolu: false

    implicitWidth: yazi.implicitWidth + 18
    implicitHeight: 22
    radius: 11
    color: kok.dolu ? Qt.rgba(kok.renk.r, kok.renk.g, kok.renk.b, 0.16) : "transparent"
    border.width: 1
    border.color: Qt.rgba(kok.renk.r, kok.renk.g, kok.renk.b, 0.7)

    Text {
        id: yazi
        anchors.centerIn: parent
        text: kok.metin
        color: kok.renk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 0.3
    }
}
