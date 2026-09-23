import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Musterilerim ekrani: WPF'teki Firmalarim + FirmaEkle/FirmaDetayWindow
// ikilisinin Qt/QML karsiligi. Sayfalama SQL Server tarafinda yapilir
// (Database::musteriListesiGetir), ayni GecmisTekliflerPage deseni.
Item {
    id: root

    readonly property int sayfaBoyutu: 50

    function formuAc(kayit) {
        duzenlemeDialogu.musteriId = kayit ? kayit.musteriId : 0
        duzenlemeDialogu.baslik = kayit ? "Müşteri Düzenle" : "Müşteri Ekle"
        hataMesaji.text = ""
        firmaAdAlani.text = kayit ? kayit.firmaAdi : ""
        firmaAdresAlani.text = kayit ? kayit.firmaAdresi : ""
        firmaTelAlani.text = kayit ? kayit.firmaTelefonu : ""
        firmaEpostaAlani.text = kayit ? kayit.firmaEposta : ""
        vergiNoAlani.text = kayit ? kayit.vergiNumarasi : ""
        vergiDairesiAlani.text = kayit ? kayit.vergiDairesi : ""
        ilgiliKisiAlani.text = kayit ? kayit.ilgiliKisi : ""
        ilgiliKisiTelAlani.text = kayit ? kayit.ilgiliKisiTelefonu : ""
        duzenlemeDialogu.open()
    }

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlarListesi: []
    property string aramaMetni: ""

    // SatisModuluPage tum sekmeleri (bu da dahil) StackLayout icinde ANINDA
    // olusturur -- gorunmese bile. otomatikYukle false ise onCompleted burada
    // sorgu atmaz; yukleme kullanici bu sekmeye gercekten gecince yapilir
    // (bkz. SatisModuluPage), boylece modul acilirken tum sekmelerin ayni anda
    // UI thread'ini bloke eden senkron sorgu atmasi onlenir.
    property bool otomatikYukle: true

    function sayfayiYukle(sayfaNo) {
        const sonuc = database.musteriListesiGetir(aramaMetni, sayfaNo, sayfaBoyutu)
        sayfaSonucu = sonuc
        musteriListesi.model = []
        kayitlarListesi = sonuc.kayitlar
        musteriListesi.model = kayitlarListesi
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
                    text: "Müşterilerim"
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
                text: "+ Müşteri Ekle"
                Layout.preferredHeight: 38
                onClicked: root.formuAc(null)
                background: Rectangle { radius: Theme.radiusKucuk; color: ekleButonu.hovered ? Theme.vurguHover : Theme.vurgu }
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
                placeholderText: "Firma adı, ilgili kişi veya e-posta ara..."
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

                Label { text: "NO"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 56 }
                Label { text: "FİRMA ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 220 }
                Label { text: "ADRES"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "TELEFON"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 140 }
                Label { text: "E-POSTA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 200 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 130 }
            }
        }

        ListView {
            id: musteriListesi
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
                        text: satir.modelData.musteriId
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 56
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.firmaAdi
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 220
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.firmaAdresi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.fillHeight: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.firmaTelefonu
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 140
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.firmaEposta
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 200
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }

                    RowLayout {
                        Layout.preferredWidth: 130
                        spacing: 6

                        Button {
                            id: detayButonu
                            text: "Detay"
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 28
                            onClicked: root.formuAc(satir.modelData)
                            background: Rectangle { radius: 5; color: detayButonu.hovered ? Theme.panelHover : "transparent"; border.width: 1; border.color: Theme.kenarlikVurgu }
                            contentItem: Text { text: "Detay"; color: Theme.vurguAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        Button {
                            id: silButonu
                            text: "Sil"
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 28
                            onClicked: {
                                const id = satir.modelData.musteriId
                                sifreDialogu.iste("Müşteriyi Sil",
                                                  "\"" + satir.modelData.firmaAdi + "\" kalıcı olarak silinsin mi?",
                                                  "Sil", true, function() { root.musteriSil(id) })
                            }
                            background: Rectangle {
                                radius: 5
                                color: silButonu.hovered ? Theme.tehlikeZeminHover : "transparent"
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

    // ---- Ekle / Duzenle dialogu (ayni form, musteriId=0 ise "ekle" davranir) ----
    TemaDialog {
        id: duzenlemeDialogu
        property int musteriId: 0
        width: 560
        onayMetni: "Kaydet"
        elleKapat: true

        function formAlani() {
            return {
                firmaAdi: firmaAdAlani.text,
                firmaAdresi: firmaAdresAlani.text,
                firmaTelefonu: firmaTelAlani.text,
                firmaEposta: firmaEpostaAlani.text,
                vergiDairesi: vergiDairesiAlani.text,
                vergiNumarasi: vergiNoAlani.text,
                ilgiliKisi: ilgiliKisiAlani.text,
                ilgiliKisiTelefonu: ilgiliKisiTelAlani.text
            }
        }

        // Kayitli musteride degisiklik yonetici sifresiyle onaylanir (yeni kayitta sorulmaz).
        onOnaylandi: {
            if (duzenlemeDialogu.musteriId > 0)
                sifreDialogu.iste("Değişiklikleri Kaydet", "", "Kaydet", false, function() { duzenlemeDialogu.kaydet() })
            else
                duzenlemeDialogu.kaydet()
        }

        function kaydet() {
            const veri = formAlani()
            const sonuc = duzenlemeDialogu.musteriId > 0
                ? database.musteriGuncelle(duzenlemeDialogu.musteriId, veri)
                : database.musteriEkle(veri)
            if (!sonuc.basarili) {
                hataMesaji.text = sonuc.hata
                return
            }
            hataMesaji.text = ""
            duzenlemeDialogu.close()
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label { id: hataMesaji; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            EtiketliAlan { id: firmaAdAlani; etiket: "FİRMA ADI *" }
            EtiketliAlan { id: firmaAdresAlani; etiket: "ADRES" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan { id: firmaTelAlani; etiket: "TELEFON" }
                EtiketliAlan { id: firmaEpostaAlani; etiket: "E-POSTA" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan { id: vergiNoAlani; etiket: "VERGİ NUMARASI" }
                EtiketliAlan { id: vergiDairesiAlani; etiket: "VERGİ DAİRESİ" }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan { id: ilgiliKisiAlani; etiket: "İLGİLİ KİŞİ" }
                EtiketliAlan { id: ilgiliKisiTelAlani; etiket: "İLGİLİ KİŞİ TELEFONU" }
            }
        }
    }

    SifreOnayDialog { id: sifreDialogu }

    function musteriSil(musteriId) {
        const sonuc = database.musteriSil(musteriId)
        if (sonuc.basarili) {
            silHataMesaji.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        } else {
            silHataMesaji.text = sonuc.hata
        }
    }
}