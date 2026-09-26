import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Teklif notu / uretim notu icin acilan not penceresi. Notlar ekranda kalici bir
// metin kutusu olarak yer kaplamasin diye, kucuk bir butona basilinca bu pencerede
// cok satirli olarak yazilir/okunur (bkz. TeklifVerPage.qml, GecmisTekliflerPage.qml).
//
// SozlesmeDuzenleDialog gibi pencere metni KENDISI KAYDETMEZ: "Kaydet"e basilinca
// kaydedildi() sinyalini yayinlar; veritabanina yazma isini acan ekran yapar.
Dialog {
    id: kok

    // Pencere basligi ("Teklif Notu", "Teklif 1203/Rev.2 — Üretim Notu" vb.).
    property string baslik: ""

    // Notun kime gorundugunu soyleyen kisa bilgi satiri (PDF'e basilir/basilmaz).
    property string bilgi: ""

    // Pencere acilirken gosterilecek metin. Acan ekran her acilista doldurur.
    property string metin: ""

    // Notun rengi: teklif notu vurgu (mavi), uretim notu basari (yesil).
    property color renk: Theme.vurgu

    property string yerTutucu: "Notunuzu buraya yazın..."

    // Kilitli teklifte ya da yalnizca goruntuleme amacli acildiginda.
    property bool saltOkunur: false

    // Veritabanindaki sutunlar NVARCHAR(1000).
    readonly property int azamiUzunluk: 1000

    signal kaydedildi(string yeniMetin)

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 80 : 560, 560)
    height: Math.min(parent ? parent.height - 60 : 420, 420)
    padding: 20

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    // Her acilista metin bastan doldurulur -- "İptal" ile atilan yarim duzenleme
    // bir sonraki acilisa tasinmasin.
    onOpened: {
        metinAlani.text = kok.metin
        if (!kok.saltOkunur) {
            metinAlani.cursorPosition = metinAlani.length
            metinAlani.forceActiveFocus()
        }
    }

    header: ColumnLayout {
        spacing: 4

        RowLayout {
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 18
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 4
                Layout.preferredHeight: 16
                radius: 2
                color: kok.renk
            }
            Label {
                Layout.fillWidth: true
                text: kok.baslik
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.bold: true
                font.pixelSize: Theme.fontBoyutOrta
                elide: Text.ElideRight
            }
        }
        Label {
            visible: kok.bilgi.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 20
            text: kok.bilgi
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            wrapMode: Text.WordWrap
        }
        Item { Layout.preferredHeight: 2 }
    }

    contentItem: ColumnLayout {
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusKucuk
            color: Theme.arkaplan
            border.width: 1
            border.color: metinAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

            ScrollView {
                anchors.fill: parent
                anchors.margins: 8
                clip: true

                TextArea {
                    id: metinAlani
                    readOnly: kok.saltOkunur
                    background: null
                    color: kok.saltOkunur ? Theme.metinIkincil : Theme.metinBirincil
                    placeholderTextColor: Theme.metinCokSoluk
                    placeholderText: kok.saltOkunur ? "Not yok." : kok.yerTutucu
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // TextArea'nin maximumLength'i yok; sinir sayacla gosterilir ve
            // asildiginda kaydetme engellenir.
            Label {
                visible: !kok.saltOkunur
                text: metinAlani.length + " / " + kok.azamiUzunluk
                color: metinAlani.length > kok.azamiUzunluk ? Theme.tehlikeAcik : Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }

            Item { Layout.fillWidth: true }

            Button {
                id: iptalButonu
                Layout.preferredWidth: 110
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: kok.saltOkunur ? "Kapat" : "İptal"
                onClicked: kok.close()
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: iptalButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: iptalButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    text: iptalButonu.text
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                id: kaydetButonu
                visible: !kok.saltOkunur
                enabled: metinAlani.length <= kok.azamiUzunluk
                Layout.preferredWidth: 130
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Notu Kaydet"
                onClicked: {
                    kok.kaydedildi(metinAlani.text.trim())
                    kok.close()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    opacity: kaydetButonu.enabled ? 1 : 0.4
                    color: kaydetButonu.hovered ? Theme.vurguHover : Theme.vurgu
                }
                contentItem: Text {
                    text: kaydetButonu.text
                    color: "#ffffff"
                    font.family: Theme.fontAilesi
                    font.bold: true
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
