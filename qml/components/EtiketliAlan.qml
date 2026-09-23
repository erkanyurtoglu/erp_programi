import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Ustunde kucuk bir etiket bulunan tek satirlik form girdisi (dialog formlari).
// Sayi girisi icin: SayiBicimlendirici { hedef: alanId.alan }
ColumnLayout {
    id: kok

    property string etiket: ""
    property alias text: girdi.text
    property alias placeholderText: girdi.placeholderText
    property alias echoMode: girdi.echoMode
    property alias alan: girdi

    // Enter'a basilinca.
    signal kabulEdildi()

    Layout.fillWidth: true
    spacing: 4

    Label {
        visible: kok.etiket.length > 0
        text: kok.etiket
        color: Theme.metinSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    TextField {
        id: girdi
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.girdiYuksekligi
        leftPadding: 12
        rightPadding: 12
        color: Theme.metinBirincil
        placeholderTextColor: Theme.metinCokSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutNormal
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true
        onAccepted: kok.kabulEdildi()
        background: Rectangle {
            color: Theme.arkaplan
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: girdi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
        }
    }
}
