import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Muhasebe karti (db/31). Muhasebe, siparise donusmus tekliflerin fatura ve
// irsaliyesini KENDI programinda keser; bu ekran ona gereken veriyi tek
// tikla kopyalanir halde verir ve kesilen faturanin numarasini geri alir.
// Bir muhasebe sistemi (cari, tahsilat, vade) DEGILDIR.
//
//   Faturalanacak -- fatura no bos teklifler (varsayilan: Tümü)
//   Faturalanan   -- fatura no girilmis teklifler
//
// "Faturalandı" teklifin durumunu degistirmez: fatura kesilip cihaz henuz
// teslim edilmemis olabilir (bkz. Database::faturaBilgisiKaydet).
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0
    signal anaMenuyeDon()

    function modulYetkisi(kod) {
        const liste = root.oturum && root.oturum.moduller ? root.oturum.moduller : []
        return liste.find(m => m.modulKodu === kod) || null
    }
    readonly property bool duzenleyebilir: {
        const m = root.modulYetkisi("MUHASEBE")
        return m !== null && m.duzenleyebilir === true
    }

    readonly property int sayfaBoyutu: 50

    // ---- Liste durumu ----
    property string sekme: root.baslangicSekmesi === 1 ? "faturalanan" : "faturalanacak"
    property string durum: ""
    property string aramaMetni: ""
    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlar: []
    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    // ---- Secili teklif ----
    property int seciliId: 0
    property var detay: ({})
    readonly property var seciliKayit: root.kayitlar.find(k => k.teklifId === root.seciliId) || null
    property var sevk: ({})
    property string detayHatasi: ""

    function sayfayiYukle(sayfaNo) {
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.muhasebeListesiGetirBaslat({
            sekme: root.sekme,
            durum: root.sekme === "faturalanacak" ? root.durum : "",
            arama: root.aramaMetni
        }, sayfaNo, root.sayfaBoyutu)
        zamanAsimi.restart()
    }

    function sekmeyiAc(yeniSekme) {
        root.sekme = yeniSekme
        root.sayfayiYukle(1)
    }

    function teklifiSec(teklifId) {
        root.seciliId = teklifId
        root.detayiYukle()
    }

    function detayiYukle() {
        if (root.seciliId <= 0)
            return
        const d = database.muhasebeTeklifVerisiGetir(root.seciliId)
        const s = database.sevkBilgileriGetir(root.seciliId)
        root.detayHatasi = !d.basarili ? d.hata : (!s.basarili ? s.hata : "")
        root.detay = d.basarili ? d : ({})
        root.sevk = s.basarili ? s : ({})
        irsaliyeNoAlani.text = root.sevk.irsaliyeNo || ""
        faturaNoAlani.text = root.sevk.faturaNo || ""
        root.faturaTarihi = root.sevk.faturaTarihi || ""
    }

    Connections {
        target: database
        function onMuhasebeListesiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimi.stop()
            root.yukleniyor = false
            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "Liste yüklenemedi: veritabanına bağlanılamadı."
                root.kayitlar = []
                return
            }
            if (sonuc.hata) {
                root.listeHatasi = sonuc.hata
                root.kayitlar = []
                return
            }
            root.sayfaSonucu = sonuc
            root.kayitlar = sonuc.kayitlar
        }
    }

    Component.onCompleted: ilkYukleme.start()
    Timer {
        id: ilkYukleme
        interval: 50
        onTriggered: root.sayfayiYukle(1)
    }
    Timer {
        id: zamanAsimi
        interval: 25000
        onTriggered: {
            if (!root.yukleniyor)
                return
            root.yukleniyor = false
            root.listeHatasi = "Sunucudan yanıt alınamadı; tekrar deneyin."
        }
    }
    Timer {
        id: aramaZamanlayici
        interval: 350
        onTriggered: root.sayfayiYukle(1)
    }

    // ---- Bicim yardimcilari ----
    function paraSembolu(pb) {
        return pb === "USD" ? "$" : (pb === "EUR" ? "€" : "₺")
    }
    function para(tutar) {
        return SayiBicimi.bicimle(Number(tutar || 0), 2) + " " + root.paraSembolu(root.detay.paraBirimi)
    }
    // Panoya giden sayi: binlik ayracsiz, ondalik virgul ("1234,50") -- fatura
    // programlari ve Turkce Excel bunu sayi olarak alir.
    function panoSayisi(tutar) {
        return Number(tutar || 0).toFixed(2).replace(".", ",")
    }
    function tekSatir(metin) {
        return String(metin || "").replace(/\s*[\r\n]+\s*/g, " ").trim()
    }

    function kopyala(metin, ne) {
        database.panoyaKopyala(metin)
        bildirim.goster((ne || "Metin") + " kopyalandı")
    }

    // Faturada bir kalem: indirim varsa indirimli birim fiyatla yazilir; satir
    // toplami teklifte kayitli tutardir (PDF ile ayni).
    readonly property bool indirimVar: Number(root.detay.genelIndirimOrani || 0) > 0
    function kalemBirimFiyati(k) {
        return root.indirimVar && Number(k.indirimliBirimFiyat || 0) > 0 ? k.indirimliBirimFiyat : k.birimFiyat
    }
    function kalemSatiriPano(k) {
        return [root.tekSatir(k.aciklama), k.adet, root.panoSayisi(root.kalemBirimFiyati(k)),
                root.panoSayisi(k.toplamTutar)].join("\t")
    }
    function kalemTablosuPano() {
        const satirlar = ["Açıklama\tAdet\tBirim Fiyat\tTutar"]
        for (const k of (root.detay.kalemler || []))
            satirlar.push(root.kalemSatiriPano(k))
        return satirlar.join("\n")
    }

    readonly property var faturaAlanlari: [
        { etiket: "Fatura Başlığı", anahtar: "faturaBasligi" },
        { etiket: "Adres", anahtar: "faturaAdresi" },
        { etiket: "Vergi Dairesi", anahtar: "faturaVergiDairesi" },
        { etiket: "Vergi No", anahtar: "faturaVergiNo" },
        { etiket: "Yetkili", anahtar: "faturaYetkili" },
        { etiket: "Telefon", anahtar: "faturaTelefon" },
        { etiket: "E-Posta", anahtar: "faturaEposta" }
    ]
    readonly property var irsaliyeAlanlari: [
        { etiket: "İrsaliye Başlığı", anahtar: "irsaliyeBasligi" },
        { etiket: "Adres", anahtar: "irsaliyeAdresi" },
        { etiket: "Vergi Dairesi", anahtar: "irsaliyeVergiDairesi" },
        { etiket: "Vergi No", anahtar: "irsaliyeVergiNo" },
        { etiket: "Yetkili", anahtar: "irsaliyeYetkili" },
        { etiket: "Telefon", anahtar: "irsaliyeTelefon" },
        { etiket: "E-Posta", anahtar: "irsaliyeEposta" }
    ]
    readonly property var sartAlanlari: [
        { etiket: "KDV", anahtar: "siparisKdv" },
        { etiket: "Fatura Şekli", anahtar: "faturaSekli" },
        { etiket: "Ödeme", anahtar: "odeme" },
        { etiket: "Teslimat", anahtar: "teslimat" },
        { etiket: "Nakliye", anahtar: "nakliye" },
        { etiket: "Garanti", anahtar: "garanti" },
        { etiket: "Referans No", anahtar: "referansNumarasi" },
        { etiket: "Ek Fatura Notu", anahtar: "ekFaturaNotu" },
        { etiket: "Açıklamalar", anahtar: "aciklamalar" }
    ]
    function doluAlanlar(liste) {
        return liste.filter(a => String(root.sevk[a.anahtar] || "").trim().length > 0)
    }
    function bolumPano(liste) {
        return root.doluAlanlar(liste).map(a => a.etiket + ": " + String(root.sevk[a.anahtar]).trim()).join("\n")
    }

    // ---- Fatura kaydi ----
    property string faturaTarihi: ""

    function faturayiKaydet() {
        // Yalnizca degisen alanlar gider: ayni anda satisin girdigi numara
        // ezilmesin. Tarih kurali (bos tarih = bugun, fatura no silinince tarih
        // de silinir) Database::faturaBilgisiKaydet'tedir.
        const degisen = ({})
        if (irsaliyeNoAlani.text.trim() !== String(root.sevk.irsaliyeNo || "").trim())
            degisen.irsaliyeNo = irsaliyeNoAlani.text
        if (faturaNoAlani.text.trim() !== String(root.sevk.faturaNo || "").trim())
            degisen.faturaNo = faturaNoAlani.text
        if (root.faturaTarihi !== (root.sevk.faturaTarihi || ""))
            degisen.faturaTarihi = root.faturaTarihi
        if (Object.keys(degisen).length === 0) {
            bildirim.goster("Değişiklik yok")
            return
        }
        const sonuc = database.faturaBilgisiKaydet(root.seciliId, degisen)
        if (!sonuc.basarili) {
            bildirim.goster(sonuc.hata, true)
            return
        }
        bildirim.goster(faturaNoAlani.text.trim().length > 0 ? "Faturalandı olarak kaydedildi" : "Kaydedildi")
        root.detayiYukle()
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
    }

    function irsaliyeyiAc() {
        sevkDialogu.teklifId = root.seciliId
        sevkDialogu.teklifNo = root.detay.teklifNo || ""
        sevkDialogu.firmaAdi = root.detay.firmaAdi || ""
        sevkDialogu.saltOkunur = root.detay.durum === "Tamamlandı" || !root.duzenleyebilir
        sevkDialogu.faturaSaltOkunur = !root.duzenleyebilir
        sevkDialogu.veri = database.sevkBilgileriGetir(root.seciliId)
        sevkDialogu.open()
    }

    function sevkiKaydet(sevk) {
        if (!sevkDialogu.saltOkunur) {
            const sonuc = database.sevkBilgileriKaydet(root.seciliId, sevk)
            if (!sonuc.basarili) {
                bildirim.goster(sonuc.hata, true)
                return
            }
        }
        if (sevkDialogu.faturaAlanlariVar && !sevkDialogu.faturaSaltOkunur && sevkDialogu.faturaDegistiMi(sevk)) {
            const f = database.faturaBilgisiKaydet(root.seciliId, sevkDialogu.faturaDegisiklikleri(sevk))
            if (!f.basarili) {
                bildirim.goster(f.hata, true)
                return
            }
        }
        bildirim.goster("İrsaliye bilgileri kaydedildi")
        root.detayiYukle()
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
    }

    // ======================================================================
    // Bilesenler
    // ======================================================================

    // Etiket + deger + kopyala dugmesi.
    component KopyaSatiri: RowLayout {
        id: kopyaSatiri
        property string etiket: ""
        property string deger: ""
        Layout.fillWidth: true
        spacing: 10

        Label {
            text: kopyaSatiri.etiket
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
            Layout.preferredWidth: 120
            Layout.alignment: Qt.AlignTop
            topPadding: 4
        }
        TextEdit {
            text: kopyaSatiri.deger
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: Theme.metinBirincil
            selectionColor: Theme.vurgu
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            topPadding: 3
        }
        TemaButon {
            tur: "sade"
            kucuk: true
            text: "Kopyala"
            Layout.alignment: Qt.AlignTop
            onClicked: root.kopyala(kopyaSatiri.deger, kopyaSatiri.etiket)
        }
    }

    // Tiklaninca yalnizca kendi degerini panoya alan tablo hucresi.
    component KopyaHucresi: Label {
        id: hucre
        property string panoMetni: text
        property string ne: ""
        color: hucreFare.containsMouse ? Theme.vurgu : Theme.metinBirincil
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutNormal
        font.underline: hucreFare.containsMouse
        Layout.alignment: Qt.AlignTop

        MouseArea {
            id: hucreFare
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.kopyala(hucre.panoMetni, hucre.ne)
        }
    }

    // Baslikli panel; sagdaki "Tümünü kopyala" istege bagli.
    component Bolum: Rectangle {
        id: bolum
        property string baslik: ""
        property string topluKopyaMetni: ""
        property string topluKopyaEtiketi: "Tümünü kopyala"
        default property alias icerik: bolumIcerik.data

        Layout.fillWidth: true
        Layout.preferredHeight: bolumIcerik.implicitHeight + 32
        radius: Theme.radiusNormal
        color: Theme.panel
        border.width: 1
        border.color: Theme.kenarlik

        ColumnLayout {
            id: bolumIcerik
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: bolum.baslik
                    color: Theme.vurguAcik
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk + 1
                    font.bold: true
                    font.letterSpacing: 1
                    Layout.fillWidth: true
                }
                TemaButon {
                    visible: bolum.topluKopyaMetni.length > 0
                    kucuk: true
                    text: bolum.topluKopyaEtiketi
                    onClicked: root.kopyala(bolum.topluKopyaMetni, bolum.baslik)
                }
            }
        }
    }

    component YanMenuButonu: Rectangle {
        id: buton
        property string metin: ""
        property bool secili: false
        signal tiklandi()

        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: Theme.radiusKucuk
        color: secili ? Theme.panelVurgu : (alan.containsMouse ? Theme.panelHover : "transparent")
        border.width: secili ? 1 : 0
        border.color: Theme.kenarlikVurgu

        Rectangle {
            visible: buton.secili
            width: 3
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 6
            radius: 2
            color: Theme.vurgu
        }
        Label {
            anchors.left: parent.left
            anchors.leftMargin: buton.secili ? 20 : 14
            anchors.verticalCenter: parent.verticalCenter
            text: buton.metin
            color: buton.secili ? Theme.metinBirincil : Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            font.bold: buton.secili
        }
        MouseArea {
            id: alan
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: buton.tiklandi()
        }
    }

    // ======================================================================
    // Gorunum
    // ======================================================================
    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Sol yan menu ----
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.arkaplanIkincil

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.kenarlik
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4

                Label {
                    text: "MUHASEBE"
                    color: Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.bold: true
                    Layout.bottomMargin: 8
                }
                YanMenuButonu {
                    metin: "◀ Ana Menü"
                    Layout.bottomMargin: 8
                    onTiklandi: root.anaMenuyeDon()
                }
                YanMenuButonu {
                    metin: "Faturalanacak"
                    secili: root.sekme === "faturalanacak"
                    onTiklandi: root.sekmeyiAc("faturalanacak")
                }
                YanMenuButonu {
                    metin: "Faturalanan"
                    secili: root.sekme === "faturalanan"
                    onTiklandi: root.sekmeyiAc("faturalanan")
                }
                Item { Layout.fillHeight: true }
            }
        }

        // ---- Icerik ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 24
            spacing: 12

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 2
                    Label {
                        text: root.sekme === "faturalanacak" ? "Faturalanacak" : "Faturalanan"
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutBaslik
                        font.bold: true
                        color: Theme.metinBirincil
                    }
                    Label {
                        text: root.sayfaSonucu.toplamKayit + " teklif"
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                        color: Theme.metinSoluk
                    }
                }

                Item { Layout.fillWidth: true }

                // Varsayilan Tümü; Alınan / Biten ile daraltilabilir.
                SuzgecHapi {
                    visible: root.sekme === "faturalanacak"
                    metin: "Alınan"
                    secili: root.durum === "Kabul Edildi"
                    onTiklandi: { root.durum = "Kabul Edildi"; root.sayfayiYukle(1) }
                }
                SuzgecHapi {
                    visible: root.sekme === "faturalanacak"
                    metin: "Biten"
                    secili: root.durum === "Tamamlandı"
                    onTiklandi: { root.durum = "Tamamlandı"; root.sayfayiYukle(1) }
                }
                SuzgecHapi {
                    visible: root.sekme === "faturalanacak"
                    metin: "Tümü"
                    secili: root.durum === ""
                    onTiklandi: { root.durum = ""; root.sayfayiYukle(1) }
                }
            }

            TemaMetinKutusu {
                Layout.fillWidth: true
                placeholderText: "Teklif no, firma adı veya fatura no ara..."
                onTextChanged: {
                    root.aramaMetni = text
                    aramaZamanlayici.restart()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                // ---- Liste ----
                ColumnLayout {
                    Layout.preferredWidth: 400
                    Layout.maximumWidth: 400
                    Layout.fillHeight: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: liste
                            anchors.fill: parent
                            clip: true
                            spacing: 4
                            model: root.kayitlar
                            ScrollBar.vertical: ScrollBar {}

                            delegate: Rectangle {
                                id: satir
                                required property var modelData
                                readonly property bool secili: satir.modelData.teklifId === root.seciliId
                                readonly property color durumRengi: satir.modelData.faturaDurumu === "faturalandi" ? Theme.basari
                                                                   : satir.modelData.faturaDurumu === "hazir" ? Theme.vurgu : Theme.uyari

                                width: ListView.view.width - 8
                                height: 64
                                radius: Theme.radiusKucuk
                                color: satir.secili ? Theme.panelVurgu : (satirAlani.containsMouse ? Theme.panelHover : Theme.panel)
                                border.width: 1
                                border.color: satir.secili ? Theme.kenarlikVurgu : Theme.kenarlik

                                MouseArea {
                                    id: satirAlani
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.teklifiSec(satir.modelData.teklifId)
                                }

                                Rectangle {
                                    width: 3
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    radius: 2
                                    color: satir.durumRengi
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 20
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Label {
                                            text: satir.modelData.teklifNo
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: true
                                        }
                                        KisalanMetin {
                                            text: satir.modelData.firmaAdi
                                            color: Theme.metinIkincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Label {
                                            text: satir.modelData.faturaDurumu === "faturalandi"
                                                  ? "Fatura " + satir.modelData.faturaNo
                                                    + (satir.modelData.faturaTarihi ? " · " + satir.modelData.faturaTarihi : "")
                                                  : satir.modelData.faturaDurumu === "hazir" ? "Faturaya hazır"
                                                  : "İrsaliye bilgileri eksik"
                                            color: satir.durumRengi
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            text: SayiBicimi.bicimle(satir.modelData.genelToplam, 2) + " "
                                                  + root.paraSembolu(satir.modelData.paraBirimi)
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                    }
                                }
                            }
                        }

                        ListeDurumu {
                            anchors.fill: parent
                            yukleniyor: root.yukleniyor
                            hata: root.listeHatasi
                            kayitSayisi: root.kayitlar.length
                            aramaVar: root.aramaMetni.trim().length > 0
                            bosMetin: root.sekme === "faturalanacak" ? "Faturalanacak teklif yok."
                                                                     : "Henüz fatura no girilmiş teklif yok."
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.sayfaSonucu.toplamSayfa > 1
                        TemaButon {
                            kucuk: true
                            text: "◀"
                            enabled: root.sayfaSonucu.mevcutSayfa > 1 && !root.yukleniyor
                            onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa - 1)
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "Sayfa " + root.sayfaSonucu.mevcutSayfa + " / " + root.sayfaSonucu.toplamSayfa
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                        }
                        TemaButon {
                            kucuk: true
                            text: "▶"
                            enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa && !root.yukleniyor
                            onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa + 1)
                        }
                    }
                }

                // ---- Detay paneli ----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Label {
                        anchors.centerIn: parent
                        visible: root.seciliId <= 0 || root.detayHatasi.length > 0
                        text: root.detayHatasi.length > 0 ? root.detayHatasi : "Soldan bir teklif seçin."
                        color: root.detayHatasi.length > 0 ? Theme.tehlikeAcik : Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                    }

                    ScrollView {
                        id: detayGorunumu
                        anchors.fill: parent
                        visible: root.seciliId > 0 && root.detayHatasi.length === 0
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: detayGorunumu.availableWidth
                            spacing: 12

                            // Baslik
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    KisalanMetin {
                                        Layout.fillWidth: true
                                        text: "Teklif " + (root.detay.teklifNo || "") + "  ·  " + (root.detay.firmaAdi || "")
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutOrta
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: (root.detay.durum || "")
                                              + (root.detay.kabulTarihi ? "  ·  Kabul " + root.detay.kabulTarihi : "")
                                              + (root.detay.teslimatTarihi ? "  ·  Planlanan teslim " + root.detay.teslimatTarihi : "")
                                              + (root.detay.personelAdSoyad ? "  ·  " + root.detay.personelAdSoyad : "")
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk
                                    }
                                }
                                TemaButon {
                                    kucuk: true
                                    text: "Teklif PDF"
                                    onClicked: PdfOnizleme.ac("teklif", root.seciliId, "Teklif " + (root.detay.teklifNo || ""))
                                }
                                TemaButon {
                                    kucuk: true
                                    tur: "uyari"
                                    text: "İrsaliye Bilgileri"
                                    onClicked: root.irsaliyeyiAc()
                                }
                            }

                            // Fatura kaydi: muhasebenin geri bildirimi.
                            Bolum {
                                baslik: "FATURA KAYDI"
                                visible: root.sevk.faturaAlanlariVar === true

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    EtiketliAlan {
                                        id: irsaliyeNoAlani
                                        etiket: "İRSALİYE NO"
                                        alan.readOnly: !root.duzenleyebilir
                                        alan.maximumLength: 50
                                    }
                                    EtiketliAlan {
                                        id: faturaNoAlani
                                        etiket: "FATURA NO"
                                        alan.readOnly: !root.duzenleyebilir
                                        alan.maximumLength: 50
                                    }
                                    TarihSecici {
                                        Layout.preferredWidth: 170
                                        etiket: "FATURA TARİHİ"
                                        deger: root.faturaTarihi
                                        temizlenebilir: root.duzenleyebilir
                                        enabled: root.duzenleyebilir
                                        onSecildi: (tarih) => root.faturaTarihi = tarih
                                    }
                                    TemaButon {
                                        visible: root.duzenleyebilir
                                        tur: "birincil"
                                        text: "Kaydet"
                                        Layout.alignment: Qt.AlignBottom
                                        onClicked: root.faturayiKaydet()
                                    }
                                }
                            }

                            Bolum {
                                baslik: "FATURA BİLGİLERİ"
                                topluKopyaMetni: root.bolumPano(root.faturaAlanlari)

                                // Kayitta bos olan alanlar musteri kartindan on doldurulur
                                // (sevkBilgileriGetir); satis onaylamamis demektir.
                                Label {
                                    visible: root.seciliKayit !== null && root.seciliKayit.faturaDurumu === "eksik"
                                    text: root.sevk.kayitVarMi === true
                                          ? "Fatura başlığı veya vergi no girilmemiş; boş alanlar müşteri kartından."
                                          : root.doluAlanlar(root.faturaAlanlari).length === 0
                                            ? "İrsaliye bilgileri girilmemiş."
                                            : "İrsaliye bilgileri girilmemiş; aşağıdakiler müşteri kartından."
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                    color: Theme.uyariAcik
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                }
                                Repeater {
                                    model: root.doluAlanlar(root.faturaAlanlari)
                                    delegate: KopyaSatiri {
                                        required property var modelData
                                        etiket: modelData.etiket
                                        deger: String(root.sevk[modelData.anahtar]).trim()
                                    }
                                }
                            }

                            Bolum {
                                baslik: "İRSALİYE BİLGİLERİ"
                                visible: root.doluAlanlar(root.irsaliyeAlanlari).length > 0
                                topluKopyaMetni: root.bolumPano(root.irsaliyeAlanlari)
                                Repeater {
                                    model: root.doluAlanlar(root.irsaliyeAlanlari)
                                    delegate: KopyaSatiri {
                                        required property var modelData
                                        etiket: modelData.etiket
                                        deger: String(root.sevk[modelData.anahtar]).trim()
                                    }
                                }
                            }

                            Bolum {
                                baslik: "SİPARİŞ ŞARTLARI"
                                visible: root.doluAlanlar(root.sartAlanlari).length > 0
                                topluKopyaMetni: root.bolumPano(root.sartAlanlari)
                                Repeater {
                                    model: root.doluAlanlar(root.sartAlanlari)
                                    delegate: KopyaSatiri {
                                        required property var modelData
                                        etiket: modelData.etiket
                                        deger: String(root.sevk[modelData.anahtar]).trim()
                                    }
                                }
                            }

                            Bolum {
                                baslik: "KALEMLER"
                                topluKopyaMetni: root.kalemTablosuPano()
                                topluKopyaEtiketi: "Tabloyu kopyala"

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label { text: "AÇIKLAMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.fillWidth: true }
                                    Label { text: "ADET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
                                    Label { text: root.indirimVar ? "İND. BİRİM FİYAT" : "BİRİM FİYAT"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 120; horizontalAlignment: Text.AlignRight }
                                    Label { text: "TUTAR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 120; horizontalAlignment: Text.AlignRight }
                                    Item { Layout.preferredWidth: 70 }
                                }

                                Repeater {
                                    model: root.detay.kalemler || []
                                    delegate: RowLayout {
                                        id: kalemSatiri
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 0
                                            KopyaHucresi {
                                                visible: !!kalemSatiri.modelData.urunKodu
                                                text: kalemSatiri.modelData.urunKodu || ""
                                                ne: "Ürün kodu"
                                            }
                                            Label {
                                                visible: !!kalemSatiri.modelData.urunKodu
                                                text: " · "
                                                color: Theme.metinSoluk
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: Theme.fontBoyutNormal
                                                Layout.alignment: Qt.AlignTop
                                            }
                                            KopyaHucresi {
                                                text: kalemSatiri.modelData.aciklama
                                                panoMetni: root.tekSatir(kalemSatiri.modelData.aciklama)
                                                ne: "Açıklama"
                                                wrapMode: Text.Wrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                        KopyaHucresi {
                                            text: kalemSatiri.modelData.adet
                                            ne: "Adet"
                                            Layout.preferredWidth: 50
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        KopyaHucresi {
                                            text: root.para(root.kalemBirimFiyati(kalemSatiri.modelData))
                                            panoMetni: root.panoSayisi(root.kalemBirimFiyati(kalemSatiri.modelData))
                                            ne: "Birim fiyat"
                                            Layout.preferredWidth: 120
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        KopyaHucresi {
                                            text: root.para(kalemSatiri.modelData.toplamTutar)
                                            panoMetni: root.panoSayisi(kalemSatiri.modelData.toplamTutar)
                                            ne: "Tutar"
                                            Layout.preferredWidth: 120
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        TemaButon {
                                            tur: "sade"
                                            kucuk: true
                                            text: "Kopyala"
                                            Layout.preferredWidth: 70
                                            Layout.alignment: Qt.AlignTop
                                            onClicked: root.kopyala(root.kalemSatiriPano(kalemSatiri.modelData), "Kalem")
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.kenarlik }

                                // Toplamlar teklifte kayitli degerlerdir (PDF ile ayni).
                                Repeater {
                                    model: {
                                        const d = root.detay
                                        const satirlar = []
                                        if (root.indirimVar)
                                            satirlar.push({ ad: "İndirim", deger: "%" + d.genelIndirimOrani })
                                        satirlar.push({ ad: root.indirimVar ? "İndirimli Toplam" : "Ara Toplam", tutar: d.indirimliToplam })
                                        if (Number(d.paketlemeUcreti || 0) > 0)
                                            satirlar.push({ ad: "Paketleme", tutar: d.paketlemeUcreti })
                                        if (Number(d.tasimaUcreti || 0) > 0)
                                            satirlar.push({ ad: "Taşıma", tutar: d.tasimaUcreti })
                                        if (Number(d.kdvOrani || 0) > 0)
                                            satirlar.push({ ad: "KDV %" + d.kdvOrani, tutar: d.kdvTutari })
                                        satirlar.push({ ad: "Genel Toplam", tutar: d.genelToplam, kalin: true })
                                        return satirlar
                                    }
                                    delegate: RowLayout {
                                        id: toplamSatiri
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            text: toplamSatiri.modelData.ad
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: toplamSatiri.modelData.kalin === true
                                        }
                                        KopyaHucresi {
                                            text: toplamSatiri.modelData.tutar !== undefined
                                                  ? root.para(toplamSatiri.modelData.tutar) : toplamSatiri.modelData.deger
                                            panoMetni: toplamSatiri.modelData.tutar !== undefined
                                                       ? root.panoSayisi(toplamSatiri.modelData.tutar)
                                                       : String(toplamSatiri.modelData.deger).replace("%", "")
                                            ne: toplamSatiri.modelData.ad
                                            font.bold: toplamSatiri.modelData.kalin === true
                                            Layout.preferredWidth: 120
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        TemaButon {
                                            tur: "sade"
                                            kucuk: true
                                            text: "Kopyala"
                                            Layout.preferredWidth: 70
                                            visible: toplamSatiri.modelData.tutar !== undefined
                                            onClicked: root.kopyala(root.panoSayisi(toplamSatiri.modelData.tutar),
                                                                    toplamSatiri.modelData.ad)
                                        }
                                        Item { Layout.preferredWidth: 70; visible: toplamSatiri.modelData.tutar === undefined }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 8 }
                        }
                    }
                }
            }
        }
    }

    SevkBilgileriDialog {
        id: sevkDialogu
        onKaydedildi: (sevk) => root.sevkiKaydet(sevk)
    }

    // Kopyalama / kaydetme geri bildirimi.
    Rectangle {
        id: bildirim
        property bool hata: false
        function goster(metin, hataMi) {
            bildirimMetni.text = metin
            bildirim.hata = hataMi === true
            bildirim.visible = true
            bildirimZamani.restart()
        }
        visible: false
        z: 100
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 24
        width: Math.min(bildirimMetni.implicitWidth + 32, parent.width - 48)
        height: bildirimMetni.implicitHeight + 16
        radius: Theme.radiusNormal
        color: bildirim.hata ? Qt.rgba(0.14, 0.08, 0.09, 0.97) : Qt.rgba(0.07, 0.14, 0.10, 0.97)
        border.width: 1
        border.color: bildirim.hata ? Theme.tehlikeAcik : Theme.basariAcik

        Text {
            id: bildirimMetni
            anchors.centerIn: parent
            width: Math.min(implicitWidth, bildirim.parent.width - 80)
            wrapMode: Text.Wrap
            color: bildirim.hata ? Theme.tehlikeAcik : Theme.basariAcik
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
        }
        Timer {
            id: bildirimZamani
            interval: 2500
            onTriggered: bildirim.visible = false
        }
    }
}
