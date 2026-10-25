import QtQuick
import QtQuick.Controls
import erp_programi

// Liste ekranlarinin ust kismindaki suzgec (filtre) hapi. sayi > 0 ise
// yaninda renkli sayac gosterilir.
Rectangle {
    id: kok

    property string metin: ""
    property bool secili: false
    property int sayi: 0
    property color renk: Theme.vurgu
    signal tiklandi()

    implicitWidth: satir.implicitWidth + 26
    implicitHeight: Theme.girdiYuksekligi
    radius: Theme.radiusKucuk
    color: kok.secili ? Theme.vurguZeminSoluk : (fare.containsMouse ? Theme.panelHover : Theme.panel)
    border.width: 1
    border.color: kok.secili ? Theme.vurgu : Theme.kenarlik

    Row {
        id: satir
        anchors.centerIn: parent
        spacing: 7
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: kok.metin
            color: kok.secili ? Theme.metinBirincil : Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
            font.bold: kok.secili
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: kok.sayi > 0
            width: Math.max(20, sayiYazi.implicitWidth + 10)
            height: 18
            radius: 9
            color: Qt.rgba(kok.renk.r, kok.renk.g, kok.renk.b, 0.2)
            Text {
                id: sayiYazi
                anchors.centerIn: parent
                text: kok.sayi
                color: kok.renk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.bold: true
            }
        }
    }

    MouseArea {
        id: fare
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: kok.tiklandi()
    }
}
