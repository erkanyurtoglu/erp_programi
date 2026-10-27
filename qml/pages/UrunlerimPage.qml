import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Urunlerim ekrani: WPF'teki Urunlerim + UrunEkle/UrunDetayWindow ikilisinin
// Qt/QML karsiligi. Sayfalama SQL Server tarafinda yapilir
// (urunListesiSorgusu), ayni GecmisTekliflerPage/MusterilerimPage deseni.
//
// NOT: Yeni semada fiyat tek para biriminde (TL) tutuluyor (goc kararinda
// alindigi gibi); WPF'teki gibi ayrica sabit Dolar/Euro fiyat sutunlari YOK --
// gerekirse Teklif Ver ekranindaki gibi elle girilen kur ile ceviri yapilir.
//
// YUKLEME ASENKRONDUR (bkz. MusterilerimPage.qml'deki ayni not). Urun
// listesinde bu ozellikle onemli: UrunAciklamasi/UrunAciklamasiEn
// nvarchar(MAX) oldugu icin sorgu suresi tarihsel olarak saniyelerle
// olculuyordu (bkz. db/11_urun_indeksleri.sql).
//
// SILME vs ARSIVLEME: MusterilerimPage ile ayni kural -- teklif kaleminde
// kullanilmis urun kalici silinemez, bu durumda arsivleme onerilir.
Item {
    id: root

    readonly property int sayfaBoyutu: 50

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlarListesi: []
    property string aramaMetni: ""
    property bool arsivliGoster: false

    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    // Bkz. MusterilerimPage.qml'deki ayni not: SatisModuluPage tum sekmeleri
    // ANINDA olusturur, otomatikYukle false ise burada sorgu atilmaz.
    property bool otomatikYukle: true

    // Satis modulunde duzenleme yetkisi (bkz. SatisModuluPage.satisDuzenleyebilir).
    // Yoksa liste ve Detay salt goruntulemedir; sunucu da yazmayi reddeder.
    property bool duzenleyebilir: true

    function paraFormat(deger) {
        return deger.toLocaleString(Qt.locale("tr_TR"), 'f', 2)
    }

    function sayfayiYukle(sayfaNo) {
        islemHatasi.text = ""
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.urunListesiGetirBaslat(
            root.aramaMetni, sayfaNo, root.sayfaBoyutu, root.arsivliGoster)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onUrunListesiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "Ürün listesi yüklenemedi: veritabanına bağlanılamadı."
                root.kayitlarListesi = []
                return
            }

            root.sayfaSonucu = sonuc
            // model'e elle atama YAPILMAZ -- bkz. MusterilerimPage'deki not.
            root.kayitlarListesi = sonuc.kayitlar
        }
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle(1)


    // Yanit gelmezse ekran sonsuza kadar "Yükleniyor…" demesin: sorgu bu sureyi
    // asarsa kullaniciya durum bildirilir ve tekrar deneme imkani verilir.
    // (Istek iptal EDILMEZ; gec de olsa yanit gelirse liste yine dolar.)
    Timer {
        id: zamanAsimiZamanlayici
        interval: 25000
        onTriggered: {
            if (!root.yukleniyor)
                return
            root.yukleniyor = false
            root.listeHatasi = "Ürün listesi sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
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
                    text: "Ürünlerim"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.sayfaSonucu.toplamKayit + " kayıt"
                           + (root.arsivliGoster ? " (arşiv dahil)" : "")
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                id: islemHatasi
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320
            }

            TemaOnayKutusu {
                text: "Arşivi göster"
                checked: root.arsivliGoster
                onToggled: {
                    root.arsivliGoster = checked
                    root.sayfayiYukle(1)
                }
            }

            Button {
                id: ekleButonu
                text: "+ Ürün Ekle"
                visible: root.duzenleyebilir
                Layout.preferredHeight: 38
                onClicked: duzenlemeDialogu.formuAc(null)
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
                placeholderText: "Ürün kodu, açıklama (TR/EN) veya kategori ara..."
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: {
                    root.aramaMetni = text
                    aramaZamanlayici.restart()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
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
                Label { text: "FİYAT (TL)"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 110 }
                Label { text: "USD"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 90 }
                Label { text: "EUR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 90 }
                Label { text: "MALİYET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 100 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 196 }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: urunListesi
                anchors.fill: parent
                clip: true
                spacing: 4
                model: root.kayitlarListesi

                delegate: Rectangle {
                    id: satir
                    required property int index
                    required property var modelData

                    readonly property bool aktifMi: satir.modelData.aktifMi !== false

                    width: ListView.view.width
                    height: 48
                    radius: Theme.radiusKucuk
                    color: satirAlani.containsMouse ? Theme.panelHover : Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik
                    opacity: satir.aktifMi ? 1.0 : 0.55

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

                        RowLayout {
                            // DIKKAT: Layout.fillWidth, duz Item'larda false'tur ama
                            // RowLayout/ColumnLayout gibi layout turevlerinde ORTUK
                            // OLARAK true'dur. Acikca kapatilmazsa preferredWidth
                            // yalnizca bir taban deger olur, sutun artan genisligi
                            // yutar ve saginda kalan AÇIKLAMA sutunu sifira ezilir.
                            Layout.fillWidth: false
                            Layout.preferredWidth: 110
                            Layout.fillHeight: true
                            spacing: 6
                            KisalanMetin {
                                text: satir.modelData.urunKodu
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.bold: true
                                font.pixelSize: Theme.fontBoyutNormal
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                visible: !satir.aktifMi
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 18
                                radius: 4
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.kenarlik
                                Text {
                                    anchors.centerIn: parent
                                    text: "Arşiv"
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 9
                                    color: Theme.metinSoluk
                                }
                            }
                        }
                        KisalanMetin {
                            text: satir.modelData.kategori
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 130
                            elide: Text.ElideRight
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        KisalanMetin {
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
                        // USD / EUR liste fiyatlari TL'den bagimsizdir; girilmemisse "—".
                        Text {
                            text: satir.modelData.fiyatUSD > 0 ? root.paraFormat(satir.modelData.fiyatUSD) + " $" : "—"
                            color: satir.modelData.fiyatUSD > 0 ? Theme.metinIkincil : Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 90
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            text: satir.modelData.fiyatEUR > 0 ? root.paraFormat(satir.modelData.fiyatEUR) + " €" : "—"
                            color: satir.modelData.fiyatEUR > 0 ? Theme.metinIkincil : Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 90
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            // Maliyet satis fiyatindan yuksekse (zararina satis)
                            // sutun uyari rengine doner -- listede de fark edilsin.
                            readonly property bool zararli: satir.modelData.maliyet > satir.modelData.birimFiyat
                                                            && satir.modelData.birimFiyat > 0
                            text: root.paraFormat(satir.modelData.maliyet) + " ₺"
                            color: zararli ? Theme.tehlikeAcik : Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 100
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                            ToolTip.visible: zararli && maliyetHucreAlani.containsMouse
                            ToolTip.text: "Maliyet, birim satış fiyatından yüksek."
                            MouseArea {
                                id: maliyetHucreAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        RowLayout {
                            // Ortuk fillWidth kapatiliyor (bkz. urun kodu sutunu).
                            Layout.fillWidth: false
                            Layout.preferredWidth: 196
                            spacing: 6

                            Button {
                                id: detayButonu
                                text: "Detay"
                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 28
                                onClicked: duzenlemeDialogu.formuAc(satir.modelData)
                                background: Rectangle { radius: 5; color: detayButonu.hovered ? Theme.panelHover : "transparent"; border.width: 1; border.color: Theme.kenarlikVurgu }
                                contentItem: Text { text: "Detay"; color: Theme.vurguAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }

                            Button {
                                id: arsivButonu
                                text: satir.aktifMi ? "Arşivle" : "Geri Al"
                                visible: root.duzenleyebilir
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 28
                                onClicked: {
                                    const id = satir.modelData.urunId
                                    const ad = root.urunAdi(satir.modelData)
                                    const aktifEt = !satir.aktifMi
                                    sifreDialogu.iste(aktifEt ? "Arşivden Çıkar" : "Ürünü Arşivle",
                                                      aktifEt
                                                        ? "\"" + ad + "\" yeniden listelerde ve teklif aramasında görünecek."
                                                        : "\"" + ad + "\" listelerden ve teklif aramasından gizlenecek. "
                                                          + "Geçmiş teklifleri etkilenmez.",
                                                      aktifEt ? "Geri Al" : "Arşivle", false,
                                                      function() { root.arsivDurumDegistir(id, aktifEt) })
                                }
                                background: Rectangle { radius: 5; color: arsivButonu.hovered ? Theme.panelHover : "transparent"; border.width: 1; border.color: Theme.kenarlik }
                                contentItem: Text { text: arsivButonu.text; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }

                            Button {
                                id: silButonu
                                text: "Sil"
                                visible: root.duzenleyebilir
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 28
                                onClicked: {
                                    const id = satir.modelData.urunId
                                    const ad = root.urunAdi(satir.modelData)
                                    sifreDialogu.iste("Ürünü Sil",
                                                      "\"" + ad + "\" kalıcı olarak silinsin mi? "
                                                      + "Teklifte kullanılmış ürünler silinemez; "
                                                      + "o durumda arşivleme önerilir.",
                                                      "Sil", true, function() { root.urunSil(id) })
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

            ListeDurumu {
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.kayitlarListesi.length
                aramaVar: root.aramaMetni.trim().length > 0
                bosMetin: "Henüz ürün eklenmemiş. \"+ Ürün Ekle\" ile başlayabilirsiniz."
                aramaBosMetni: "Aramanıza uygun ürün bulunamadı."
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Button {
                id: oncekiButonu
                text: "◀ Önceki"
                enabled: root.sayfaSonucu.mevcutSayfa > 1 && !root.yukleniyor
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
                enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa && !root.yukleniyor
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa + 1)
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.panel; border.width: 1; border.color: Theme.kenarlik; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
                contentItem: Text { text: sonrakiButonu.text; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
            }
        }
    }

    // ---- Ekle / Duzenle dialogu (ayni form, urunId=0 ise "ekle" davranir) ----
    TemaDialog {
        id: duzenlemeDialogu
        property int urunId: 0
        property string acilisAnlikGoruntusu: ""
        width: 580
        onayMetni: "Kaydet"
        onayGorunur: root.duzenleyebilir
        iptalMetni: root.duzenleyebilir ? "İptal" : "Kapat"
        elleKapat: true

        function formuAc(kayit) {
            duzenlemeDialogu.urunId = kayit ? kayit.urunId : 0
            duzenlemeDialogu.baslik = kayit ? "Ürün Düzenle" : "Ürün Ekle"
            hataMesaji.text = ""
            urunKoduAlani.text = kayit ? kayit.urunKodu : ""
            kategoriAlani.text = kayit ? kayit.kategori : ""
            aciklamaAlani.text = kayit ? kayit.urunAciklamasi : ""
            aciklamaEnAlani.text = kayit ? kayit.urunAciklamasiEn : ""
            birimFiyatBicimi.ayarla(kayit ? kayit.birimFiyat : 0)
            // Girilmemis doviz fiyati "0,00" degil bos gorunur ("Girilmedi").
            if (kayit && kayit.fiyatUSD > 0) fiyatUsdBicimi.ayarla(kayit.fiyatUSD); else fiyatUsdBicimi.temizle()
            if (kayit && kayit.fiyatEUR > 0) fiyatEurBicimi.ayarla(kayit.fiyatEUR); else fiyatEurBicimi.temizle()
            maliyetBicimi.ayarla(kayit ? kayit.maliyet : 0)
            duzenlemeDialogu.acilisAnlikGoruntusu = JSON.stringify(duzenlemeDialogu.formAlani())
            duzenlemeDialogu.open()
        }

        function formAlani() {
            return {
                urunKodu: urunKoduAlani.text.trim(),
                kategori: kategoriAlani.text.trim(),
                urunAciklamasi: aciklamaAlani.text.trim(),
                urunAciklamasiEn: aciklamaEnAlani.text.trim(),
                birimFiyat: birimFiyatBicimi.deger,
                fiyatUSD: fiyatUsdBicimi.deger,
                fiyatEUR: fiyatEurBicimi.deger,
                maliyet: maliyetBicimi.deger
            }
        }

        function degistiMi() {
            return JSON.stringify(duzenlemeDialogu.formAlani()) !== duzenlemeDialogu.acilisAnlikGoruntusu
        }

        // Kayitli urunde degisiklik yonetici sifresiyle onaylanir (yeni kayitta
        // sorulmaz); "Detay" ile sadece bakip hicbir sey degistirmediyse de
        // sorulmaz -- bkz. MusterilerimPage'deki ayni not.
        onOnaylandi: {
            if (duzenlemeDialogu.urunId > 0 && !duzenlemeDialogu.degistiMi()) {
                duzenlemeDialogu.close()
                return
            }
            duzenlemeDialogu.maliyetiDogrulaVeKaydet()
        }

        // ZARARINA SATIS UYARISI: maliyet, birim satis fiyatindan yuksekse
        // kayit sessizce yapilmaz; once kullaniciya sorulur. Yasaklamiyoruz --
        // kampanya/stok eritme gibi gercek durumlar var.
        function maliyetiDogrulaVeKaydet() {
            const veri = formAlani()
            if (veri.birimFiyat > 0 && veri.maliyet > veri.birimFiyat) {
                onayDialogu.iste("Maliyet Satış Fiyatından Yüksek",
                                 "Maliyet (" + root.paraFormat(veri.maliyet) + " ₺), birim satış "
                                 + "fiyatından (" + root.paraFormat(veri.birimFiyat) + " ₺) yüksek. "
                                 + "Bu ürün tekliflere zararına girecek.\n\nYine de kaydedilsin mi?",
                                 "Yine de Kaydet", false,
                                 function() { duzenlemeDialogu.sifreyiSorVeKaydet() })
                return
            }
            duzenlemeDialogu.sifreyiSorVeKaydet()
        }

        function sifreyiSorVeKaydet() {
            if (duzenlemeDialogu.urunId > 0)
                sifreDialogu.iste("Değişiklikleri Kaydet", "", "Kaydet", false,
                                  function() { duzenlemeDialogu.kaydet() })
            else
                duzenlemeDialogu.kaydet()
        }

        function kaydet() {
            const veri = formAlani()
            const sonuc = duzenlemeDialogu.urunId > 0
                ? database.urunGuncelle(duzenlemeDialogu.urunId, veri)
                : database.urunEkle(veri)
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan { id: urunKoduAlani; etiket: "ÜRÜN KODU" }
                EtiketliAlan { id: kategoriAlani; etiket: "KATEGORİ" }
            }
            EtiketliAlan { id: aciklamaAlani; etiket: "ÜRÜN AÇIKLAMASI *" }
            EtiketliAlan { id: aciklamaEnAlani; etiket: "ÜRÜN AÇIKLAMASI (İNGİLİZCE)" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan {
                    id: birimFiyatAlani
                    etiket: "SATIŞ FİYATI (TL)"
                    placeholderText: "0,00"
                    SayiBicimlendirici { id: birimFiyatBicimi; hedef: birimFiyatAlani.alan }
                }
                EtiketliAlan {
                    id: maliyetAlani
                    etiket: "MALİYET (TL)"
                    placeholderText: "0,00"
                    SayiBicimlendirici { id: maliyetBicimi; hedef: maliyetAlani.alan }
                }
            }
            // USD / EUR fiyatlari TL fiyatindan bagimsizdir; teklifte o para
            // birimi secilince dogrudan bunlar kullanilir. Bos = fiyat yok.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan {
                    id: fiyatUsdAlani
                    etiket: "SATIŞ FİYATI (USD)"
                    placeholderText: "Girilmedi"
                    SayiBicimlendirici { id: fiyatUsdBicimi; hedef: fiyatUsdAlani.alan }
                }
                EtiketliAlan {
                    id: fiyatEurAlani
                    etiket: "SATIŞ FİYATI (EUR)"
                    placeholderText: "Girilmedi"
                    SayiBicimlendirici { id: fiyatEurBicimi; hedef: fiyatEurAlani.alan }
                }
            }

            // Urun kodu kurallari bilgisi: kullanici hatayi kaydetmeye
            // calistiktan sonra degil, onceden gorsun.
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                text: "Ürün kodu zorunlu değildir; girilirse başka bir üründe kullanılmamış olmalı "
                      + "ve \"MANUEL\" ile başlayamaz (bu ön ek tekliflere özel manuel kalemler için ayrılmıştır)."
            }
        }
    }

    SifreOnayDialog { id: sifreDialogu }
    OnayDialog { id: onayDialogu }

    // Mesajlarda kullanilacak okunabilir urun adi: kod varsa kod, yoksa aciklama.
    function urunAdi(kayit) {
        return kayit.urunKodu && kayit.urunKodu.length > 0 ? kayit.urunKodu : kayit.urunAciklamasi
    }

    function urunSil(urunId) {
        const sonuc = database.urunSil(urunId)
        if (sonuc.basarili) {
            islemHatasi.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            return
        }

        if (sonuc.iliskiliKayitVar === true) {
            onayDialogu.iste("Ürün Silinemez",
                             sonuc.hata + "\n\nBunun yerine arşivlensin mi? "
                             + "Arşivlenen ürün listelerden ve teklif aramasından gizlenir, "
                             + "geçmiş teklifleri olduğu gibi kalır.",
                             "Arşivle", false,
                             function() { root.arsivDurumDegistir(urunId, false) })
            return
        }
        islemHatasi.text = sonuc.hata
    }

    function arsivDurumDegistir(urunId, aktif) {
        const sonuc = database.urunArsivDurumDegistir(urunId, aktif)
        if (sonuc.basarili) {
            islemHatasi.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        } else {
            islemHatasi.text = sonuc.hata
        }
    }
}
