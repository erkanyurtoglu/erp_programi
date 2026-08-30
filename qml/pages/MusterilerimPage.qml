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

    // Dialog formlarinda tekrar eden alan stili -- dosyanin en ustunde, root'un
    // dogrudan cocugu olarak tanimlaniyor (bkz. TeklifVerPage.qml'deki ayni kural).
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
                onClicked: {
                    duzenlemeDialogu.musteriId = 0
                    duzenlemeDialogu.title = "Müşteri Ekle"
                    firmaAdAlani.text = ""
                    firmaAdresAlani.text = ""
                    firmaTelAlani.text = ""
                    firmaEpostaAlani.text = ""
                    vergiNoAlani.text = ""
                    vergiDairesiAlani.text = ""
                    ilgiliKisiAlani.text = ""
                    ilgiliKisiTelAlani.text = ""
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
                            text: "Detay"
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 28
                            onClicked: {
                                duzenlemeDialogu.musteriId = satir.modelData.musteriId
                                duzenlemeDialogu.title = "Müşteri Düzenle"
                                firmaAdAlani.text = satir.modelData.firmaAdi
                                firmaAdresAlani.text = satir.modelData.firmaAdresi
                                firmaTelAlani.text = satir.modelData.firmaTelefonu
                                firmaEpostaAlani.text = satir.modelData.firmaEposta
                                vergiNoAlani.text = satir.modelData.vergiNumarasi
                                vergiDairesiAlani.text = satir.modelData.vergiDairesi
                                ilgiliKisiAlani.text = satir.modelData.ilgiliKisi
                                ilgiliKisiTelAlani.text = satir.modelData.ilgiliKisiTelefonu
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
                            onClicked: silOnayDialogu.hedefId = satir.modelData.musteriId
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

    // ---- Ekle / Duzenle dialogu (ayni form, musteriId=0 ise "ekle" davranir) ----
    Dialog {
        id: duzenlemeDialogu
        property int musteriId: 0
        modal: true
        width: 420
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

        onAccepted: {
            const veri = formAlani()
            const sonuc = duzenlemeDialogu.musteriId > 0
                ? database.musteriGuncelle(duzenlemeDialogu.musteriId, veri)
                : database.musteriEkle(veri)
            if (sonuc.basarili)
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            else
                hataMesaji.text = sonuc.hata
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label { id: hataMesaji; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            FormAlani { id: firmaAdAlani; placeholderText: "Firma Adı *" }
            FormAlani { id: firmaAdresAlani; placeholderText: "Firma Adresi" }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: firmaTelAlani; placeholderText: "Firma Telefonu" }
                FormAlani { id: firmaEpostaAlani; placeholderText: "Firma E-posta" }
            }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: vergiNoAlani; placeholderText: "Vergi Numarası" }
                FormAlani { id: vergiDairesiAlani; placeholderText: "Vergi Dairesi" }
            }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: ilgiliKisiAlani; placeholderText: "İlgili Kişi" }
                FormAlani { id: ilgiliKisiTelAlani; placeholderText: "İlgili Kişi Telefonu" }
            }
        }
    }

    Dialog {
        id: silOnayDialogu
        property int hedefId: -1
        title: "Müşteriyi Sil"
        modal: true
        width: 320
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No
        visible: hedefId !== -1

        background: Rectangle { color: Theme.panel; radius: Theme.radiusNormal; border.color: Theme.kenarlik; border.width: 1 }

        contentItem: Label {
            text: "Bu müşteri kalıcı olarak silinecek. Bu müşteriye ait teklifler varsa silme işlemi başarısız olur. Emin misiniz?"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            wrapMode: Text.WordWrap
            width: silOnayDialogu.availableWidth
        }

        onAccepted: {
            const sonuc = database.musteriSil(hedefId)
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
