import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Cihaz Maliyetleri: Excel'deki cihaz maliyet sayfalarinin karsiligi. Hem
// Yonetim'de hem Satinalma'da acilir; ne gorulup ne degistirilebilecegi
// kullanicinin yetkisine baglidir (Database::cihazYetkisi):
//   * tamYetki            : cihaz ekle / arsivle, ad, kar orani, urun eslesmesi
//   * kalemDuzenleyebilir : recete kalemleri (parca, adet, fiyat, kur)
//   * fiyatGorebilir      : kar orani, satis fiyati, katalog karsilastirmasi
// Asil denetim sunucudadir; yetkisiz kullaniciya fiyat bilgisi hic gelmez.
//
// Recete TL karsiliklari burada yalnizca GOSTERIM icin hesaplanir; kayitta
// sunucu ayni kuralla yeniden hesaplar (Database::cihazKaydet).
Item {
    id: root

    property bool otomatikYukle: true

    property var yetki: ({ fiyatGorebilir: false, tamYetki: false, kalemDuzenleyebilir: false,
                           semaHazir: true, urunEslesmesiVar: false })
    readonly property bool tamYetki: root.yetki.tamYetki === true
    readonly property bool kalemDuzenleyebilir: root.yetki.kalemDuzenleyebilir === true
    readonly property bool fiyatGorebilir: root.yetki.fiyatGorebilir === true

    // ---- Liste ----
    property var cihazlar: []
    property string aramaMetni: ""
    property bool arsivGoster: false
    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    // ---- Secili cihaz (form) ----
    property int seciliCihazId: -1          // -1: secim yok, 0: yeni cihaz
    property var cihaz: null                 // cihazGetir().cihaz
    property var gecmis: []
    property string cihazAdi: ""
    property real karOrani: 80
    property int urunId: 0
    property string urunMetni: ""
    property var katalogFiyat: null
    property string katalogParaBirimi: ""
    property string acilisAnlikGoruntusu: ""
    property int degisiklikSayaci: 0         // toplamlarin yeniden hesaplanmasi icin
    property string sekme: "recete"          // "recete" | "gecmis"
    property int secilecekCihazId: 0

    readonly property bool formAcik: root.seciliCihazId >= 0
    readonly property bool yeniCihaz: root.seciliCihazId === 0
    readonly property bool arsivde: root.cihaz !== null && root.cihaz.aktifMi === false
    readonly property bool degisti: root.formAcik
        && (root.degisiklikSayaci, JSON.stringify(root.formAnlikGoruntusu()) !== root.acilisAnlikGoruntusu)

    readonly property var toplamlar: {
        root.degisiklikSayaci
        kurServisi.kurTarihi    // guncel kur gelince yeniden hesaplansin
        let kayitli = 0, guncel = 0, dovizVar = false, guncelKurEksik = false
        for (let i = 0; i < kalemModeli.count; ++i) {
            const k = kalemModeli.get(i)
            const kur = k.paraBirimi === "TL" ? 1 : k.kur
            kayitli += Math.round(k.adet * Math.round(k.birimFiyat * kur * 100) / 100 * 100) / 100
            if (k.paraBirimi !== "TL") {
                dovizVar = true
                const gk = kurServisi.kur(k.paraBirimi)
                if (gk > 0)
                    guncel += k.adet * k.birimFiyat * gk
                else
                    guncelKurEksik = true
            } else {
                guncel += k.adet * k.birimFiyat
            }
        }
        kayitli = Math.round(kayitli * 100) / 100
        return {
            maliyet: kayitli,
            satis: Math.round(kayitli * (1 + root.karOrani / 100) * 100) / 100,
            guncelMaliyet: guncel,
            dovizVar: dovizVar,
            guncelKurEksik: guncelKurEksik
        }
    }

    // ---- Yukleme ----
    function sayfayiYukle() {
        root.yetki = database.cihazYetkisi()
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.cihazListesiGetirBaslat(root.aramaMetni, root.arsivGoster)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onCihazListesiHazir(istekNo, liste) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false
            root.cihazlar = liste
            if (root.secilecekCihazId > 0) {
                const id = root.secilecekCihazId
                root.secilecekCihazId = 0
                root.cihazAc(id)
            }
        }
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle()

    Timer {
        id: zamanAsimiZamanlayici
        interval: 25000
        onTriggered: {
            if (!root.yukleniyor)
                return
            root.yukleniyor = false
            root.listeHatasi = "Cihazlar sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    Timer {
        id: aramaZamanlayici
        interval: 350
        onTriggered: root.sayfayiYukle()
    }

    function bosKalem() {
        return { receteKalemId: 0, grup: "", kalemTuru: "Malzeme", kalemAdi: "", adet: 1, birim: "adet",
                 birimFiyat: 0, paraBirimi: "TL", kur: 1, tedarikciAdi: "", sonSatinalmaId: 0,
                 fiyatTarihi: "", aciklama: "", oneriVar: false, oneriFiyat: 0, oneriParaBirimi: "",
                 oneriKur: 0, oneriTarih: "", oneriTedarikci: "", oneriSatinalmaId: 0 }
    }

    function cihazAc(cihazId) {
        formHatasi.text = ""
        const sonuc = database.cihazGetir(cihazId)
        if (!sonuc.basarili) {
            islemHatasi.text = sonuc.hata
            return
        }
        islemHatasi.text = ""
        const c = sonuc.cihaz
        root.cihaz = c
        root.gecmis = sonuc.gecmis
        root.cihazAdi = c.cihazAdi
        adAlani.text = c.cihazAdi
        root.karOrani = c.karOrani !== undefined ? c.karOrani : 0
        root.urunId = c.urunId || 0
        root.urunMetni = c.urunKodu ? c.urunKodu + " · " + c.urunAciklamasi : ""
        urunKutusu.text = root.urunMetni
        root.katalogFiyat = c.katalogFiyat !== undefined ? c.katalogFiyat : null
        root.katalogParaBirimi = c.katalogParaBirimi || ""
        kalemModeli.clear()
        for (const k of sonuc.kalemler) {
            const o = k.oneri
            kalemModeli.append(Object.assign(bosKalem(), {
                receteKalemId: k.receteKalemId, grup: k.grup, kalemTuru: k.kalemTuru, kalemAdi: k.kalemAdi,
                adet: k.adet, birim: k.birim, birimFiyat: k.birimFiyat, paraBirimi: k.paraBirimi,
                kur: k.kur, tedarikciAdi: k.tedarikciAdi, sonSatinalmaId: k.sonSatinalmaId,
                fiyatTarihi: k.fiyatTarihi, aciklama: k.aciklama,
                oneriVar: !!o,
                oneriFiyat: o ? o.birimFiyat : 0, oneriParaBirimi: o ? o.paraBirimi : "",
                oneriKur: o ? o.kur : 0, oneriTarih: o ? o.tarih : "",
                oneriTedarikci: o ? o.tedarikciAdi : "", oneriSatinalmaId: o ? o.satinalmaId : 0
            }))
        }
        root.seciliCihazId = cihazId
        root.sekme = "recete"
        root.degisiklikSayaci++
        root.acilisAnlikGoruntusu = JSON.stringify(root.formAnlikGoruntusu())
    }

    function yeniCihazAc() {
        formHatasi.text = ""
        root.cihaz = null
        root.gecmis = []
        root.cihazAdi = ""
        adAlani.text = ""
        root.karOrani = 80
        root.urunId = 0
        root.urunMetni = ""
        urunKutusu.text = ""
        root.katalogFiyat = null
        root.katalogParaBirimi = ""
        kalemModeli.clear()
        kalemModeli.append(bosKalem())
        root.seciliCihazId = 0
        root.sekme = "recete"
        root.degisiklikSayaci++
        root.acilisAnlikGoruntusu = JSON.stringify(root.formAnlikGoruntusu())
    }

    // Secili cihazi birakir (degisiklikler atilir).
    function formuKapat() {
        root.seciliCihazId = -1
        root.cihaz = null
        root.gecmis = []
        kalemModeli.clear()
        root.acilisAnlikGoruntusu = ""
        formHatasi.text = ""
    }

    // Kaydedilmemis degisiklik varsa once onay ister. Modul kabuklari da
    // sekme degistirirken bunu cagirir (bkz. Yonetim / SatinAlma ModuluPage).
    function gecisYap(yapilacak) {
        if (!root.degisti) {
            yapilacak()
            return
        }
        onayDialogu.iste("Kaydedilmemiş Değişiklikler",
                         "Bu cihazdaki değişiklikler kaydedilmedi. Vazgeçilsin mi?",
                         "Vazgeç", true, yapilacak)
    }

    function kalemlerListesi() {
        const liste = []
        for (let i = 0; i < kalemModeli.count; ++i) {
            const k = kalemModeli.get(i)
            liste.push({ receteKalemId: k.receteKalemId, grup: k.grup, kalemTuru: k.kalemTuru,
                         kalemAdi: k.kalemAdi, adet: k.adet, birim: k.birim, birimFiyat: k.birimFiyat,
                         paraBirimi: k.paraBirimi, kur: k.kur, tedarikciAdi: k.tedarikciAdi,
                         sonSatinalmaId: k.sonSatinalmaId, fiyatTarihi: k.fiyatTarihi, aciklama: k.aciklama })
        }
        return liste
    }

    function formAnlikGoruntusu() {
        return { cihazAdi: root.cihazAdi.trim(), karOrani: root.karOrani, urunId: root.urunId,
                 kalemler: root.kalemlerListesi() }
    }

    function kalemDegistir(i, alan, deger) {
        if (kalemModeli.get(i)[alan] === deger)
            return
        kalemModeli.setProperty(i, alan, deger)
        // Elle girilen fiyat bir alima ait degildir.
        if (alan === "birimFiyat" || alan === "paraBirimi")
            kalemModeli.setProperty(i, "sonSatinalmaId", 0)
        if (alan === "paraBirimi") {
            if (deger === "TL") {
                kalemModeli.setProperty(i, "kur", 1)
            } else {
                const gk = kurServisi.kur(deger)
                kalemModeli.setProperty(i, "kur", gk > 0 ? gk : 0)
            }
        }
        root.degisiklikSayaci++
    }

    function oneriUygula(i) {
        const k = kalemModeli.get(i)
        kalemModeli.setProperty(i, "birimFiyat", k.oneriFiyat)
        kalemModeli.setProperty(i, "paraBirimi", k.oneriParaBirimi)
        kalemModeli.setProperty(i, "kur", k.oneriParaBirimi === "TL" ? 1 : k.oneriKur)
        kalemModeli.setProperty(i, "tedarikciAdi", k.oneriTedarikci)
        kalemModeli.setProperty(i, "sonSatinalmaId", k.oneriSatinalmaId)
        kalemModeli.setProperty(i, "fiyatTarihi", k.oneriTarih)
        kalemModeli.setProperty(i, "oneriVar", false)
        root.degisiklikSayaci++
    }

    // Dovizli kalemlerin kurunu bugunku TCMB kuruna ceker; maliyet gecmisine
    // kayitla birlikte duser.
    function kurlariGuncelle() {
        let eksik = false
        for (let i = 0; i < kalemModeli.count; ++i) {
            const pb = kalemModeli.get(i).paraBirimi
            if (pb === "TL")
                continue
            const gk = kurServisi.kur(pb)
            if (gk > 0)
                kalemModeli.setProperty(i, "kur", gk)
            else
                eksik = true
        }
        root.degisiklikSayaci++
        formHatasi.text = eksik ? "Güncel kur alınamadı; ilgili kalemlerin kurunu elle girin." : ""
    }

    function kaydet() {
        formHatasi.text = ""
        if (root.tamYetki && root.cihazAdi.trim().length === 0) {
            formHatasi.text = "Cihaz adı boş olamaz."
            return
        }
        const sonuc = database.cihazKaydet(root.seciliCihazId, {
            cihazAdi: root.cihazAdi.trim(),
            karOrani: root.karOrani,
            urunId: root.urunId,
            aciklama: root.cihaz ? root.cihaz.aciklama : "",
            kalemler: root.kalemlerListesi()
        })
        if (!sonuc.basarili) {
            formHatasi.text = sonuc.hata
            return
        }
        root.acilisAnlikGoruntusu = JSON.stringify(root.formAnlikGoruntusu())
        root.secilecekCihazId = sonuc.cihazId
        root.sayfayiYukle()
    }

    function arsivDurumuDegistir() {
        const aktif = root.arsivde
        const sonuc = database.cihazAktifDurumDegistir(root.seciliCihazId, aktif)
        if (!sonuc.basarili) {
            formHatasi.text = sonuc.hata
            return
        }
        root.secilecekCihazId = root.seciliCihazId
        root.sayfayiYukle()
    }

    function katalogFarkMetni() {
        if (root.katalogFiyat === null || root.katalogFiyat === undefined)
            return ""
        const katalog = SatinalmaBicim.dovizli(root.katalogFiyat, root.katalogParaBirimi)
        // Farkli para biriminde karsilastirma yapilmaz (kura cevrilmez).
        if (root.katalogParaBirimi !== "TL" || root.katalogFiyat <= 0)
            return "Katalog: " + katalog
        const fark = (root.toplamlar.satis - root.katalogFiyat) / root.katalogFiyat * 100
        if (Math.abs(fark) < 0.5)
            return "Katalog: " + katalog + " (aynı)"
        return "Katalog: " + katalog + " (hesaplanan %" + SayiBicimi.bicimle(Math.abs(fark), 1)
               + (fark > 0 ? " daha yüksek)" : " daha düşük)")
    }

    ListModel { id: kalemModeli }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Cihaz Maliyetleri"
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutBaslik
                font.bold: true
                color: Theme.metinBirincil
            }
            Item { Layout.fillWidth: true }
            Label {
                id: islemHatasi
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 420
            }
            TemaButon {
                text: "+ Cihaz Ekle"
                tur: "birincil"
                visible: root.tamYetki
                enabled: !root.yeniCihaz && root.yetki.semaHazir
                onClicked: root.gecisYap(function() { root.yeniCihazAc() })
            }
        }

        Label {
            visible: !root.yetki.semaHazir
            text: "Cihaz tabloları bulunamadı; db/17 betiği çalıştırılmamış."
            color: Theme.uyariAcik
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // ================= Sol: cihaz listesi =================
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true
                spacing: 8

                TemaMetinKutusu {
                    Layout.fillWidth: true
                    placeholderText: "Cihaz ara..."
                    onTextChanged: {
                        root.aramaMetni = text
                        aramaZamanlayici.restart()
                    }
                }
                TemaOnayKutusu {
                    text: "Arşivi göster"
                    checked: root.arsivGoster
                    onToggled: {
                        root.arsivGoster = checked
                        root.sayfayiYukle()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        anchors.fill: parent
                        clip: true
                        spacing: 4
                        model: root.cihazlar

                        delegate: Rectangle {
                            id: kart
                            required property var modelData
                            readonly property bool seciliMi: root.seciliCihazId === kart.modelData.cihazId

                            width: ListView.view.width
                            height: 60
                            radius: Theme.radiusKucuk
                            opacity: kart.modelData.aktifMi ? 1 : 0.55
                            color: kart.seciliMi ? Theme.panelVurgu
                                 : (kartAlani.containsMouse ? Theme.panelHover : Theme.panel)
                            border.width: 1
                            border.color: kart.seciliMi ? Theme.kenarlikVurgu : Theme.kenarlik

                            MouseArea {
                                id: kartAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (kart.seciliMi)
                                        return
                                    const id = kart.modelData.cihazId
                                    root.gecisYap(function() { root.cihazAc(id) })
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    KisalanMetin {
                                        Layout.fillWidth: true
                                        text: kart.modelData.cihazAdi
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: !kart.modelData.aktifMi
                                        text: "arşiv"
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 10
                                    }
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: "Maliyet " + SatinalmaBicim.para(kart.modelData.toplamMaliyetTL)
                                          + (kart.modelData.satisFiyatiTL !== undefined
                                             ? "  ·  Satış " + SatinalmaBicim.para(kart.modelData.satisFiyatiTL) : "")
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    ListeDurumu {
                        anchors.fill: parent
                        yukleniyor: root.yukleniyor
                        hata: root.listeHatasi
                        kayitSayisi: root.cihazlar.length
                        aramaVar: root.aramaMetni.trim().length > 0
                        bosMetin: root.tamYetki ? "Henüz cihaz eklenmemiş. \"+ Cihaz Ekle\" ile başlayabilirsiniz."
                                                : "Henüz cihaz eklenmemiş."
                        aramaBosMetni: "Aramanıza uygun cihaz bulunamadı."
                    }
                }
            }

            // ================= Sag: cihaz karti =================
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                Label {
                    anchors.centerIn: parent
                    visible: !root.formAcik
                    text: "Soldan bir cihaz seçin."
                    color: Theme.metinSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12
                    visible: root.formAcik

                    // ---- Baslik: ad + arsiv ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        EtiketliAlan {
                            id: adAlani
                            etiket: "CİHAZ ADI"
                            Layout.fillWidth: true
                            enabled: root.tamYetki
                            onDuzenlendi: (metin) => root.cihazAdi = metin
                        }
                        TemaButon {
                            Layout.alignment: Qt.AlignBottom
                            visible: root.tamYetki && !root.yeniCihaz
                            text: root.arsivde ? "Arşivden Çıkar" : "Arşivle"
                            enabled: !root.degisti
                            onClicked: root.arsivDurumuDegistir()
                        }
                    }

                    // ---- Ozet kutulari ----
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10

                        component OzetKutusu: Rectangle {
                            id: kutu
                            property string baslik: ""
                            property string deger: ""
                            property string altYazi: ""
                            width: 200
                            height: 70
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 1
                                Label { text: kutu.baslik; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                                Label { text: kutu.deger; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: 17; font.bold: true }
                                Label { visible: text.length > 0; text: kutu.altYazi; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }

                        OzetKutusu {
                            baslik: "Toplam maliyet"
                            deger: SatinalmaBicim.para(root.toplamlar.maliyet)
                            altYazi: "Kalemlerin kendi kuruyla"
                        }
                        OzetKutusu {
                            visible: root.toplamlar.dovizVar
                            baslik: "Güncel kurla maliyet"
                            deger: root.toplamlar.guncelKurEksik ? "—" : SatinalmaBicim.para(root.toplamlar.guncelMaliyet)
                            altYazi: root.toplamlar.guncelKurEksik ? "Güncel kur alınamadı"
                                     : "TCMB " + (kurServisi.kurTarihi || "")
                        }

                        // Kar orani: yonetim duzenler, yalnizca gorebilen okur.
                        Rectangle {
                            visible: root.fiyatGorebilir
                            width: 160
                            height: 70
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 3
                                Label { text: "Kâr oranı"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                                RowLayout {
                                    spacing: 4
                                    SayiKutusu {
                                        Layout.preferredWidth: 90
                                        kompakt: true
                                        enabled: root.tamYetki
                                        ondalik: 2
                                        sadeGoster: true
                                        deger: root.karOrani
                                        onDegisti: (yeni) => { root.karOrani = yeni; root.degisiklikSayaci++ }
                                    }
                                    Label { text: "%"; color: Theme.metinSoluk; font.family: Theme.fontAilesi }
                                }
                            }
                        }
                        OzetKutusu {
                            visible: root.fiyatGorebilir
                            width: 260
                            baslik: "Satış fiyatı"
                            deger: SatinalmaBicim.para(root.toplamlar.satis)
                            altYazi: root.katalogFarkMetni()
                        }
                    }

                    // ---- Urun eslesmesi (katalog karsilastirmasi) ----
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.fiyatGorebilir && root.yetki.urunEslesmesiVar
                        spacing: 8
                        Label { text: "Katalogdaki ürün"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                        OneriliMetinKutusu {
                            id: urunKutusu
                            Layout.fillWidth: true
                            Layout.maximumWidth: 520
                            kompakt: true
                            enabled: root.tamYetki
                            placeholderText: "Ürün kodu veya açıklama ile ara..."
                            enAzHarf: 2
                            oneriKaynagi: function(metin) { return database.cihazUrunAra(metin) }
                            oneriMetni: function(o) { return (o.urunKodu || "") + " · " + o.urunAciklamasi }
                            oneriAltMetni: function(o) { return SatinalmaBicim.dovizli(o.birimFiyat, o.paraBirimi) }
                            onOneriSecildi: (o) => {
                                root.urunId = o.urunId
                                root.urunMetni = (o.urunKodu || "") + " · " + o.urunAciklamasi
                                root.katalogFiyat = o.birimFiyat
                                root.katalogParaBirimi = o.paraBirimi
                                root.degisiklikSayaci++
                            }
                        }
                        TemaButon {
                            visible: root.tamYetki && root.urunId > 0
                            kucuk: true
                            tur: "sade"
                            text: "Eşleşmeyi kaldır"
                            onClicked: {
                                root.urunId = 0
                                root.urunMetni = ""
                                urunKutusu.text = ""
                                root.katalogFiyat = null
                                root.katalogParaBirimi = ""
                                root.degisiklikSayaci++
                            }
                        }
                    }

                    // ---- Sekmeler ----
                    RowLayout {
                        spacing: 8
                        SuzgecHapi { metin: "Reçete"; sayi: kalemModeli.count; secili: root.sekme === "recete"; onTiklandi: root.sekme = "recete" }
                        SuzgecHapi {
                            visible: !root.yeniCihaz
                            metin: "Maliyet Geçmişi"
                            sayi: root.gecmis.length
                            secili: root.sekme === "gecmis"
                            onTiklandi: root.sekme = "gecmis"
                        }
                    }

                    // ================= Recete =================
                    ColumnLayout {
                        id: receteSutunu
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.sekme === "recete"
                        spacing: 6

                        // Sutun genislikleri (baslik ve satirlar ayni)
                        readonly property int gGrup: 120
                        readonly property int gTur: 110
                        readonly property int gAdet: 70
                        readonly property int gBirim: 70
                        readonly property int gFiyat: 110
                        readonly property int gPara: 72
                        readonly property int gKur: 80
                        readonly property int gTutar: 110
                        readonly property int gTedarikci: 140

                        RowLayout {
                            id: receteBasligi
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            spacing: 6
                            component Baslik: Label { color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Baslik { text: "GRUP"; Layout.preferredWidth: receteSutunu.gGrup }
                            Baslik { text: "TÜR"; Layout.preferredWidth: receteSutunu.gTur }
                            Baslik { text: "KALEM"; Layout.fillWidth: true }
                            Baslik { text: "ADET"; Layout.preferredWidth: receteSutunu.gAdet }
                            Baslik { text: "BİRİM"; Layout.preferredWidth: receteSutunu.gBirim }
                            Baslik { text: "BİRİM FİYAT"; Layout.preferredWidth: receteSutunu.gFiyat }
                            Baslik { text: "PB"; Layout.preferredWidth: receteSutunu.gPara }
                            Baslik { text: "KUR"; Layout.preferredWidth: receteSutunu.gKur }
                            Baslik { text: "TUTAR (TL)"; Layout.preferredWidth: receteSutunu.gTutar; horizontalAlignment: Text.AlignRight }
                            Baslik { text: "TEDARİKÇİ"; Layout.preferredWidth: receteSutunu.gTedarikci }
                            Item { Layout.preferredWidth: 28 }
                        }

                        ListView {
                            id: receteListesi
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: kalemModeli

                            delegate: Rectangle {
                                id: kalemSatiri
                                required property int index
                                required property string grup
                                required property string kalemTuru
                                required property string kalemAdi
                                required property real adet
                                required property string birim
                                required property real birimFiyat
                                required property string paraBirimi
                                required property real kur
                                required property string tedarikciAdi
                                required property bool oneriVar
                                required property real oneriFiyat
                                required property string oneriParaBirimi
                                required property string oneriTarih
                                required property string oneriTedarikci

                                readonly property bool kilitli: !root.kalemDuzenleyebilir
                                readonly property real tutarTL: Math.round(kalemSatiri.adet
                                    * Math.round(kalemSatiri.birimFiyat * (kalemSatiri.paraBirimi === "TL" ? 1 : kalemSatiri.kur) * 100) / 100 * 100) / 100

                                width: ListView.view.width
                                height: satirSutunu.implicitHeight + 8
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik

                                ColumnLayout {
                                    id: satirSutunu
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 4
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        TemaMetinKutusu {
                                            Layout.preferredWidth: receteSutunu.gGrup
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            placeholderText: "Örn. MEKANİK"
                                            text: kalemSatiri.grup
                                            onTextEdited: root.kalemDegistir(kalemSatiri.index, "grup", text)
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: receteSutunu.gTur
                                            Layout.preferredHeight: 32
                                            radius: Theme.radiusKucuk
                                            color: Theme.arkaplan
                                            border.width: 1
                                            border.color: Theme.kenarlik
                                            TemaComboBox {
                                                anchors.fill: parent
                                                enabled: !kalemSatiri.kilitli
                                                font.pixelSize: Theme.fontBoyutKucuk + 1
                                                model: ["Malzeme", "İşçilik", "Dış Hizmet", "Genel Gider"]
                                                currentIndex: Math.max(0, model.indexOf(kalemSatiri.kalemTuru))
                                                onActivated: root.kalemDegistir(kalemSatiri.index, "kalemTuru", currentText)
                                            }
                                        }
                                        OneriliMetinKutusu {
                                            Layout.fillWidth: true
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            placeholderText: "Parça / hizmet adı"
                                            text: kalemSatiri.kalemAdi
                                            enAzHarf: 2
                                            oneriKaynagi: function(metin) { return database.satinalmaKalemOnerileri(metin, 8) }
                                            oneriMetni: function(o) { return o.kalemAdi }
                                            oneriAltMetni: function(o) {
                                                return "son alış: " + SatinalmaBicim.dovizli(o.birimFiyat, o.paraBirimi)
                                                       + (o.tedarikciAdi ? " · " + o.tedarikciAdi : "")
                                                       + (o.tarih ? " · " + SatinalmaBicim.tarih(o.tarih) : "")
                                            }
                                            onTextEdited: root.kalemDegistir(kalemSatiri.index, "kalemAdi", text)
                                            // Gecmis alim secilince ad ve birim gelir; fiyat bos ise
                                            // son alis fiyati da onerilir (recete bir maliyet tahminidir).
                                            onOneriSecildi: (o) => {
                                                root.kalemDegistir(kalemSatiri.index, "kalemAdi", o.kalemAdi)
                                                if (o.birim)
                                                    root.kalemDegistir(kalemSatiri.index, "birim", o.birim)
                                                if (kalemSatiri.birimFiyat <= 0) {
                                                    root.kalemDegistir(kalemSatiri.index, "paraBirimi", o.paraBirimi)
                                                    root.kalemDegistir(kalemSatiri.index, "birimFiyat", o.birimFiyat)
                                                    if (o.paraBirimi !== "TL" && o.kur > 1)
                                                        root.kalemDegistir(kalemSatiri.index, "kur", o.kur)
                                                    if (o.tedarikciAdi)
                                                        root.kalemDegistir(kalemSatiri.index, "tedarikciAdi", o.tedarikciAdi)
                                                }
                                            }
                                        }
                                        SayiKutusu {
                                            Layout.preferredWidth: receteSutunu.gAdet
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            ondalik: 3
                                            sadeGoster: true
                                            deger: kalemSatiri.adet
                                            onDegisti: (yeni) => root.kalemDegistir(kalemSatiri.index, "adet", yeni)
                                        }
                                        OneriliMetinKutusu {
                                            Layout.preferredWidth: receteSutunu.gBirim
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            text: kalemSatiri.birim
                                            gecikme: 0
                                            enAzHarf: 0
                                            odaktaAc: true
                                            oneriKaynagi: function(metin) { return SatinalmaBicim.birimOnerileri(metin) }
                                            onTextEdited: root.kalemDegistir(kalemSatiri.index, "birim", text)
                                            onOneriSecildi: (o) => root.kalemDegistir(kalemSatiri.index, "birim", o)
                                        }
                                        SayiKutusu {
                                            Layout.preferredWidth: receteSutunu.gFiyat
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            ondalik: 4
                                            sadeGoster: true
                                            deger: kalemSatiri.birimFiyat
                                            onDegisti: (yeni) => root.kalemDegistir(kalemSatiri.index, "birimFiyat", yeni)
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: receteSutunu.gPara
                                            Layout.preferredHeight: 32
                                            radius: Theme.radiusKucuk
                                            color: Theme.arkaplan
                                            border.width: 1
                                            border.color: Theme.kenarlik
                                            TemaComboBox {
                                                anchors.fill: parent
                                                enabled: !kalemSatiri.kilitli
                                                font.pixelSize: Theme.fontBoyutKucuk + 1
                                                model: SatinalmaBicim.paraBirimleri
                                                currentIndex: Math.max(0, model.indexOf(kalemSatiri.paraBirimi))
                                                onActivated: root.kalemDegistir(kalemSatiri.index, "paraBirimi", currentText)
                                            }
                                        }
                                        SayiKutusu {
                                            Layout.preferredWidth: receteSutunu.gKur
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli && kalemSatiri.paraBirimi !== "TL"
                                            ondalik: 4
                                            sadeGoster: true
                                            vurgulu: kalemSatiri.paraBirimi !== "TL" && kalemSatiri.kur <= 1
                                            deger: kalemSatiri.paraBirimi === "TL" ? 1 : kalemSatiri.kur
                                            onDegisti: (yeni) => root.kalemDegistir(kalemSatiri.index, "kur", yeni)
                                        }
                                        Label {
                                            Layout.preferredWidth: receteSutunu.gTutar
                                            horizontalAlignment: Text.AlignRight
                                            text: SayiBicimi.bicimle(kalemSatiri.tutarTL, 2)
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                        }
                                        TemaMetinKutusu {
                                            Layout.preferredWidth: receteSutunu.gTedarikci
                                            kompakt: true
                                            enabled: !kalemSatiri.kilitli
                                            text: kalemSatiri.tedarikciAdi
                                            onTextEdited: root.kalemDegistir(kalemSatiri.index, "tedarikciAdi", text)
                                        }
                                        TemaButon {
                                            Layout.preferredWidth: 28
                                            visible: !kalemSatiri.kilitli
                                            kucuk: true
                                            tur: "sade"
                                            text: "✕"
                                            onClicked: {
                                                kalemModeli.remove(kalemSatiri.index)
                                                root.degisiklikSayaci++
                                            }
                                        }
                                    }

                                    // Son alim onerisi
                                    RowLayout {
                                        visible: kalemSatiri.oneriVar
                                        Layout.fillWidth: true
                                        Layout.leftMargin: receteSutunu.gGrup + receteSutunu.gTur + 12
                                        spacing: 8
                                        Label {
                                            Layout.fillWidth: true
                                            text: "Son alım: " + SatinalmaBicim.dovizli(kalemSatiri.oneriFiyat, kalemSatiri.oneriParaBirimi)
                                                  + " · " + SatinalmaBicim.tarih(kalemSatiri.oneriTarih)
                                                  + (kalemSatiri.oneriTedarikci ? " · " + kalemSatiri.oneriTedarikci : "")
                                            color: Theme.uyariAcik
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                            elide: Text.ElideRight
                                        }
                                        TemaButon {
                                            visible: !kalemSatiri.kilitli
                                            kucuk: true
                                            tur: "uyari"
                                            text: "Fiyatı Uygula"
                                            onClicked: root.oneriUygula(kalemSatiri.index)
                                        }
                                    }
                                }
                            }

                            footer: Item {
                                width: receteListesi.width
                                height: root.kalemDuzenleyebilir ? 44 : 0
                                TemaButon {
                                    visible: root.kalemDuzenleyebilir
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    kucuk: true
                                    text: "+ Kalem Ekle"
                                    onClicked: {
                                        kalemModeli.append(root.bosKalem())
                                        root.degisiklikSayaci++
                                        receteListesi.positionViewAtEnd()
                                    }
                                }
                            }
                        }
                    }

                    // ================= Maliyet gecmisi =================
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.sekme === "gecmis"

                        ListView {
                            anchors.fill: parent
                            clip: true
                            spacing: 4
                            model: root.gecmis

                            delegate: Rectangle {
                                id: gecmisSatiri
                                required property var modelData
                                width: ListView.view.width
                                height: gecmisSutunu.implicitHeight + 16
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 12
                                    Label {
                                        Layout.preferredWidth: 120
                                        Layout.alignment: Qt.AlignTop
                                        text: gecmisSatiri.modelData.tarih
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk + 1
                                    }
                                    ColumnLayout {
                                        id: gecmisSutunu
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            Layout.fillWidth: true
                                            text: gecmisSatiri.modelData.aciklama
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            wrapMode: Text.WordWrap
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            visible: gecmisSatiri.modelData.eskiBirimFiyatTL !== undefined
                                                     && gecmisSatiri.modelData.eskiBirimFiyatTL !== null
                                            text: "Birim fiyat " + SatinalmaBicim.para(gecmisSatiri.modelData.eskiBirimFiyatTL)
                                                  + " → " + SatinalmaBicim.para(gecmisSatiri.modelData.yeniBirimFiyatTL)
                                                  + (gecmisSatiri.modelData.tedarikciAdi ? " · " + gecmisSatiri.modelData.tedarikciAdi : "")
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.preferredWidth: 230
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 2
                                        Label {
                                            Layout.alignment: Qt.AlignRight
                                            text: "Maliyet " + SatinalmaBicim.para(gecmisSatiri.modelData.eskiToplamTL)
                                                  + " → " + SatinalmaBicim.para(gecmisSatiri.modelData.yeniToplamTL)
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk + 1
                                        }
                                        Label {
                                            Layout.alignment: Qt.AlignRight
                                            visible: gecmisSatiri.modelData.yeniSatisFiyatiTL !== undefined
                                            text: "Satış " + SatinalmaBicim.para(gecmisSatiri.modelData.yeniSatisFiyatiTL)
                                                  + " (kâr %" + SayiBicimi.bicimle(gecmisSatiri.modelData.karOrani || 0, 2) + ")"
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                    }
                                    Label {
                                        Layout.preferredWidth: 130
                                        Layout.alignment: Qt.AlignTop
                                        text: gecmisSatiri.modelData.personel || "—"
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk + 1
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: root.gecmis.length === 0
                            text: "Henüz maliyet değişikliği yok."
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                        }
                    }

                    // ---- Alt: hata + kayit ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.kalemDuzenleyebilir

                        Label {
                            id: formHatasi
                            Layout.fillWidth: true
                            visible: text.length > 0
                            wrapMode: Text.WordWrap
                            color: Theme.tehlikeAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                        }
                        Item { Layout.fillWidth: true; visible: formHatasi.text.length === 0 }

                        TemaButon {
                            visible: root.toplamlar.dovizVar && root.sekme === "recete"
                            text: "Kurları Güncelle"
                            onClicked: root.kurlariGuncelle()
                        }
                        TemaButon {
                            visible: root.degisti
                            text: "Vazgeç"
                            onClicked: {
                                if (root.yeniCihaz) {
                                    root.formuKapat()
                                } else {
                                    root.cihazAc(root.seciliCihazId)
                                }
                            }
                        }
                        TemaButon {
                            text: root.yeniCihaz ? "Cihazı Oluştur" : "Kaydet"
                            tur: "birincil"
                            enabled: root.degisti || root.yeniCihaz
                            onClicked: root.kaydet()
                        }
                    }
                }
            }
        }
    }

    OnayDialog { id: onayDialogu }
}
