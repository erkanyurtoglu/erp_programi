import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Takvimden secilen tarih kutusu. Deger her zaman "yyyy-MM-dd" ya da bos.
// Ustte etiket isteniyorsa "etiket" doldurulur.
//
// Kutu "deger"i KENDISI DEGISTIRMEZ, yalnizca secildi(tarih) yayar; degeri
// sahibi yazar. Ic atama, disaridaki "deger: kayit.tarih" baglantisini
// koparir ve baska kayda gecildiginde eski tarih ekranda kalirdi.
ColumnLayout {
    id: kok

    property string etiket: ""
    property string deger: ""
    property string bosMetin: "Tarih seçin"
    property bool temizlenebilir: true
    property bool kompakt: false
    // Kirmizi gosterilsin mi (gecikmis tarih)?
    property bool uyari: false
    // Bugunden onceki gunler secilemesin mi? (bkz. TarihTakvimi.gecmisKapali)
    property bool gecmisKapali: false

    signal secildi(string tarih)

    spacing: 4

    function goster(yyyyAaGg) {
        if (!yyyyAaGg || yyyyAaGg.length === 0)
            return ""
        const p = yyyyAaGg.split("-")
        return p.length === 3 ? p[2] + "." + p[1] + "." + p[0] : yyyyAaGg
    }

    Label {
        visible: kok.etiket.length > 0
        text: kok.etiket
        color: Theme.metinSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: kok.kompakt ? 32 : Theme.girdiYuksekligi
        radius: Theme.radiusKucuk
        color: Theme.arkaplan
        border.width: 1
        border.color: takvim.visible ? Theme.kenarlikVurgu
                    : kok.uyari ? Theme.tehlike : Theme.kenarlik

        KisalanMetin {
            anchors.left: parent.left
            anchors.right: temizle.visible ? temizle.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            text: kok.deger.length > 0 ? kok.goster(kok.deger) : kok.bosMetin
            color: kok.deger.length === 0 ? Theme.metinCokSoluk
                 : kok.uyari ? Theme.tehlikeAcik : Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: kok.kompakt ? Theme.fontBoyutKucuk + 1 : Theme.fontBoyutNormal
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: takvim.open()
        }

        Text {
            id: temizle
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: kok.temizlenebilir && kok.deger.length > 0
            text: "✕"
            color: Theme.metinSoluk
            font.pixelSize: Theme.fontBoyutKucuk

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: kok.secildi("")
            }
        }

        TarihTakvimi {
            id: takvim
            y: parent.height + 4
            gecmisKapali: kok.gecmisKapali
            onTarihSecildi: (tarih) => {
                kok.secildi(tarih)
                takvim.close()
            }
        }
    }
}
