import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Musterilerim ekrani: WPF'teki Firmalarim + FirmaEkle/FirmaDetayWindow
// ikilisinin Qt/QML karsiligi. Sayfalama SQL Server tarafinda yapilir
// (musteriListesiSorgusu), ayni GecmisTekliflerPage deseni.
//
// YUKLEME ASENKRONDUR: sorgu, canli aramayla ayni worker thread'i uzerinde
// calisir ve sonuc database.musteriListesiHazir sinyaliyle doner (bkz.
// Database.h "Sayfali listelerin ASENKRON yolu"). Eskiden UI thread'inde
// senkron calisiyordu: her arama ve her sayfa degisimi boyunca pencere
// donuyordu.
//
// SILME vs ARSIVLEME: teklifte kullanilmis bir musteri FK kisitlamasi
// nedeniyle kalici silinemez (bilerek -- musteri silinince teklifleri de
// silinmesin). Bu durumda ekran kullaniciya ARSIVLEMEYI onerir: kayit yerinde
// kalir, listelerden ve Teklif Ver aramasindan gizlenir, gecmis teklifler hic
// etkilenmez (bkz. db/13_musteri_urun_arsiv.sql).
Item {
    id: root

    readonly property int sayfaBoyutu: 50

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlarListesi: []
    property string aramaMetni: ""
    // "Arşivi göster" anahtari: arsivlenmis musteriler de listelenir.
    property bool arsivliGoster: false

    // Asenkron yuklemenin durumu. "bekleyenIstek", en son baslatilan sorgunun
    // numarasi: yalnizca BU numarayla donen sonuc ekrana basilir, boylece
    // hizli yazarken gecikmis bir sonuc guncelini ezmez.
    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    // SatisModuluPage tum sekmeleri (bu da dahil) StackLayout icinde ANINDA
    // olusturur -- gorunmese bile. otomatikYukle false ise onCompleted burada
    // sorgu atmaz; yukleme kullanici bu sekmeye gercekten gecince yapilir
    // (bkz. SatisModuluPage).
    property bool otomatikYukle: true

    // Satis modulunde duzenleme yetkisi (bkz. SatisModuluPage.satisDuzenleyebilir).
    // Yoksa liste ve Detay salt goruntulemedir; sunucu da yazmayi reddeder.
    property bool duzenleyebilir: true

    function sayfayiYukle(sayfaNo) {
        // Onceki islemin hata mesaji ekranda kalmasin: eskiden yalnizca
        // BASARILI bir islemden sonra temizleniyordu, dolayisiyla kullanici
        // arama yapip sayfa degistirdikten sonra bile eski hatayi goruyordu.
        islemHatasi.text = ""
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.musteriListesiGetirBaslat(
            root.aramaMetni, sayfaNo, root.sayfaBoyutu, root.arsivliGoster)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onMusteriListesiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return                       // eskimis sonuc -- yok say
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            // Worker baglanti kuramadiysa bos harita yayinlar.
            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "Müşteri listesi yüklenemedi: veritabanına bağlanılamadı."
                root.kayitlarListesi = []
                return
            }

            root.sayfaSonucu = sonuc
            // DIKKAT: ListView.model'e burada ELLE atama yapilmaz. Eskiden
            // "model = []" + "model = liste" seklinde atanıyordu; bu, QML'deki
            // "model: root.kayitlarListesi" baglantisini ILK atamada kalici
            // olarak kiriyordu (sonraki guncellemeler yalnizca her seferinde
            // tekrar elle atandigi icin gorunuyordu).
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
            root.listeHatasi = "Müşteri listesi sunucudan yanıt alınamadığı için yüklenemedi. "
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
                    text: "Müşterilerim"
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
                text: "+ Müşteri Ekle"
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
                // Arama artik telefon ve vergi numarasini da kapsiyor: bir
                // firmayi siklikla elindeki telefon ya da fatura bilgisiyle ararsin.
                placeholderText: "Firma adı, ilgili kişi, e-posta, telefon veya vergi no ara..."
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
            color: Theme.tabloBaslikZemin
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.tabloBaslikKenarlik

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Label { text: "NO"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 56 }
                Label { text: "FİRMA ADI"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "TELEFON"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 140 }
                Label { text: "E-POSTA"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 200 }
                Label { text: "İŞLEMLER"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 196 }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: musteriListesi
                anchors.fill: parent
                clip: true
                spacing: 4
                model: root.kayitlarListesi

                delegate: Rectangle {
                    id: satir
                    required property int index
                    required property var modelData

                    // Arsivlenmis kayit soluk gosterilir (Personellerim'deki
                    // pasif personel gosterimiyle ayni dil).
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

                        Text {
                            text: satir.modelData.musteriId
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 56
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6
                            KisalanMetin {
                                text: satir.modelData.firmaAdi
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
                                Layout.preferredWidth: 46
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
                            text: satir.modelData.firmaTelefonu
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 140
                            elide: Text.ElideRight
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        KisalanMetin {
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
                            // Layout turevlerinde Layout.fillWidth ORTUK olarak
                            // true'dur; kapatilmazsa bu sutun artan genisligi yutar.
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
                                    const id = satir.modelData.musteriId
                                    const ad = satir.modelData.firmaAdi
                                    const aktifEt = !satir.aktifMi
                                    sifreDialogu.iste(aktifEt ? "Arşivden Çıkar" : "Müşteriyi Arşivle",
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
                                    const id = satir.modelData.musteriId
                                    const ad = satir.modelData.firmaAdi
                                    sifreDialogu.iste("Müşteriyi Sil",
                                                      "\"" + ad + "\" kalıcı olarak silinsin mi? "
                                                      + "Teklifte kullanılmış müşteriler silinemez; "
                                                      + "o durumda arşivleme önerilir.",
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

            // Bos liste / yukleniyor / baglanti hatasi gostergesi -- eskiden
            // bu uc durum da bombos bir alan olarak gorunuyordu.
            ListeDurumu {
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.kayitlarListesi.length
                aramaVar: root.aramaMetni.trim().length > 0
                bosMetin: "Henüz müşteri eklenmemiş. \"+ Müşteri Ekle\" ile başlayabilirsiniz."
                aramaBosMetni: "Aramanıza uygun müşteri bulunamadı."
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

    // ---- Ekle / Duzenle dialogu (ayni form, musteriId=0 ise "ekle" davranir) ----
    TemaDialog {
        id: duzenlemeDialogu
        property int musteriId: 0
        // Form acilirken alinan anlik goruntu; "degisiklik var mi?" kontrolu
        // bununla yapilir (bkz. degistiMi).
        property string acilisAnlikGoruntusu: ""
        width: 560
        onayMetni: "Kaydet"
        onayGorunur: root.duzenleyebilir
        iptalMetni: root.duzenleyebilir ? "İptal" : "Kapat"
        elleKapat: true

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
            duzenlemeDialogu.acilisAnlikGoruntusu = JSON.stringify(duzenlemeDialogu.formAlani())
            duzenlemeDialogu.open()
        }

        function formAlani() {
            return {
                firmaAdi: firmaAdAlani.text.trim(),
                firmaAdresi: firmaAdresAlani.text.trim(),
                firmaTelefonu: firmaTelAlani.text.trim(),
                firmaEposta: firmaEpostaAlani.text.trim(),
                vergiDairesi: vergiDairesiAlani.text.trim(),
                vergiNumarasi: vergiNoAlani.text.trim(),
                ilgiliKisi: ilgiliKisiAlani.text.trim(),
                ilgiliKisiTelefonu: ilgiliKisiTelAlani.text.trim()
            }
        }

        function degistiMi() {
            return JSON.stringify(duzenlemeDialogu.formAlani()) !== duzenlemeDialogu.acilisAnlikGoruntusu
        }

        // Kayitli musteride degisiklik yonetici sifresiyle onaylanir (yeni
        // kayitta sorulmaz). "Detay" ile sadece BAKMAK icin acilip hicbir sey
        // degistirilmediyse de sorulmaz -- eskiden kullanici hic degisiklik
        // yapmadan Kaydet'e bastiginda bosu bosuna yonetici sifresi isteniyordu.
        onOnaylandi: {
            if (duzenlemeDialogu.musteriId > 0 && !duzenlemeDialogu.degistiMi()) {
                duzenlemeDialogu.close()
                return
            }
            if (duzenlemeDialogu.musteriId > 0)
                sifreDialogu.iste("Değişiklikleri Kaydet", "", "Kaydet", false,
                                  function() { duzenlemeDialogu.kaydet(false) })
            else
                duzenlemeDialogu.kaydet(false)
        }

        // mukerrerOnayi: ayni adda musteri bulundugunda kullanici "devam"
        // dedikten sonra ikinci cagri bu bayrakla yapilir.
        function kaydet(mukerrerOnayi) {
            const veri = formAlani()
            if (mukerrerOnayi === true)
                veri.mukerrerOnayi = true

            const sonuc = duzenlemeDialogu.musteriId > 0
                ? database.musteriGuncelle(duzenlemeDialogu.musteriId, veri)
                : database.musteriEkle(veri)

            if (!sonuc.basarili) {
                // Mukerrer firma adi bir HATA degil, bir soru: ayni ismi
                // tasiyan farkli sube/tuzel kisiler gercek bir ihtiyac.
                if (sonuc.mukerrer === true) {
                    onayDialogu.iste("Aynı İsimde Müşteri Var",
                                     "\"" + sonuc.mukerrerAd + "\" adlı bir müşteri zaten kayıtlı. "
                                     + "Aynı isimde ikinci bir müşteri oluşturulursa teklif geçmişi "
                                     + "iki kayda bölünür.\n\nYine de eklemek istiyor musunuz?",
                                     "Yine de Ekle", false,
                                     function() { duzenlemeDialogu.kaydet(true) })
                    return
                }
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
    OnayDialog { id: onayDialogu }

    function musteriSil(musteriId) {
        const sonuc = database.musteriSil(musteriId)
        if (sonuc.basarili) {
            islemHatasi.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            return
        }

        // Teklifte kullanilmis musteri kalici silinemez -- kullaniciya cikmaz
        // sokak gostermek yerine arsivlemeyi oneriyoruz.
        if (sonuc.iliskiliKayitVar === true) {
            onayDialogu.iste("Müşteri Silinemez",
                             sonuc.hata + "\n\nBunun yerine arşivlensin mi? "
                             + "Arşivlenen müşteri listelerden ve teklif aramasından gizlenir, "
                             + "geçmiş teklifleri olduğu gibi kalır.",
                             "Arşivle", false,
                             function() { root.arsivDurumDegistir(musteriId, false) })
            return
        }
        islemHatasi.text = sonuc.hata
    }

    function arsivDurumDegistir(musteriId, aktif) {
        const sonuc = database.musteriArsivDurumDegistir(musteriId, aktif)
        if (sonuc.basarili) {
            islemHatasi.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        } else {
            islemHatasi.text = sonuc.hata
        }
    }
}
