import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Personellerim ekrani: WPF'teki Personellerim + PersonelEkle/PersonelDetayWindow
// karsiligi. Kalici silme yerine Aktif/Pasif bayragi kullanilir -- bir personel
// pasife alinirsa gecmis tekliflerdeki KullaniciId referansi bozulmaz, sadece
// giris yapamaz hale gelir (bkz. Database::girisYap -> AktifMi kontrolu).
Item {
    id: root

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
    property var rolListesi: []

    function sayfayiYukle(sayfaNo) {
        const sonuc = database.personelListesiGetir(aramaMetni, sayfaNo, sayfaBoyutu)
        sayfaSonucu = sonuc
        personelListesi.model = []
        kayitlarListesi = sonuc.kayitlar
        personelListesi.model = kayitlarListesi
    }

    Component.onCompleted: {
        rolListesi = database.rolListesiGetir()
        sayfayiYukle(1)
    }

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
                    text: "Personellerim"
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
                id: hataMesajiUst
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320
            }

            Button {
                id: ekleButonu
                text: "+ Personel Ekle"
                Layout.preferredHeight: 38
                onClicked: {
                    duzenlemeDialogu.kullaniciId = 0
                    duzenlemeDialogu.title = "Personel Ekle"
                    adSoyadAlani.text = ""
                    kullaniciAdiAlani.text = ""
                    sifreAlani.text = ""
                    sifreAlani.placeholderText = "Şifre *"
                    telefonAlani.text = ""
                    pozisyonAlani.text = ""
                    for (let i = 0; i < rolCheckboxRepeater.count; i++)
                        rolCheckboxRepeater.itemAt(i).checked = false
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
                placeholderText: "Ad soyad veya kullanıcı adı ara..."
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

                Label { text: "AD SOYAD"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 180 }
                Label { text: "KULLANICI ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 140 }
                Label { text: "ROLLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 80 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 150 }
            }
        }

        ListView {
            id: personelListesi
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
                opacity: satir.modelData.aktifMi ? 1.0 : 0.55

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
                        text: satir.modelData.adSoyad
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 180
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.kullaniciAdi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 140
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: satir.modelData.rolAdlari
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        elide: Text.ElideRight
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: 70
                        Layout.preferredHeight: 24
                        radius: 5
                        color: satir.modelData.aktifMi ? "#0f2417" : "#1e2a3f"
                        border.width: 1
                        border.color: satir.modelData.aktifMi ? Theme.basari : Theme.kenarlik
                        Text {
                            anchors.centerIn: parent
                            text: satir.modelData.aktifMi ? "Aktif" : "Pasif"
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                            color: satir.modelData.aktifMi ? Theme.basariAcik : Theme.metinSoluk
                        }
                    }

                    RowLayout {
                        Layout.preferredWidth: 150
                        spacing: 6

                        Button {
                            text: "Detay"
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 28
                            onClicked: {
                                duzenlemeDialogu.kullaniciId = satir.modelData.kullaniciId
                                duzenlemeDialogu.title = "Personel Düzenle"
                                adSoyadAlani.text = satir.modelData.adSoyad
                                kullaniciAdiAlani.text = satir.modelData.kullaniciAdi
                                sifreAlani.text = ""
                                sifreAlani.placeholderText = "Şifre (boş bırakılırsa değişmez)"
                                telefonAlani.text = satir.modelData.telefon
                                pozisyonAlani.text = satir.modelData.pozisyon
                                for (let i = 0; i < rolCheckboxRepeater.count; i++) {
                                    const kutu = rolCheckboxRepeater.itemAt(i)
                                    kutu.checked = satir.modelData.rolIdListesi.indexOf(kutu.rolId) !== -1
                                }
                                duzenlemeDialogu.open()
                            }
                            background: Rectangle { radius: 5; color: "transparent"; border.width: 1; border.color: Theme.kenarlikVurgu }
                            contentItem: Text { text: "Detay"; color: Theme.vurguAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        Button {
                            text: satir.modelData.aktifMi ? "Pasife Al" : "Aktif Et"
                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 28
                            onClicked: {
                                database.personelAktifDurumDegistir(satir.modelData.kullaniciId, !satir.modelData.aktifMi)
                                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
                            }
                            background: Rectangle {
                                radius: 5
                                color: "transparent"
                                border.width: 1
                                border.color: satir.modelData.aktifMi ? Theme.tehlike : Theme.basari
                            }
                            contentItem: Text {
                                text: satir.modelData.aktifMi ? "Pasife Al" : "Aktif Et"
                                color: satir.modelData.aktifMi ? Theme.tehlikeAcik : Theme.basariAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
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

    // ---- Ekle / Duzenle dialogu ----
    Dialog {
        id: duzenlemeDialogu
        property int kullaniciId: 0
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

        function secilenRolIdListesi() {
            const secilenler = []
            for (let i = 0; i < rolCheckboxRepeater.count; i++) {
                const kutu = rolCheckboxRepeater.itemAt(i)
                if (kutu.checked)
                    secilenler.push(kutu.rolId)
            }
            return secilenler
        }

        onAccepted: {
            const veri = {
                adSoyad: adSoyadAlani.text,
                kullaniciAdi: kullaniciAdiAlani.text,
                sifre: sifreAlani.text,
                telefon: telefonAlani.text,
                pozisyon: pozisyonAlani.text,
                rolIdListesi: secilenRolIdListesi()
            }
            const sonuc = duzenlemeDialogu.kullaniciId > 0
                ? database.personelGuncelle(duzenlemeDialogu.kullaniciId, veri)
                : database.personelEkle(veri)
            if (sonuc.basarili) {
                hataMesaji.text = ""
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            } else {
                hataMesaji.text = sonuc.hata
            }
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label { id: hataMesaji; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            FormAlani { id: adSoyadAlani; placeholderText: "Ad Soyad *" }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: kullaniciAdiAlani; placeholderText: "Kullanıcı Adı *" }
                FormAlani { id: sifreAlani; placeholderText: "Şifre *"; echoMode: TextInput.Password }
            }
            RowLayout {
                Layout.fillWidth: true
                FormAlani { id: telefonAlani; placeholderText: "Telefon" }
                FormAlani { id: pozisyonAlani; placeholderText: "Pozisyon" }
            }

            Label { text: "ROLLER"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.topMargin: 4 }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    id: rolCheckboxRepeater
                    model: root.rolListesi

                    delegate: CheckBox {
                        id: kutu
                        required property var modelData
                        readonly property int rolId: modelData.rolId
                        text: modelData.rolAdi

                        contentItem: Label {
                            text: kutu.text
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            leftPadding: kutu.indicator.width + 6
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
