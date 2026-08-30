import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Not: Bu dosyada asagida kucuk bir tarih secici (Popup + MonthGrid) tanimliyoruz;
// TextField'a elle "yyyy-aa-gg" yazmak yerine takvimden secim yapilabilsin diye.

// Gecmis Teklifler ekrani: WPF'teki GecmisTekliflerViewModel + GecmisTekliflerim.xaml
// ikilisinin Qt/QML karsiligi. Bu tek bilesen UC AYRI SEKME icin de kullanilir:
//   - durumFiltresi=""             -> "Giden Tekliflerim": durumdan bagimsiz TUM
//                                      teklifler (WPF'teki gibi bir gecmis/log).
//   - durumFiltresi="Kabul Edildi" -> "Alınan Tekliflerim"
//   - durumFiltresi="Tamamlandı"   -> "Biten Tekliflerim"
// Filtreleme ve sayfalama mantigi burada degil, Database::gecmisTekliflerGetir()
// icinde (SQL Server tarafinda) calisir; bu sayfa sadece sonucu gosterir ve
// kullanici etkilesimini C++ tarafina iletir.
Item {
    id: root

    readonly property int sayfaBoyutu: 50

    // Hangi sekme oldugumuzu belirler (bkz. yukaridaki not) ve baslikta gosterilir.
    property string durumFiltresi: ""
    property string baslikMetni: "Giden Tekliflerim"

    // SatisModuluPage, tum sekmeleri (bu da dahil) StackLayout icinde ANINDA
    // olusturur -- sekme henuz gorunur olmasa da. otomatikYukle false ise
    // Component.onCompleted burada sorgu atmaz; yukleme, kullanici bu sekmeye
    // gercekten tikladiginda (bkz. SatisModuluPage'deki sayfayiYukle cagrisi)
    // yapilir. Boylece modul acilir acilmaz butun sekmelerin ayni anda,
    // UI thread'ini bloke eden senkron sorgular atmasi onlenir.
    property bool otomatikYukle: true

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
    property string pdfMesaji: ""
    property bool pdfMesajiHata: false

    function pdfOlusturVeAc(teklifId) {
        const sonuc = database.teklifPdfOlustur(teklifId)
        if (sonuc.basarili) {
            root.pdfMesaji = "Teklif #" + teklifId + " PDF: " + sonuc.dosyaYolu
            root.pdfMesajiHata = false
            Qt.openUrlExternally("file:///" + sonuc.dosyaYolu)
        } else {
            root.pdfMesaji = "Teklif #" + teklifId + " için PDF oluşturulamadı: " + sonuc.hata
            root.pdfMesajiHata = true
        }
    }

    function sayfayiYukle(sayfaNo) {
        const sonuc = database.gecmisTekliflerGetir(
            aramaMetni, secilenTarihFiltresi, baslangicTarihi, bitisTarihi, sayfaNo, sayfaBoyutu, root.durumFiltresi);
        sayfaSonucu = sonuc;
        // Model'i once bosaltip sonra doldurmak, ListView'in olasi hatali bir
        // "change-set" (ekleme/silme farki) hesaplamasi yerine temiz bir "reset"
        // yapmasini garantiler.
        teklifListesi.model = [];
        kayitlarListesi = sonuc.kayitlar;
        teklifListesi.model = kayitlarListesi;
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle(1)

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
                    text: root.baslikMetni
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
                visible: root.pdfMesaji.length > 0
                text: root.pdfMesaji
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                color: root.pdfMesajiHata ? Theme.tehlikeAcik : Theme.basariAcik
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 360
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
                Label { text: "TEKLİFİ YAPAN"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 130 }
                Label { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 110 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 270 }
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
                        // ONEMLI: Layout.preferredWidth: 0 olmadan RowLayout, bu Text'in
                        // (kirpilmemis) dogal genisligini "tercih edilen" boyut sayiyor ve
                        // uzun firma adlarinda satiri kendi genisliginin otesine tasiyor --
                        // bu da sonraki sutunlarin (tarih/kullanici/durum) satirdan satira
                        // farkli miktarda saga kaymis gibi gorunmesine yol aciyordu.
                        // preferredWidth: 0 RowLayout'a bu ogeyi kalan alana KISALTMASINI
                        // soyler, boylece elide gercekten calisir ve sutunlar hizali kalir.
                        Layout.preferredWidth: 0
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
                            if (d === "Reddedildi") return "#3f1620"
                            return Theme.panel
                        }
                        border.width: 1
                        border.color: {
                            const d = satir.modelData.durum
                            if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basari
                            if (d === "Beklemede") return Theme.vurgu
                            if (d === "Reddedildi") return Theme.tehlike
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
                                if (d === "Reddedildi") return Theme.tehlikeAcik
                                return Theme.metinIkincil
                            }
                        }

                        ToolTip.visible: redSebebiAlani.containsMouse && satir.modelData.durum === "Reddedildi" && satir.modelData.redSebebi.length > 0
                        ToolTip.text: satir.modelData.redSebebi
                        MouseArea {
                            id: redSebebiAlani
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }

                    RowLayout {
                        Layout.preferredWidth: 270
                        spacing: 6

                        // "Giden Tekliflerim" (durumFiltresi bos) sekmesinde, henuz cevap
                        // bekleyen teklifler icin Kabul Et / Reddet aksiyonlari.
                        Button {
                            visible: root.durumFiltresi === "" && satir.modelData.durum === "Beklemede"
                            text: "Kabul Et"
                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 28
                            onClicked: {
                                database.teklifDurumGuncelle(satir.modelData.teklifId, "Kabul Edildi", "")
                                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
                            }
                            background: Rectangle { radius: 5; color: "#123d22"; border.width: 1; border.color: Theme.basari }
                            contentItem: Text { text: "Kabul Et"; color: Theme.basariAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        Button {
                            visible: root.durumFiltresi === "" && satir.modelData.durum === "Beklemede"
                            text: "Reddet"
                            Layout.preferredWidth: 68
                            Layout.preferredHeight: 28
                            onClicked: {
                                redSebebiGirisi.text = ""
                                reddetDialogu.hedefTeklifId = satir.modelData.teklifId
                                reddetDialogu.open()
                            }
                            background: Rectangle { radius: 5; color: "transparent"; border.width: 1; border.color: Theme.tehlike }
                            contentItem: Text { text: "Reddet"; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        // "Alınan Tekliflerim" sekmesinde, siparis hazirlanip gonderildiginde
                        // "Biten Tekliflerim"e tasimak icin.
                        Button {
                            visible: root.durumFiltresi === "Kabul Edildi"
                            text: "Tamamlandı"
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 28
                            onClicked: {
                                database.teklifDurumGuncelle(satir.modelData.teklifId, "Tamamlandı", "")
                                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
                            }
                            background: Rectangle { radius: 5; color: Theme.vurgu }
                            contentItem: Text { text: "Tamamlandı"; color: "#ffffff"; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: pdfButonu
                            text: "PDF"
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 28
                            onClicked: root.pdfOlusturVeAc(satir.modelData.teklifId)
                            background: Rectangle {
                                radius: 5
                                color: pdfButonu.hovered ? Theme.panelHover : "transparent"
                                border.color: Theme.kenarlik
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "PDF"
                                color: Theme.metinIkincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            id: silButonu
                            text: "Sil"
                            Layout.preferredWidth: 50
                            Layout.preferredHeight: 28
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

    // Reddetme sebebi (opsiyonel) girisi.
    Dialog {
        id: reddetDialogu
        property int hedefTeklifId: -1
        title: "Teklifi Reddet"
        modal: true
        width: 360
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        onAccepted: {
            database.teklifDurumGuncelle(hedefTeklifId, "Reddedildi", redSebebiGirisi.text)
            hedefTeklifId = -1
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        }
        onRejected: hedefTeklifId = -1

        contentItem: ColumnLayout {
            spacing: 8
            Label {
                text: "Müşteri neden reddetti? (opsiyonel)"
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
            }
            TextArea {
                id: redSebebiGirisi
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                wrapMode: TextArea.Wrap
                color: Theme.metinBirincil
                placeholderTextColor: Theme.metinCokSoluk
                placeholderText: "Örn: Fiyat yüksek bulundu, rakip firma tercih edildi..."
                background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
            }
        }
    }
}
