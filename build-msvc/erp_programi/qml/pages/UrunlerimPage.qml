import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Urunlerim ekrani: WPF'teki Urunlerim + UrunEkle/UrunDetayWindow ikilisinin
// Qt/QML karsiligi. Sayfalama SQL Server tarafinda yapilir
// (Database::urunListesiGetir), ayni GecmisTekliflerPage/MusterilerimPage deseni.
//
// NOT: Yeni semada fiyat tek para biriminde (TL) tutuluyor (goc kararinda
// alindigi gibi); WPF'teki gibi ayrica sabit Dolar/Euro fiyat sutunlari YOK --
// gerekirse Teklif Ver ekranindaki gibi elle girilen kur ile ceviri yapilir.
Item {
    id: root

    // Dialog formlarinda tekrar eden alan stili.
    component FormAlani: TextField {
        Layout.fillWidth: true
        color: Theme.metinBirincil
        placeholderTextColor: Theme.metinCokSoluk
        font.family: Theme.fontAilesi
        background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
    }

    readonly property int sayfaBoyutu: 50

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlarListesi: []
    property string aramaMetni: ""

    // Bkz. MusterilerimPage.qml'deki ayni not: SatisModuluPage tum sekmeleri
    // ANINDA olusturur, otomatikYukle false ise burada sorgu atilmaz -- yukleme
    // sekmeye gercekten gecince yapilir.
    property bool otomatikYukle: true

    function paraFormat(deger) {
        return deger.toLocaleString(Qt.locale("tr_TR"), 'f', 2)
    }

    function sayfayiYukle(sayfaNo) {
        const sonuc = database.urunListesiGetir(aramaMetni, sayfaNo, sayfaBoyutu)
        sayfaSonucu = sonuc
        urunListesi.model = []
        kayitlarListesi = sonuc.kayitlar
        urunListesi.model = kayitlarListesi
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle(1)

    Timer {
        id: aramaZamanlayici
        interval: 350
        onTriggered: root.sayfayiYukle(1)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Ürünlerim"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.sayfaSonucu.toplamKayit + " kayıt"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                id: silHataMesaji
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320
            }

            Button {
                id: ekleButonu
                text: "+ Ürün Ekle"
                Layout.preferredHeight: 38
                onClicked: {
                    duzenlemeDialogu.urunId = 0
                    duzenlemeDialogu.title = "Ürün Ekle"
                    urunKoduAlani.text = ""
                    kategoriAlani.text = ""
                    aciklamaAlani.text = ""
                    aciklamaEnAlani.text = ""
                    birimFiyatAlani.text = "0"
                    maliyetAlani.text = "0"
                    duzenlemeDialogu.open()
                }
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.vurgu }
                contentItem: Text {
                    text: ekleButonu.text
                    color: "#ffffff"
                    font.family: Theme.fontAilesi
                    font.bold: true
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 14
                    rightPadding: 14
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.girdiYuksekligi
            radius: Theme.radiusKucuk
            color: Theme.panel
            border.width: 1
            border.color: aramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

            TextField {
                id: aramaKutusu
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                background: null
                color: Theme.metinBirincil
                placeholderTextColor: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                placeholderText: "Ürün kodu, açıklama veya kategori ara..."
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: {
                    root.aramaMetni = text
                    aramaZamanlayici.restart()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 40
            color: Theme.panel
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Label { text: "ÜRÜN KODU"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 110 }
                Label { text: "KATEGORİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 130 }
                Label { text: "AÇIKLAMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "BİRİM FİYAT"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 110 }
                Label { text: "MALİYET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 100 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 130 }
            }
        }

        ListView {
            id: urunListesi
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            reuseItems: false
            model: root.kayitlarListesi

            delegate: Rectangle {
                id: satir
                required property int index
                required property var modelData

                width: ListView.view.width
                height: 48
                radius: Theme.radiusKucuk
                color: satirAlani.containsMouse ? Theme.panelHover : Theme.panel
                border.width: 1
                border.color: Theme.kenarlik
                layer.enabled: true

                MouseArea {
                    id: satirAlani
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: satir.modelData.urunKodu
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 110
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.kategori
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 130
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.urunAciklamasi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.fillHeight: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: root.paraFormat(satir.modelData.birimFiyat) + " ₺"
                        color: Theme.vurguAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 110
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: root.paraFormat(satir.modelData.maliyet) + " ₺"
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 100
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }

                    RowLayout {
                        Layout.preferredWidth: 130
                        spacing: 6

                        Button {
                            text: "Detay"
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 28
                            onClicked: {
                                duzenlemeDialogu.urunId = satir.modelData.urunId
                                duzenlemeDialogu.title = "Ürün Düzenle"
                                urunKoduAlani.text = satir.modelData.urunKodu
                                kategoriAlani.text = satir.modelData.kategori
                                aciklamaAlani.text = satir.modelData.urunAciklamasi
                                aciklamaEnAlani.text = satir.modelData.urunAciklamasiEn
                                birimFiyatAlani.text = String(satir.modelData.birimFiyat)
                                maliyetAlani.text = String(satir.modelData.maliyet)
                                duzenlemeDialogu.open()
                            }
                            background: Rectangle { radius: 5; color: "transparent"; border.width: 1; border.color: Theme.kenarlikVurgu }
                            contentItem: Text { text: "Detay"; color: Theme.vurguAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        Button {
                            id: silButonu
                            text: "Sil"
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 28
                            onClicked: silOnayDialogu.hedefId = satir.modelData.urunId
                            background: Rectangle {
                                radius: 5
                                color: silButonu.hovered ? "#3f1d24" : "transparent"
                                border.width: 1
                                border.color: silButonu.hovered ? Theme.tehlikeHover : Theme.kenarlik
                            }
                            contentItem: Text { text: "Sil"; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Button {
                id: oncekiButonu
                text: "◀ Önceki"
                enabled: root.sayfaSonucu.mevcutSayfa > 1
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa - 1)
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.panel; border.width: 1; border.color: Theme.kenarlik; opacity: oncekiButonu.enabled ? 1.0 : 0.4 }
                contentItem: Text { text: oncekiButonu.text; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: oncekiButonu.enabled ? 1.0 : 0.4 }
            }

            Label {
                text: "Sayfa " + root.sayfaSonucu.mevcutSayfa + " / " + root.sayfaSonucu.toplamSayfa
                color: Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
            }

            Button {
                id: sonrakiButonu
                text: "Sonraki ▶"
                enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa + 1)
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.panel; border.width: 1; border.color: Theme.kenarlik; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
                contentItem: Text { text: sonrakiButonu.text; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
            }
        }
    }

    // ---- Ekle / Duzenle dialogu (ayni form, urunId=0 ise "ekle" davranir) ----
    Dialog {
        id: duzenlemeDialogu
        property int urunId: 0
        modal: true
        width: 440
        anchors.centerIn: parent
        standardButtons: Dialog.Save | Dialog.Cancel

        background: Rectangle { color: Theme.panel; radius: Theme.radiusNormal; border.color: Theme.kenarlik; border.width: 1 }
        header: Label {
            text: duzenlemeDialogu.title
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
            padding: 16
        }

        function formAlani() {
            return {
                urunKodu: urunKoduAlani.text,
                kategori: kategoriAlani.text,
                urunAciklamasi: aciklamaAlani.text,
                urunAciklamasiEn: aciklamaEnAlani.text,
                birimFiyat: parseFloat(birimFiyatAlani.text) || 0,
                maliyet: parseFloat(maliyetAlani.text) || 0
            }
        }

        onAccepted: {
            const veri = formAlani()
            const sonuc = duzenlemeDialogu.urunId > 0
                ? database.urunGuncelle(duzenlemeDialogu.urunId, veri)
                : database.urunEkle(veri)
            if (sonuc.basarili)
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            else
                hataMesaji.text = sonuc.hata
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label { id: hataMesaji; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: urunKoduAlani; placeholderText: "Ürün Kodu" }
                FormAlani { id: kategoriAlani; placeholderText: "Kategori" }
            }
            FormAlani { id: aciklamaAlani; placeholderText: "Ürün Açıklaması *" }
            FormAlani { id: aciklamaEnAlani; placeholderText: "Ürün Açıklaması (İngilizce)" }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: birimFiyatAlani; placeholderText: "Birim Satış Fiyatı (TL)"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
                FormAlani { id: maliyetAlani; placeholderText: "Maliyet (TL)"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
            }
        }
    }

    Dialog {
        id: silOnayDialogu
        property int hedefId: -1
        title: "Ürünü Sil"
        modal: true
        width: 320
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No
        visible: hedefId !== -1

        background: Rectangle { color: Theme.panel; radius: Theme.radiusNormal; border.color: Theme.kenarlik; border.width: 1 }

        contentItem: Label {
            text: "Bu ürün kalıcı olarak silinecek. Bu ürünü içeren teklifler varsa silme işlemi başarısız olur. Emin misiniz?"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            wrapMode: Text.WordWrap
            width: silOnayDialogu.availableWidth
        }

        onAccepted: {
            const sonuc = database.urunSil(hedefId)
            hedefId = -1
            if (sonuc.basarili) {
                silHataMesaji.text = ""
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            } else {
                silHataMesaji.text = sonuc.hata
            }
        }
        onRejected: hedefId = -1
    }
}
