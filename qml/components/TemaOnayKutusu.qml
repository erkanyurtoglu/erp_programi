import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Uygulama temasina uygun onay kutusu. Basic stilin acik renkli varsayilan
// gorunumu koyu temada okunmadigi icin indicator/contentItem burada bir kez
// tanimlanir; Musterilerim / Urunlerim ("Arşivi göster") ve Personellerim
// ("Pasifleri göster", rol secimi) ekranlari ayni kutuyu kullanir.
CheckBox {
    id: kok

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: kok.leftPadding
        y: (kok.height - height) / 2
        radius: 4
        color: kok.checked ? Theme.vurgu : Theme.arkaplan
        border.width: 1
        border.color: kok.checked ? Theme.vurgu
                    : (kok.hovered ? Theme.metinSoluk : Theme.kenarlik)

        Text {
            anchors.centerIn: parent
            visible: kok.checked
            text: "✓"
            color: "#ffffff"
            font.bold: true
            font.pixelSize: 12
        }
    }

    contentItem: Label {
        text: kok.text
        color: Theme.metinIkincil
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutKucuk
        leftPadding: kok.indicator.width + 6
        verticalAlignment: Text.AlignVCenter
    }
}
