import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Teklif PDF'inin son sayfasindaki "Satış Sözleşmesi" maddelerini goruntuleyip
// duzenlemek icin acilan pencere ("Satış Sözleşmesi" butonu bunu acar).
//
// Metin bicimi kasitli olarak DUZ METINDIR (bkz.
// TeklifPdfOlusturucu::varsayilanSozlesmeMetni): her satir numarali bir madde
// olur, "- " ile baslayan satirlar ustundeki maddenin alt maddesi olur. Boylece
// kullanici HTML bilmeden PDF'teki maddeleri degistirebiliyor.
//
// Pencere metni KENDISI KAYDETMEZ: "Kaydet"e basilinca sadece kaydedildi()
// sinyalini yayinlar, kalici kayit/teklife baglama isini acan ekran yapar
// (bkz. TeklifVerPage.qml).
Dialog {
    id: kok

    // Pencere acilirken gosterilecek metin (teklife kayitli metin veya
    // varsayilan). Acan ekran her acilista bunu doldurur.
    property string metin: ""

    // "Varsayılana Dön" butonunun yazacagi fabrika metni (dile gore degisir).
    property string varsayilanMetin: ""

    // Kabul edilmis / tamamlanmis teklifte sozlesme yalnizca okunur: metin
    // degistirilemez, "Varsayılana Dön" ve "Kaydet" gizlenir.
    property bool saltOkunur: false

    // Kullanici "Kaydet"e bastiginda, duzenlenmis metinle yayinlanir.
    signal kaydedildi(string yeniMetin)

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 80 : 820, 820)
    height: Math.min(parent ? parent.height - 60 : 640, 660)
    padding: 20

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    // Her acilista metin alani, acan ekranin verdigi metinle bastan doldurulur --
    // onceki oturumdan kalan yarim duzenleme tasinmasin.
    onOpened: {
        metinAlani.text = kok.metin
        if (!kok.saltOkunur)
            metinAlani.forceActiveFocus()
    }

    header: RowLayout {
        spacing: 8
        Item { Layout.preferredWidth: 12 }
        Rectangle {
            Layout.topMargin: 18
            Layout.preferredWidth: 4
            Layout.preferredHeight: 16
            radius: 2
            color: Theme.vurgu
        }
        Label {
            Layout.topMargin: 18
            Layout.fillWidth: true
            text: "Satış Sözleşmesi"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
        }
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
                    color: Theme.metinBirincil
                    placeholderTextColor: Theme.metinCokSoluk
                    placeholderText: "Sözleşme maddelerini buraya yazın..."
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    // Madde sayisi arttikca satirlarin birbirine girmemesi icin
                    // biraz nefes payi: PDF'teki madde araligina benzer bir okuma
                    // ritmi veriyor.
                    topPadding: 2
                    bottomPadding: 2
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 10

            Button {
                id: varsayilanButonu
                visible: !kok.saltOkunur
                Layout.preferredWidth: 150
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Varsayılana Dön"
                // Metni geri almak icin bir sonraki adim yok: kullanici yanlislikla
                // basarsa "İptal" ile pencereyi kapatip degisiklikleri atabilir.
                onClicked: metinAlani.text = kok.varsayilanMetin
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: varsayilanButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: varsayilanButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    text: varsayilanButonu.text
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
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
                Layout.preferredWidth: 150
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Sözleşmeyi Kaydet"
                onClicked: {
                    kok.kaydedildi(metinAlani.text)
                    kok.close()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
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
