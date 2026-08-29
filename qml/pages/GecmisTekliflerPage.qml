import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Not: Bu dosyada asagida kucuk bir tarih secici (Popup + MonthGrid) tanimliyoruz;
// TextField'a elle "yyyy-aa-gg" yazmak yerine takvimden secim yapilabilsin diye.

// Gecmis Teklifler ekrani: WPF'teki GecmisTekliflerViewModel + GecmisTekliflerim.xaml
// ikilisinin Qt/QML karsiligi. Filtreleme ve sayfalama mantigi burada degil,
// Database::gecmisTekliflerGetir() icinde (SQL Server tarafinda) calisir; bu sayfa
// sadece sonucu gosterir ve kullanici etkilesimini C++ tarafina iletir.
Item {
    id: root

    readonly property int sayfaBoyutu: 50

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    // ListView'in model'i DOGRUDAN "sayfaSonucu.kayitlar" iç-içe property yoluna
    // degil, duz (flat) bu property'e baglanir. Ic ice property-path binding'in
    // QML tarafinda iki kez farkli JS array kopyasi uretip ListView'in eski/yeni
    // model karsilastirmasini (change-set) sasirtmasi ihtimaline karsi.
    property var kayitlarListesi: []
    property string aramaMetni: ""
    property string secilenTarihFiltresi: "Hepsi"
    property string baslangicTarihi: ""
    property string bitisTarihi: ""

    function sayfayiYukle(sayfaNo) {
        const sonuc = database.gecmisTekliflerGetir(
            aramaMetni, secilenTarihFiltresi, baslangicTarihi, bitisTarihi, sayfaNo, sayfaBoyutu);
        sayfaSonucu = sonuc;
        // Model'i once bosaltip sonra doldurmak, ListView'in olasi hatali bir
        // "change-set" (ekleme/silme farki) hesaplamasi yerine temiz bir "reset"
        // yapmasini garantiler.
        teklifListesi.model = [];
        kayitlarListesi = sonuc.kayitlar;
        teklifListesi.model = kayitlarListesi;
    }

    Component.onCompleted: sayfayiYukle(1)

    // Arama kutusunda her tus vurusunda degil, kullanici yazmayi biraktiktan
    // kisa bir sure sonra sorgu atiyoruz (WPF tarafindaki DispatcherTimer ile ayni fikir).
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
                    text: "Geçmiş Teklifler"
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
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

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
                    placeholderText: "Teklif no, firma, ürün ara..."
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: {
                        root.aramaMetni = text
                        aramaZamanlayici.restart()
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 160
                Layout.preferredHeight: Theme.girdiYuksekligi
                radius: Theme.radiusKucuk
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ComboBox {
                    id: tarihCombo
                    anchors.fill: parent
                    background: null
                    model: ["Hepsi", "1 Gün", "1 Hafta", "15 Gün", "30 Gün", "Özel Tarih"]
                    onActivated: {
                        root.secilenTarihFiltresi = currentText
                        root.sayfayiYukle(1)
                    }
                    contentItem: Text {
                        text: tarihCombo.displayText
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 12
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 170
                Layout.preferredHeight: Theme.girdiYuksekligi
                radius: Theme.radiusKucuk
                color: Theme.panel
                border.width: 1
                border.color: baslangicTakvimi.visible ? Theme.kenarlikVurgu : Theme.kenarlik
                visible: tarihCombo.currentText === "Özel Tarih"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.baslangicTarihi.length > 0 ? root.baslangicTarihi : "Başlangıç seçin"
                    color: root.baslangicTarihi.length > 0 ? Theme.metinBirincil : Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: baslangicTakvimi.open()
                }

                TarihTakvimi {
                    id: baslangicTakvimi
                    y: parent.height + 4
                    onTarihSecildi: (tarih) => {
                        root.baslangicTarihi = tarih
                        root.sayfayiYukle(1)
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 170
                Layout.preferredHeight: Theme.girdiYuksekligi
                radius: Theme.radiusKucuk
                color: Theme.panel
                border.width: 1
                border.color: bitisTakvimi.visible ? Theme.kenarlikVurgu : Theme.kenarlik
                visible: tarihCombo.currentText === "Özel Tarih"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: root.bitisTarihi.length > 0 ? root.bitisTarihi : "Bitiş seçin"
                    color: root.bitisTarihi.length > 0 ? Theme.metinBirincil : Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bitisTakvimi.open()
                }

                TarihTakvimi {
                    id: bitisTakvimi
                    y: parent.height + 4
                    onTarihSecildi: (tarih) => {
                        root.bitisTarihi = tarih
                        root.sayfayiYukle(1)
                    }
                }
            }
        }

        // Tablo basligi
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

                Label { text: "TEKLİF NO"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 80 }
                Label { text: "FİRMA ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "TEKLİF TARİHİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 100 }
                Label { text: "KABUL TARİHİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 100 }
                Label { text: "TESLİM TARİHİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 100 }
                Label { text: "TEKLİFİ YAPAN"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 130 }
                Label { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 110 }
                Label { text: ""; Layout.preferredWidth: 80 }
            }
        }

        ListView {
            id: teklifListesi
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            // Delegate recycling KAPALI: sadece 50 satirlik bir sayfa gosteriyoruz,
            // performans maliyeti onemsiz; buna karsilik "hayalet bos satir"
            // riskini tamamen ortadan kaldiriyor (her delegate sifirdan olusturulur).
            reuseItems: false
            model: root.kayitlarListesi

            // ONEMLI: reuseItems (delegate recycling) acikken, "modelData"yi
            // "required property" olarak tanimlamazsak, oge yeniden kullanildiginda
            // (scroll sirasinda) QML bazen eski/bos degeri gosterebiliyor -- bu da
            // "hayalet bos satir" gorunumune yol aciyordu. required property ile
            // ListView her yeniden kullanimda degeri garanti guncelliyor.
            delegate: Rectangle {
                id: satir
                required property int index
                required property var modelData

                width: ListView.view.width
                height: 46
                radius: Theme.radiusKucuk
                color: satirAlani.containsMouse ? Theme.panelHover : Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                // Qt6 RHI (D3D11) sahne grafiği renderer'i, ardisik satirlarda
                // birbirine cok benzeyen Text node'larini tek bir "batch"te
                // birlestirmeye calisiyor; bu birlestirme bazen glyph atlas
                // offsetlerini yanlis hesaplayip her ikinci satirin metnini
                // gorunmez kiliyor (bilinen Qt Quick batching hatasi). layer.enabled
                // bu delegate'i ayri bir texture'a render ederek batch disina alir.
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
                        text: satir.modelData.teklifId
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 80
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                    }
                    Text {
                        text: satir.modelData.firmaAdi
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    Text {
                        text: satir.modelData.teklifTarihi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 100
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                    }
                    Text {
                        text: satir.modelData.kabulTarihi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 100
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                    }
                    Text {
                        text: satir.modelData.teslimTarihi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 100
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                    }
                    Text {
                        text: satir.modelData.personelKullaniciAdi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: 130
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 24
                        radius: 5
                        color: {
                            const d = satir.modelData.durum
                            if (d === "Tamamlandı" || d === "Kabul Edildi") return "#0f2417"
                            if (d === "Beklemede") return "#1e2a3f"
                            return Theme.panel
                        }
                        border.width: 1
                        border.color: {
                            const d = satir.modelData.durum
                            if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basari
                            if (d === "Beklemede") return Theme.vurgu
                            return Theme.kenarlik
                        }

                        Text {
                            anchors.centerIn: parent
                            text: satir.modelData.durum
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            color: {
                                const d = satir.modelData.durum
                                if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basariAcik
                                if (d === "Beklemede") return Theme.vurguAcik
                                return Theme.metinIkincil
                            }
                        }
                    }

                    Button {
                        id: silButonu
                        text: "Sil"
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 30
                        onClicked: silOnayDialogu.acilacakTeklifId = satir.modelData.teklifId
                        background: Rectangle {
                            radius: 5
                            color: silButonu.hovered ? "#3f1d24" : "transparent"
                            border.color: silButonu.hovered ? Theme.tehlikeHover : Theme.kenarlik
                            border.width: 1
                        }
                        contentItem: Text {
                            text: "Sil"
                            color: Theme.tehlikeAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
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
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik
                    opacity: oncekiButonu.enabled ? 1.0 : 0.4
                }
                contentItem: Text {
                    text: oncekiButonu.text
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: oncekiButonu.enabled ? 1.0 : 0.4
                }
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
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik
                    opacity: sonrakiButonu.enabled ? 1.0 : 0.4
                }
                contentItem: Text {
                    text: sonrakiButonu.text
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: sonrakiButonu.enabled ? 1.0 : 0.4
                }
            }
        }
    }

    // Silme onayi (WPF'teki sifre dogrulamali onay penceresinin basitlestirilmis hali;
    // sifre onayi bir sonraki adimda eklenecek).
    Dialog {
        id: silOnayDialogu
        property int acilacakTeklifId: -1
        title: "Teklifi Sil"
        modal: true
        width: 320
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No
        visible: acilacakTeklifId !== -1

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        contentItem: Label {
            text: "Teklif #" + silOnayDialogu.acilacakTeklifId + " kalıcı olarak silinecek. Emin misiniz?"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            wrapMode: Text.WordWrap
            width: silOnayDialogu.availableWidth
        }

        onAccepted: {
            database.teklifSil(acilacakTeklifId)
            acilacakTeklifId = -1
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        }
        onRejected: acilacakTeklifId = -1
    }
}
