import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Etiketsiz, temaya uygun tek satirlik metin kutusu (tablo hucreleri ve
// satir ici alanlar icin; ustunde etiket isteyen formlar EtiketliAlan
// kullanir).
TextField {
    id: kok

    property bool kompakt: false
    // Zorunlu ama bos: kenarlik uyari renginde.
    property bool eksik: false

    implicitHeight: kok.kompakt ? 32 : Theme.girdiYuksekligi
    leftPadding: 10
    rightPadding: 10
    color: Theme.metinBirincil
    placeholderTextColor: Theme.metinCokSoluk
    font.family: Theme.fontAilesi
    font.pixelSize: kok.kompakt ? Theme.fontBoyutKucuk + 1 : Theme.fontBoyutNormal
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radiusKucuk
        color: kok.enabled ? Theme.arkaplan : "transparent"
        border.width: kok.enabled ? 1 : 0
        border.color: kok.activeFocus ? Theme.kenarlikVurgu
                    : kok.eksik ? Theme.uyari : Theme.kenarlik
    }
}
