import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Satinalma talebi: satinalmacinin "defteri". Biri gelip "Buyuk Aras'tan 3
// Gemo PLC, direnc.net'ten ESP32, kablo da bul bir yerden" der; satinalmaci
// burada not alir, fiyatlari toplar ve siparise donusturur.
//
//   Ust serit : kim, hangi birim icin, ne zamana istedi (talebi isteyen
//               kisi degil satinalmaci girer).
//   Kalemler  : her kalemde ne alinacak, NE ICIN (hangi cihaz), kac tane ve
//               NEREDEN. Her kalemin bir tedarikci satiri vardir; fiyat
//               tedarikciye sorulduysa cevap gelene kadar bos kalir.
//               Piyasa arastirmasi gereken kalemde "+ Alternatif fiyat" ile
//               baska yerler eklenir; iki ve daha fazla satir olunca alinacak
//               yer ● ile secilir ve en ucuz isaretlenir. Ayri bir "yeri
//               belli / arastirilacak" secimi yoktur: satir sayisi bunu
//               soyler (veritabanindaki Arastirilacak bayragi buna gore yazilir).
//               Kullanici kalem x firma karsilastirma TABLOSUNU reddetti.
//   Alt serit : fiyati belli, yeri secilmis kalemler TEDARIKCI BAZINDA
//               gruplanir, her tedarikci icin ayri siparis olusur. Fiyati
//               bekleyen kalemler talepte acik kalir.
//
// Veritabaninda "nereden + kaca" satirlari, "teklif firmasi"
// (satinalma_teklif_firmalari: tedarikci + para birimi) ve o firmanin kalem
// fiyati (satinalma_teklif_fiyatlari) olarak saklanir. Ekran bunu gostermez.
//
// Odak kaybi: kalemler kalemModel'de, "nereden / kaca" satirlari fiyatModel'de
// (kalemAnahtar ile kaleme bagli) tutulur ve yerinde guncellenir
// (setProperty); her tus vurusunda satirlar yeniden olusmaz.
Item {
    id: root

    property bool duzenleyebilir: true

    property int talepId: 0
    property int talepNo: 0
    property string durum: ""
    property bool iptal: false
    property string talepTarihi: ""
    property var siparisler: []
    property var tedarikciler: []
    property var siteler: []
    property real onayEsigi: 0

    // Talep basligi
    property string isteyenBirim: ""
    property string isteyenKisi: ""
    property string ihtiyacTarihi: ""
    property string aciklama: ""

    property bool degisti: false
    property string hata: ""
    property string bilgi: ""

    // Fiyat/kur/miktar/yer degistikce artar; toplamlar buna baglidir.
    property int surum: 0
    property int anahtarSayaci: 0

    readonly property bool duzenlenebilir: root.duzenleyebilir && !root.iptal

    signal geri()
    signal kaydedildi()

    // Roller: anahtar, talepKalemId, kalemAdi, neIcin, miktar, birim,
    // siparisNo, satinalmaId, arastirilacak (birden fazla fiyat satiri var)
    ListModel { id: kalemModel }
    // Roller: anahtar, kalemAnahtar, teklifFirmaId, tedarikciId, firmaAdi,
    // link, notu, paraBirimi, kur, birimFiyat, secildi, kilitli (kalem siparise
    // donustu), firmaKilitli (yer kaydinin aktif siparisi var)
    ListModel { id: fiyatModel }
    // Siparis olusturma penceresindeki tedarikci kartlari.
    ListModel { id: siparisBilgiModel }

    // ---------------------------------------------------------------- yukleme

    function yeniAnahtar(on) {
        root.anahtarSayaci += 1
        return on + root.anahtarSayaci
    }

    function ortakYukle() {
        root.tedarikciler = database.tedarikciSecenekleriGetir()
        root.siteler = database.satinalmaSiteleriGetir()
        root.onayEsigi = database.satinalmaOnayEsigiGetir()
        kurServisi.yenile(false)
    }

    function bosKalem(neIcin) {
        return { anahtar: root.yeniAnahtar("y"), talepKalemId: 0, kalemAdi: "", neIcin: neIcin,
                 miktar: 1, birim: "adet", siparisNo: 0, satinalmaId: 0, arastirilacak: false }
    }

    function bosFiyat(kalemAnahtar, secildi) {
        return { anahtar: root.yeniAnahtar("f"), kalemAnahtar: kalemAnahtar, teklifFirmaId: 0,
                 tedarikciId: 0, firmaAdi: "", link: "", notu: "", paraBirimi: "TL", kur: 1,
                 birimFiyat: 0, secildi: secildi, kilitli: false, firmaKilitli: false }
    }

    function yeniTalep() {
        root.ortakYukle()
        root.talepId = 0
        root.talepNo = 0
        root.durum = ""
        root.iptal = false
        root.talepTarihi = SatinalmaBicim.tarih(SatinalmaBicim.bugun())
        root.siparisler = []
        root.isteyenBirim = ""
        root.isteyenKisi = ""
        root.ihtiyacTarihi = ""
        root.aciklama = ""
        kalemModel.clear()
        fiyatModel.clear()
        root.hata = ""
        root.bilgi = ""
        root.kalemEkle(false)
        root.surum += 1
        root.degisti = false
        sayfa.ScrollBar.vertical.position = 0
    }

    // yerindeKal: kaydetme / siparis islemi sonrasi yeniden okumada kaydirma
    // konumu korunur; listeden yeni acilan talep bastan gosterilir.
    function ac(id, yerindeKal) {
        const konum = sayfa.ScrollBar.vertical.position
        root.ortakYukle()
        const t = database.talepGetir(id)
        if (!t.talepId) {
            root.hata = "Talep okunamadı. Listeyi yenileyin."
            return
        }
        root.talepId = t.talepId
        root.talepNo = t.talepNo
        root.durum = t.durum
        root.iptal = t.iptal
        root.talepTarihi = SatinalmaBicim.tarih(t.talepTarihi)
        root.siparisler = t.siparisler || []
        root.isteyenBirim = t.isteyenBirim || ""
        root.isteyenKisi = t.isteyenKisi || ""
        root.ihtiyacTarihi = t.ihtiyacTarihi || ""
        root.aciklama = t.aciklama || ""

        var firmalar = {}
        for (const f of (t.firmalar || []))
            firmalar[f.teklifFirmaId] = f

        kalemModel.clear()
        fiyatModel.clear()
        for (const k of (t.kalemler || [])) {
            const anahtar = "k" + k.talepKalemId
            const satirlar = (t.fiyatlar || []).filter(fy => fy.talepKalemId === k.talepKalemId
                                                             && firmalar[fy.teklifFirmaId])
            const coklu = satirlar.length > 1
            const kilitli = (k.siparisNo || 0) > 0
            kalemModel.append({ anahtar: anahtar, talepKalemId: k.talepKalemId, kalemAdi: k.kalemAdi,
                                neIcin: k.neIcin || "", miktar: k.miktar, birim: k.birim || "",
                                siparisNo: k.siparisNo || 0, satinalmaId: k.satinalmaId || 0,
                                arastirilacak: coklu })
            for (const fy of satirlar) {
                const f = firmalar[fy.teklifFirmaId]
                fiyatModel.append({ anahtar: "f" + fy.teklifFirmaId + "_" + k.talepKalemId,
                                    kalemAnahtar: anahtar, teklifFirmaId: f.teklifFirmaId,
                                    tedarikciId: f.tedarikciId || 0, firmaAdi: f.firmaAdi,
                                    link: fy.link || f.teklifLinki || "", notu: fy.notu || "",
                                    // Kursuz kaydedilmis doviz 0 kalmali: 1 olursa
                                    // dolar fiyati TL sayilir ve kur uyarisi kaybolur.
                                    paraBirimi: f.paraBirimi || "TL",
                                    kur: (f.paraBirimi || "TL") === "TL" ? 1 : (f.kur || 0),
                                    birimFiyat: fy.birimFiyat,
                                    // Tek satirli kalemde o satir her zaman alinacak yerdir.
                                    secildi: fy.secildi || !coklu, kilitli: kilitli,
                                    firmaKilitli: f.siparisiVar === true })
            }
            if (satirlar.length === 0)
                fiyatModel.append(root.bosFiyat(anahtar, true))
        }
        root.surum += 1
        root.hata = ""
        root.degisti = false
        if (yerindeKal === true)
            Qt.callLater(function() { sayfa.ScrollBar.vertical.position = konum })
        else
            sayfa.ScrollBar.vertical.position = 0
    }

    // ---------------------------------------------------------------- kalemler

    function kalemEkle(odakla) {
        // Yeni kalem bir oncekinin "ne icin"ini devralir: ayni cihaza giden
        // kalemler genelde arka arkaya girilir. Yer devralinmaz; bir talepteki
        // kalemler cogu zaman farkli yerlerden alinir.
        const onceki = kalemModel.count > 0 ? kalemModel.get(kalemModel.count - 1) : null
        const kalem = root.bosKalem(onceki ? onceki.neIcin : "")
        kalemModel.append(kalem)
        fiyatModel.append(root.bosFiyat(kalem.anahtar, true))
        root.surum += 1
        root.degisti = true
        if (odakla)
            Qt.callLater(function() {
                const s = kalemTekrari.itemAt(kalemModel.count - 1)
                if (s)
                    s.odakla()
            })
    }

    function kalemSil(indeks) {
        const anahtar = kalemModel.get(indeks).anahtar
        for (var i = fiyatModel.count - 1; i >= 0; --i)
            if (fiyatModel.get(i).kalemAnahtar === anahtar)
                fiyatModel.remove(i)
        kalemModel.remove(indeks)
        root.surum += 1
        root.degisti = true
    }

    function kalemDegistir(indeks, rol, deger) {
        if (kalemModel.get(indeks)[rol] === deger)
            return
        kalemModel.setProperty(indeks, rol, deger)
        root.surum += 1
        root.degisti = true
    }

    function kalemIndeksi(anahtar) {
        for (var i = 0; i < kalemModel.count; ++i)
            if (kalemModel.get(i).anahtar === anahtar)
                return i
        return -1
    }

    // Kalemin "nereden / kaca" satirlarinin fiyatModel indeksleri.
    function fiyatIndeksleri(kalemAnahtar) {
        var liste = []
        for (var i = 0; i < fiyatModel.count; ++i)
            if (fiyatModel.get(i).kalemAnahtar === kalemAnahtar)
                liste.push(i)
        return liste
    }

    // Alternatif fiyat: kalem karsilastirmali olur.
    function fiyatEkle(kalemAnahtar) {
        const satirlar = root.fiyatIndeksleri(kalemAnahtar)
        // Henuz secim yoksa ilk not alinacak yer sayilir; sonra degistirilebilir.
        const seciliVar = satirlar.some(i => fiyatModel.get(i).secildi)
        const yeni = root.bosFiyat(kalemAnahtar, !seciliVar)
        // Kalemin son satirinin hemen arkasina.
        const konum = satirlar.length > 0 ? satirlar[satirlar.length - 1] + 1 : fiyatModel.count
        fiyatModel.insert(konum, yeni)
        const k = root.kalemIndeksi(kalemAnahtar)
        if (k >= 0)
            kalemModel.setProperty(k, "arastirilacak", true)
        root.surum += 1
        root.degisti = true
    }

    // Tek satir kalirsa kalem yeniden tek kaynakli olur; o satir alinacak yerdir.
    function fiyatSil(indeks) {
        const kalemAnahtar = fiyatModel.get(indeks).kalemAnahtar
        fiyatModel.remove(indeks)
        const kalan = root.fiyatIndeksleri(kalemAnahtar)
        if (kalan.length === 1) {
            fiyatModel.setProperty(kalan[0], "secildi", true)
            const k = root.kalemIndeksi(kalemAnahtar)
            if (k >= 0)
                kalemModel.setProperty(k, "arastirilacak", false)
        }
        root.surum += 1
        root.degisti = true
    }

    function fiyatSec(indeks) {
        const kalemAnahtar = fiyatModel.get(indeks).kalemAnahtar
        for (const i of root.fiyatIndeksleri(kalemAnahtar))
            fiyatModel.setProperty(i, "secildi", i === indeks)
        root.surum += 1
        root.degisti = true
    }

    function fiyatDegistir(indeks, rol, deger) {
        if (fiyatModel.get(indeks)[rol] === deger)
            return
        fiyatModel.setProperty(indeks, rol, deger)
        if (rol === "paraBirimi") {
            // TL'de kur 1; dovizde o gunun TCMB kuru otomatik dusuyor. Ayni
            // yerin ayni dovizdeki baska satirinda kur varsa o kullanilir;
            // siparisi verilmis yerin kuru (siparis gunu) devralinmaz.
            var kur = deger === "TL" ? 1 : kurServisi.kur(deger)
            const grup = root.grupAnahtari(fiyatModel.get(indeks))
            for (var i = 0; i < fiyatModel.count; ++i) {
                const d = fiyatModel.get(i)
                if (i !== indeks && !d.kilitli && !d.firmaKilitli && root.grupAnahtari(d) === grup && d.kur > 0)
                    kur = d.kur
            }
            fiyatModel.setProperty(indeks, "kur", kur)
        } else if (rol === "kur") {
            // Kur yer + para birimi basinadir: ayni gruptaki satirlara da yaz.
            const g = root.grupAnahtari(fiyatModel.get(indeks))
            for (var j = 0; j < fiyatModel.count; ++j)
                if (j !== indeks && !fiyatModel.get(j).kilitli && root.grupAnahtari(fiyatModel.get(j)) === g)
                    fiyatModel.setProperty(j, "kur", deger)
        }
        root.surum += 1
        root.degisti = true
    }

    // Ayni yer + ayni para birimi = tek siparis grubu.
    function grupAnahtari(f) {
        const ad = (f.firmaAdi || "").trim()
        if (ad.length === 0)
            return ""
        const kim = f.tedarikciId > 0 ? "t" + f.tedarikciId : "a" + ad.toLocaleLowerCase("tr")
        return kim + "|" + f.paraBirimi
    }

    function satirKuru(f) {
        return f.paraBirimi === "TL" ? 1 : (f.kur || 0)
    }

    function birimFiyatTL(f) {
        return (f.birimFiyat || 0) * root.satirKuru(f)
    }

    // Kalemin alinacagi satir: secili ve yeri yazilmis.
    function seciliFiyat(kalemAnahtar) {
        for (const i of root.fiyatIndeksleri(kalemAnahtar)) {
            const f = fiyatModel.get(i)
            if (f.secildi && f.firmaAdi.trim().length > 0)
                return f
        }
        return null
    }

    // Kalemin durumu: siparise hazir mi, ne bekliyor?
    function kalemDurumu(k) {
        if (!k || !k.anahtar)
            return { kod: "", metin: "", renk: Theme.metinSoluk }
        // Siparisteki kalem siparisin guncel durumunu gosterir ("benim
        // siparisim ne durumda?" sorusunun cevabi); tiklaninca ayrinti acilir.
        if (k.siparisNo > 0) {
            const s = root.siparisler.find(x => x.satinalmaId === k.satinalmaId)
            const durum = s ? s.durum : ""
            return { kod: "siparis",
                     metin: SatinalmaBicim.siparisNo(k.siparisNo)
                            + (durum ? " · " + SatinalmaBicim.siparisDurumAdi(durum, "", s.eksikKapatildi) : "") + "  ›",
                     renk: durum ? SatinalmaBicim.siparisDurumRengi(durum) : Theme.basariAcik }
        }
        const secili = root.seciliFiyat(k.anahtar)
        if (!secili) {
            const yerVar = root.fiyatIndeksleri(k.anahtar).some(i => fiyatModel.get(i).firmaAdi.trim().length > 0)
            return k.arastirilacak && yerVar
                   ? { kod: "secim", metin: "Seçim bekliyor", renk: Theme.uyariAcik }
                   : { kod: "yer", metin: "Tedarikçi belirlenmedi", renk: Theme.vurgu }
        }
        if (!(secili.birimFiyat > 0))
            return { kod: "fiyat", metin: "Fiyat bekleniyor", renk: Theme.uyariAcik }
        return { kod: "hazir", metin: "Siparişe hazır", renk: Theme.basariAcik }
    }

    // Karsilastirmali kalemde en ucuz (TL) fiyatin satiri; en az iki fiyat varsa.
    function enUcuzAnahtar(kalemAnahtar) {
        var enUcuz = null
        var sayi = 0
        for (const i of root.fiyatIndeksleri(kalemAnahtar)) {
            const f = fiyatModel.get(i)
            if (!(f.birimFiyat > 0) || f.firmaAdi.trim().length === 0)
                continue
            sayi += 1
            if (!enUcuz || root.birimFiyatTL(f) < root.birimFiyatTL(enUcuz))
                enUcuz = f
        }
        return sayi > 1 ? enUcuz.anahtar : ""
    }

    // Kalem durumlarinin sayilari (alt serit icin).
    readonly property var durumSayilari: {
        root.surum
        var s = { hazir: 0, fiyat: 0, secim: 0, yer: 0, siparis: 0 }
        for (var r = 0; r < kalemModel.count; ++r) {
            const k = kalemModel.get(r)
            if (k.kalemAdi.trim().length === 0)
                continue
            const d = root.kalemDurumu(k)
            if (s[d.kod] !== undefined)
                s[d.kod] += 1
        }
        return s
    }

    // Siparise donusmemis, yeri ve fiyati belli kalemler; yer bazinda.
    readonly property var siparisGruplari: {
        root.surum
        var gruplar = []
        var sira = {}
        for (var r = 0; r < kalemModel.count; ++r) {
            const k = kalemModel.get(r)
            if (k.siparisNo > 0)
                continue
            const f = root.seciliFiyat(k.anahtar)
            if (!f || !(f.birimFiyat > 0))
                continue
            const g = root.grupAnahtari(f)
            if (sira[g] === undefined) {
                sira[g] = gruplar.length
                gruplar.push({ grup: g, teklifFirmaId: f.teklifFirmaId, firmaAdi: f.firmaAdi.trim(),
                               teslimSuresiGun: 0, kaynak: "Tedarikçi",
                               toplamTL: 0, oncekiTL: root.oncekiSiparisTL(f.firmaAdi), kalemler: [] })
            }
            const grp = gruplar[sira[g]]
            if (f.tedarikciId === 0 && f.link.trim().length > 0)
                grp.kaynak = "İnternet"
            grp.toplamTL += root.birimFiyatTL(f) * (k.miktar || 0)
            grp.kalemler.push(k.kalemAdi + " × " + SatinalmaBicim.miktar(k.miktar) + " " + (k.birim || ""))
        }
        return gruplar
    }

    // Bu talepten ayni yere verilmis aktif siparislerin toplami: onay esigi
    // bunlarla birlikte denetlenir (sunucudaki kuralin aynisi).
    function oncekiSiparisTL(firmaAdi) {
        const ad = (firmaAdi || "").trim().toLocaleLowerCase("tr")
        var t = 0
        for (const s of root.siparisler)
            if (s.durum !== "İptal" && s.durum !== "Reddedildi"
                    && (s.firmaAdi || "").trim().toLocaleLowerCase("tr") === ad)
                t += s.toplamTutarTL || 0
        return t
    }

    readonly property real seciliToplamTL: {
        var t = 0
        for (const g of root.siparisGruplari)
            t += g.toplamTL
        return t
    }

    // ---------------------------------------------------------------- kaydetme

    // "Nereden / kaca" satirlari yer + para birimi bazinda "firma"
    // kayitlarina, satirin kendisi de o firmanin kalem fiyatina donusur.
    function veriHazirla() {
        var kalemler = []
        var kalemAdlari = {}
        for (var r = 0; r < kalemModel.count; ++r) {
            const k = kalemModel.get(r)
            kalemAdlari[k.anahtar] = k.kalemAdi.trim()
            kalemler.push({ anahtar: k.anahtar, talepKalemId: k.talepKalemId, kalemAdi: k.kalemAdi,
                            neIcin: k.neIcin, miktar: k.miktar, birim: k.birim,
                            arastirilacak: k.arastirilacak })
        }

        var firmalar = []
        var fiyatlar = []
        var firmaAnahtari = {}
        var ciftler = {}
        for (var i = 0; i < fiyatModel.count; ++i) {
            const f = fiyatModel.get(i)
            const g = root.grupAnahtari(f)
            if (g.length === 0)
                continue
            // Siparisi verilmis yer kaydi (para birimi, kur) sunucuda degismez.
            // Siparise donusmus kalemlerin satirlari o kayitta kalir; ayni yere
            // yeni yazilan kalemler ayri kayda gider ki guncel kuruyla siparis
            // edilsin.
            const kilitliKayit = f.firmaKilitli && f.kilitli
            const fk = kilitliKayit ? g + "|k" + f.teklifFirmaId : g
            if (firmaAnahtari[fk] === undefined) {
                firmaAnahtari[fk] = "f" + firmalar.length
                firmalar.push({ anahtar: firmaAnahtari[fk], teklifFirmaId: 0, tedarikciId: f.tedarikciId,
                                firmaAdi: f.firmaAdi.trim(), kaynak: "Tedarikçi", teklifLinki: "",
                                paraBirimi: f.paraBirimi, kur: f.kur, teslimSuresiGun: 0, notu: "" })
            }
            const firma = firmalar[Number(firmaAnahtari[fk].substring(1))]
            // Kayitli tedarikci olmayan ve urun linki olan yer internet sitesidir.
            if (f.tedarikciId === 0 && f.link.trim().length > 0) {
                firma.kaynak = "İnternet"
                if (firma.teklifLinki.length === 0)
                    firma.teklifLinki = f.link.trim()
            }
            if (f.teklifFirmaId > 0 && firma.teklifFirmaId === 0 && (kilitliKayit || !f.firmaKilitli))
                firma.teklifFirmaId = f.teklifFirmaId

            const cift = f.kalemAnahtar + "|" + g
            if (ciftler[cift]) {
                root.hata = "\"" + (kalemAdlari[f.kalemAnahtar] || "Kalem") + "\" için \""
                            + f.firmaAdi.trim() + "\" iki kez yazılmış. Birini silin."
                return null
            }
            ciftler[cift] = true
            fiyatlar.push({ kalemAnahtar: f.kalemAnahtar, firmaAnahtar: firmaAnahtari[fk],
                            birimFiyat: f.birimFiyat || 0, secildi: f.secildi,
                            link: f.link.trim(), notu: f.notu.trim() })
        }
        // Ayni firma kaydi iki gruba atanmissa (ad/para birimi degisti):
        // ikincisi yeni kayit olsun.
        var kullanilan = {}
        for (const firma of firmalar) {
            if (firma.teklifFirmaId > 0 && kullanilan[firma.teklifFirmaId])
                firma.teklifFirmaId = 0
            kullanilan[firma.teklifFirmaId] = true
        }
        return { talepId: root.talepId, isteyenBirim: root.isteyenBirim, isteyenKisi: root.isteyenKisi,
                 ihtiyacTarihi: root.ihtiyacTarihi, aciklama: root.aciklama,
                 kalemler: kalemler, firmalar: firmalar, fiyatlar: fiyatlar }
    }

    function kaydet() {
        root.hata = ""
        root.bilgi = ""
        // Bos birakilmis yeni kalemler kaydi engellemesin.
        for (var r = kalemModel.count - 1; r >= 0; --r) {
            const k = kalemModel.get(r)
            if (k.talepKalemId === 0 && k.kalemAdi.trim().length === 0 && kalemModel.count > 1)
                root.kalemSil(r)
        }
        const veri = root.veriHazirla()
        if (!veri)
            return false
        const sonuc = database.talepKaydet(veri)
        if (!sonuc.basarili) {
            root.hata = sonuc.hata
            return false
        }
        const yeniMi = root.talepId === 0
        root.ac(sonuc.talepId, true)
        root.bilgi = yeniMi ? SatinalmaBicim.talepNo(sonuc.talepNo) + " oluşturuldu."
                            : "Değişiklikler kaydedildi."
        root.kaydedildi()
        return true
    }

    function siparisOlusturBaslat() {
        root.hata = ""
        root.bilgi = ""
        if (root.siparisGruplari.length === 0) {
            root.hata = "Siparişe hazır kalem yok: tedarikçiyi ve fiyatı yazın."
            return
        }
        // Siparis bugunun kuruyla verilir: fiyatin girildigi gunun kuru
        // eskimis olabilir. Kur alinamadiysa kayitli kur kalir.
        for (var j = 0; j < fiyatModel.count; ++j) {
            const f = fiyatModel.get(j)
            if (f.paraBirimi === "TL" || f.kilitli)
                continue
            const bugunku = kurServisi.kur(f.paraBirimi)
            if (bugunku > 0 && bugunku !== f.kur) {
                fiyatModel.setProperty(j, "kur", bugunku)
                root.surum += 1
                root.degisti = true
            }
        }
        // Siparis kaydedilmis talebe dayanir: once kaydet. Siparisi verilmis
        // yerin kaydina bagli kalmis acik kalem varsa (bu kural oncesi
        // kayitlar) kayit onu ayri kayda tasir.
        var kilitliYereBagli = false
        for (var i = 0; i < fiyatModel.count; ++i)
            if (fiyatModel.get(i).firmaKilitli && !fiyatModel.get(i).kilitli)
                kilitliYereBagli = true
        if (root.degisti || root.talepId === 0 || kilitliYereBagli) {
            if (!root.kaydet())
                return
        }
        siparisDialogu.ac()
    }

    function cikisIste() {
        if (root.degisti && root.duzenlenebilir) {
            onayDialogu.iste("Kaydedilmemiş Değişiklikler",
                             "Bu talepte kaydedilmemiş değişiklikler var. Kaydetmeden çıkılsın mı?",
                             "Kaydetmeden Çık", true,
                             function() { root.degisti = false; root.geri() })
            return
        }
        root.geri()
    }

    Connections {
        target: kurServisi
        // Kurlar ekran acildiktan sonra gelirse, kuru henuz girilmemis dovizli
        // satirlar doldurulur; elle yazilmis kura dokunulmaz.
        function onKurlarDegisti() {
            var degisen = false
            for (var i = 0; i < fiyatModel.count; ++i) {
                const f = fiyatModel.get(i)
                if (f.paraBirimi !== "TL" && !(f.kur > 0) && !f.kilitli) {
                    const kur = kurServisi.kur(f.paraBirimi)
                    if (kur > 0) {
                        fiyatModel.setProperty(i, "kur", kur)
                        degisen = true
                    }
                }
            }
            if (degisen)
                root.surum += 1
        }
    }

    // Baslik rozeti: tum kalemleri siparise donmus talep, siparisleri
    // gelene kadar "Teslimat bekleniyor"dur.
    readonly property var baslikDurumu: {
        if (root.durum !== "Siparişe Dönüştü")
            return { metin: root.durum, renk: SatinalmaBicim.talepDurumRengi(root.durum) }
        const yolda = root.siparisler.some(s => SatinalmaBicim.acikMi(s.durum))
        return yolda ? { metin: "Teslimat bekleniyor", renk: SatinalmaBicim.siparisDurumRengi("Kargoda") }
                     : { metin: "Tamamlandı", renk: Theme.basariAcik }
    }

    // Kalem izgarasi: kalem satiri ile tedarikci satirlari ayni sutunlari
    // kullanir (basliklar da). Sol kisim esnek, sagdaki sutunlar sabit.
    readonly property int sutunNo: 24
    readonly property int sutunNeIcin: 180
    readonly property int sutunMiktar: 90
    readonly property int sutunBirim: 100
    readonly property int sutunDurum: 190
    readonly property int sutunSil: 28
    readonly property int sutunAraligi: 10

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    component AlanEtiketi: Label {
        color: Theme.metinSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    component DuzMetin: KisalanMetin {
        color: Theme.metinBirincil
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutNormal
        verticalAlignment: Text.AlignVCenter
    }

    // ================================================================ EKRAN
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Baslik ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            TemaButon {
                text: "◀  Talepler"
                onClicked: root.cikisIste()
            }

            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: 10
                    Label {
                        text: root.talepId > 0 ? "Talep " + SatinalmaBicim.talepNo(root.talepNo) : "Talep Oluştur"
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutBaslik
                        font.bold: true
                        color: Theme.metinBirincil
                    }
                    DurumRozeti {
                        visible: root.durum.length > 0
                        metin: root.baslikDurumu.metin
                        renk: root.baslikDurumu.renk
                        dolu: true
                    }
                    DurumRozeti {
                        visible: root.degisti && root.duzenlenebilir && root.talepId > 0
                        metin: "Kaydedilmedi"
                        renk: Theme.uyariAcik
                    }
                }
                Label {
                    text: root.talepTarihi + "  ·  " + kalemModel.count + " kalem"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                Layout.maximumWidth: 420
                visible: text.length > 0
                text: root.hata.length > 0 ? root.hata : root.bilgi
                color: root.hata.length > 0 ? Theme.tehlikeAcik : Theme.basariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
            }

            TemaButon {
                visible: root.talepId > 0 && root.duzenlenebilir && root.durumSayilari.siparis === 0
                tur: "tehlike"
                text: "Talebi İptal Et"
                onClicked: iptalDialogu.open()
            }

            TemaButon {
                visible: root.duzenlenebilir
                tur: root.degisti || root.talepId === 0 ? "birincil" : "ikincil"
                text: "Kaydet"
                enabled: root.degisti || root.talepId === 0
                onClicked: root.kaydet()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.iptal
            implicitHeight: 40
            radius: Theme.radiusKucuk
            color: Theme.tehlikeZemin
            border.color: Theme.tehlike
            Label {
                anchors.fill: parent
                anchors.leftMargin: 14
                verticalAlignment: Text.AlignVCenter
                text: "Bu talep iptal edilmiş."
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }
        }

        // ---- Talep bilgileri seridi ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: bilgiSatiri.implicitHeight + 32
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                id: bilgiSatiri
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                enabled: root.duzenlenebilir

                ColumnLayout {
                    Layout.preferredWidth: 200
                    Layout.fillWidth: false
                    spacing: 4
                    AlanEtiketi { text: "BİRİM" }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.girdiYuksekligi
                        radius: Theme.radiusKucuk
                        color: Theme.arkaplan
                        border.width: 1
                        border.color: birimKutusu.popup.visible ? Theme.kenarlikVurgu : Theme.kenarlik
                        TemaComboBox {
                            id: birimKutusu
                            anchors.fill: parent
                            model: ["Seçin"].concat(SatinalmaBicim.birimler)
                            currentIndex: Math.max(0, model.indexOf(root.isteyenBirim))
                            onActivated: {
                                root.isteyenBirim = currentIndex > 0 ? currentText : ""
                                root.degisti = true
                            }
                        }
                    }
                }

                EtiketliAlan {
                    Layout.preferredWidth: 240
                    Layout.fillWidth: false
                    etiket: "İSTEYEN KİŞİ"
                    placeholderText: "Ad Soyad"
                    text: root.isteyenKisi
                    onDuzenlendi: (metin) => {
                        root.isteyenKisi = metin
                        root.degisti = true
                    }
                }

                TarihSecici {
                    Layout.preferredWidth: 180
                    Layout.fillWidth: false
                    etiket: "NE ZAMAN LAZIM"
                    gecmisKapali: true
                    deger: root.ihtiyacTarihi
                    onSecildi: (tarih) => {
                        root.ihtiyacTarihi = tarih
                        root.degisti = true
                    }
                }

                EtiketliAlan {
                    Layout.fillWidth: true
                    etiket: "AÇIKLAMA"
                    text: root.aciklama
                    onDuzenlendi: (metin) => {
                        root.aciklama = metin
                        root.degisti = true
                    }
                }
            }
        }

        // ---- Kalemler ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Label {
                        text: "KALEMLER"
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                        font.letterSpacing: 1.5
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: {
                            if (kurServisi.yukleniyor)
                                return "Kur alınıyor…"
                            if (kurServisi.usd <= 0 && kurServisi.eur <= 0)
                                return "TCMB kuru alınamadı"
                            return "TCMB " + kurServisi.kurTarihi + "   USD "
                                   + SayiBicimi.bicimle(kurServisi.usd, 4) + "   EUR "
                                   + SayiBicimi.bicimle(kurServisi.eur, 4)
                        }
                        color: kurServisi.usd > 0 ? Theme.metinSoluk : Theme.uyariAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                    }
                    TemaButon {
                        tur: "sade"
                        kucuk: true
                        text: "Kuru Yenile"
                        onClicked: kurServisi.yenile(true)
                    }
                    TemaButon {
                        visible: root.duzenlenebilir
                        kucuk: true
                        text: "+ Kalem Ekle"
                        onClicked: root.kalemEkle(true)
                    }
                }

                ScrollView {
                    id: sayfa
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: sayfa.availableWidth
                        spacing: 10

                        // Yuvarlak secim isareti (karsilastirmali kalemde alinacak yer).
                        component Secici: Rectangle {
                            id: secici
                            property bool secili: false
                            signal tiklandi()
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: 9
                            color: "transparent"
                            border.width: 2
                            border.color: secici.secili ? Theme.vurgu : Theme.kenarlikVurgu
                            opacity: secici.enabled ? 1 : 0.5
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Theme.vurgu
                                visible: secici.secili
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                enabled: secici.enabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: secici.tiklandi()
                            }
                        }

                        Repeater {
                            id: kalemTekrari
                            model: kalemModel

                            delegate: Rectangle {
                                id: kalemKarti
                                required property int index
                                required property string anahtar
                                required property string kalemAdi
                                required property string neIcin
                                required property real miktar
                                required property string birim
                                required property int siparisNo
                                required property int satinalmaId
                                required property bool arastirilacak

                                readonly property bool kilitli: kalemKarti.siparisNo > 0 || !root.duzenlenebilir
                                readonly property var durumBilgisi: {
                                    root.surum
                                    root.siparisler
                                    return root.kalemDurumu(kalemModel.get(kalemKarti.index))
                                }
                                readonly property string enUcuz: {
                                    root.surum
                                    return kalemKarti.arastirilacak ? root.enUcuzAnahtar(kalemKarti.anahtar) : ""
                                }

                                // Kalemin alinacagi yer (kilitli kartta tek satir ozet).
                                readonly property var alinan: {
                                    root.surum
                                    return root.seciliFiyat(kalemKarti.anahtar)
                                }

                                function odakla() { adAlani.forceActiveFocus() }

                                Layout.fillWidth: true
                                implicitHeight: kartSutun.implicitHeight + 24
                                radius: Theme.radiusNormal
                                color: Theme.panelVurgu
                                border.width: 1
                                border.color: Theme.kenarlik

                                ColumnLayout {
                                    id: kartSutun
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    // ---- Siparisi verilmis kalem: kutusuz, iki satirlik ozet ----
                                    // Sutunlar duzenlenebilir kartla ayni izgarada:
                                    //   malzeme / tedarikci | ne icin | miktar / birim fiyat | durum / tutar
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: kalemKarti.kilitli
                                        spacing: root.sutunAraligi

                                        component UstMetin: KisalanMetin {
                                            Layout.fillWidth: true
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                        }
                                        component AltMetin: KisalanMetin {
                                            Layout.fillWidth: true
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }

                                        Label {
                                            Layout.preferredWidth: root.sutunNo
                                            Layout.alignment: Qt.AlignTop
                                            text: kalemKarti.index + 1
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: true
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            UstMetin {
                                                text: kalemKarti.kalemAdi
                                                font.bold: true
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                AltMetin {
                                                    Layout.fillWidth: false
                                                    text: kalemKarti.alinan ? kalemKarti.alinan.firmaAdi : "Tedarikçi yok"
                                                }
                                                Label {
                                                    visible: !!kalemKarti.alinan && kalemKarti.alinan.link.trim().length > 0
                                                    text: "Ürün sayfası ↗"
                                                    color: linkFare.containsMouse ? Theme.vurguHover : Theme.vurgu
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: Theme.fontBoyutKucuk
                                                    MouseArea {
                                                        id: linkFare
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Qt.openUrlExternally(kalemKarti.alinan.link.trim())
                                                    }
                                                }
                                                AltMetin {
                                                    text: kalemKarti.alinan && kalemKarti.alinan.notu ? kalemKarti.alinan.notu : ""
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: root.sutunNeIcin
                                            Layout.alignment: Qt.AlignTop
                                            spacing: 4
                                            UstMetin {
                                                text: kalemKarti.neIcin || "—"
                                                color: Theme.metinIkincil
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: root.sutunMiktar + root.sutunAraligi + root.sutunBirim
                                            spacing: 4
                                            UstMetin {
                                                text: SatinalmaBicim.miktar(kalemKarti.miktar) + " " + (kalemKarti.birim || "")
                                            }
                                            AltMetin {
                                                text: !kalemKarti.alinan || !(kalemKarti.alinan.birimFiyat > 0) ? "fiyat yok"
                                                      : "× " + SatinalmaBicim.dovizli(kalemKarti.alinan.birimFiyat, kalemKarti.alinan.paraBirimi)
                                                        + (kalemKarti.alinan.paraBirimi !== "TL"
                                                           ? "  (kur " + SayiBicimi.bicimle(kalemKarti.alinan.kur, 4) + ")" : "")
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: root.sutunDurum
                                            spacing: 4
                                            DurumRozeti {
                                                Layout.alignment: Qt.AlignRight
                                                metin: kalemKarti.durumBilgisi.metin
                                                renk: kalemKarti.durumBilgisi.renk
                                                dolu: true
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: kalemKarti.siparisNo > 0
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: siparisPencereleri.ayrintiAc(kalemKarti.satinalmaId)
                                                }
                                            }
                                            Label {
                                                Layout.alignment: Qt.AlignRight
                                                text: kalemKarti.alinan && kalemKarti.alinan.birimFiyat > 0
                                                      ? SatinalmaBicim.para(root.birimFiyatTL(kalemKarti.alinan) * kalemKarti.miktar) : "—"
                                                color: Theme.metinBirincil
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: Theme.fontBoyutNormal
                                                font.bold: true
                                            }
                                        }

                                        Item { Layout.preferredWidth: root.sutunSil }
                                    }

                                    // ---- Kalem satirinin etiketleri ----
                                    // Tedarikci satirindaki gibi kutularin hemen ustunde.
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.bottomMargin: -4
                                        visible: !kalemKarti.kilitli
                                        spacing: root.sutunAraligi
                                        Item { Layout.preferredWidth: root.sutunNo }
                                        AlanEtiketi { text: "MALZEME / HİZMET"; Layout.fillWidth: true }
                                        AlanEtiketi { text: "NE İÇİN"; Layout.preferredWidth: root.sutunNeIcin }
                                        AlanEtiketi { text: "MİKTAR"; Layout.preferredWidth: root.sutunMiktar }
                                        AlanEtiketi { text: "BİRİM"; Layout.preferredWidth: root.sutunBirim }
                                        Item { Layout.preferredWidth: root.sutunDurum + root.sutunAraligi + root.sutunSil }
                                    }

                                    // ---- Ne, ne icin, kac tane ----
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: !kalemKarti.kilitli
                                        spacing: root.sutunAraligi

                                        Label {
                                            Layout.preferredWidth: root.sutunNo
                                            text: kalemKarti.index + 1
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: true
                                        }

                                        OneriliMetinKutusu {
                                            id: adAlani
                                            Layout.fillWidth: true
                                            enabled: !kalemKarti.kilitli
                                            placeholderText: "Örn. ESP32 geliştirme kartı"
                                            text: kalemKarti.kalemAdi
                                            font.bold: kalemKarti.kilitli
                                            enAzHarf: 2
                                            oneriKaynagi: function(metin) { return database.satinalmaKalemOnerileri(metin, 8) }
                                            oneriMetni: function(o) { return o.kalemAdi }
                                            oneriAltMetni: function(o) {
                                                return "son alış: " + SatinalmaBicim.dovizli(o.birimFiyat, o.paraBirimi)
                                                       + (o.tedarikciAdi ? " · " + o.tedarikciAdi : "")
                                                       + (o.tarih ? " · " + SatinalmaBicim.tarih(o.tarih) : "")
                                            }
                                            onTextEdited: root.kalemDegistir(kalemKarti.index, "kalemAdi", text)
                                            // Gecmis alim secilince birim gelir; tek kaynakli kalemde
                                            // yer bos ise son alinan tedarikci onerilir. Eski fiyat
                                            // YAZILMAZ: fiyat 0 "fiyat bekleniyor" demektir, eski
                                            // fiyat kalemi yanlislikla "hazir" gosterirdi.
                                            onOneriSecildi: (o) => {
                                                root.kalemDegistir(kalemKarti.index, "kalemAdi", o.kalemAdi)
                                                if (o.birim)
                                                    root.kalemDegistir(kalemKarti.index, "birim", o.birim)
                                                if (kalemKarti.arastirilacak || !o.tedarikciAdi)
                                                    return
                                                const satirlar = root.fiyatIndeksleri(kalemKarti.anahtar)
                                                if (satirlar.length !== 1 || fiyatModel.get(satirlar[0]).firmaAdi.trim().length > 0)
                                                    return
                                                const t = root.tedarikciler.find(x => x.firmaAdi === o.tedarikciAdi)
                                                root.fiyatDegistir(satirlar[0], "firmaAdi", o.tedarikciAdi)
                                                root.fiyatDegistir(satirlar[0], "tedarikciId", t ? t.tedarikciId : 0)
                                            }
                                        }

                                        OneriliMetinKutusu {
                                            Layout.preferredWidth: root.sutunNeIcin
                                            enabled: !kalemKarti.kilitli
                                            placeholderText: "Örn. pres, sliper"
                                            text: kalemKarti.neIcin
                                            oneriKaynagi: function(metin) { return database.satinalmaNeIcinOnerileri(metin, 8) }
                                            onTextEdited: root.kalemDegistir(kalemKarti.index, "neIcin", text)
                                            onOneriSecildi: (o) => root.kalemDegistir(kalemKarti.index, "neIcin", o)
                                        }

                                        SayiKutusu {
                                            Layout.preferredWidth: root.sutunMiktar
                                            enabled: !kalemKarti.kilitli
                                            ondalik: 3
                                            sadeGoster: true
                                            deger: kalemKarti.miktar
                                            onDegisti: (yeni) => root.kalemDegistir(kalemKarti.index, "miktar", yeni)
                                        }

                                        OneriliMetinKutusu {
                                            Layout.preferredWidth: root.sutunBirim
                                            enabled: !kalemKarti.kilitli
                                            placeholderText: "adet"
                                            text: kalemKarti.birim
                                            gecikme: 0
                                            enAzHarf: 0
                                            odaktaAc: true
                                            okGoster: !kalemKarti.kilitli
                                            oneriKaynagi: function(metin) { return SatinalmaBicim.birimOnerileri(metin) }
                                            onTextEdited: root.kalemDegistir(kalemKarti.index, "birim", text)
                                            onOneriSecildi: (o) => root.kalemDegistir(kalemKarti.index, "birim", o)
                                        }

                                        Item {
                                            Layout.preferredWidth: root.sutunDurum
                                            Layout.preferredHeight: Theme.girdiYuksekligi
                                            DurumRozeti {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: kalemKarti.kalemAdi.trim().length > 0 || kalemKarti.siparisNo > 0
                                                metin: kalemKarti.durumBilgisi.metin
                                                renk: kalemKarti.durumBilgisi.renk
                                                dolu: true
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: kalemKarti.siparisNo > 0
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: siparisPencereleri.ayrintiAc(kalemKarti.satinalmaId)
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: root.sutunSil
                                            Layout.preferredHeight: Theme.girdiYuksekligi
                                            TemaButon {
                                                anchors.fill: parent
                                                tur: "sade"
                                                kucuk: true
                                                text: "✕"
                                                visible: !kalemKarti.kilitli && kalemModel.count > 1
                                                ToolTip.visible: hovered
                                                ToolTip.text: "Kalemi sil"
                                                onClicked: root.kalemSil(kalemKarti.index)
                                            }
                                        }
                                    }

                                    // ---- Tedarikci satirinin etiketleri ----
                                    // Kutularin hemen ustunde, ayni izgarada; sol kisimdaki
                                    // kutularin genislik oranlari ilk satirinkiyle aynidir.
                                    RowLayout {
                                        id: tedarikciEtiketleri
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        Layout.bottomMargin: -4
                                        visible: !kalemKarti.kilitli
                                        spacing: root.sutunAraligi
                                        readonly property bool dovizVar: {
                                            root.surum
                                            return root.fiyatIndeksleri(kalemKarti.anahtar)
                                                       .some(i => fiyatModel.get(i).paraBirimi !== "TL")
                                        }
                                        // Ilk satir site ise (kayitli tedarikci degil) link kutusu vardir.
                                        readonly property bool ilkSite: {
                                            root.surum
                                            const s = root.fiyatIndeksleri(kalemKarti.anahtar)
                                            if (s.length === 0)
                                                return false
                                            const f = fiyatModel.get(s[0])
                                            return f.tedarikciId === 0 && f.firmaAdi.trim().length > 0
                                        }
                                        Item { Layout.preferredWidth: root.sutunNo }
                                        AlanEtiketi { text: "TEDARİKÇİ VEYA SİTE"; Layout.fillWidth: true; Layout.preferredWidth: 2 }
                                        AlanEtiketi {
                                            visible: tedarikciEtiketleri.ilkSite
                                            text: "ÜRÜN LİNKİ"
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 2
                                        }
                                        AlanEtiketi {
                                            text: "NOT"
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: tedarikciEtiketleri.ilkSite ? 1 : 3
                                        }
                                        AlanEtiketi { text: "BİRİM FİYAT"; Layout.preferredWidth: root.sutunNeIcin }
                                        AlanEtiketi {
                                            text: tedarikciEtiketleri.dovizVar ? "KUR" : ""
                                            Layout.preferredWidth: root.sutunMiktar
                                        }
                                        Item { Layout.preferredWidth: root.sutunBirim }
                                        AlanEtiketi {
                                            text: "TUTAR"
                                            Layout.preferredWidth: root.sutunDurum
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Item { Layout.preferredWidth: root.sutunSil }
                                    }

                                    // ---- Tedarikci + fiyat satirlari ----
                                    // fiyatModel tum kalemlerin satirlarini tutar; yalnizca bu
                                    // kalemin satirlari yuklenir (Loader), digerleri bos kalir.
                                    Repeater {
                                        model: fiyatModel

                                        delegate: Loader {
                                            id: fiyatYukleyici
                                            required property int index
                                            required property string anahtar
                                            required property string kalemAnahtar
                                            required property int tedarikciId
                                            required property string firmaAdi
                                            required property string link
                                            required property string notu
                                            required property string paraBirimi
                                            required property real kur
                                            required property real birimFiyat
                                            required property bool secildi

                                            readonly property bool bizim: fiyatYukleyici.kalemAnahtar === kalemKarti.anahtar
                                            // Kayitli tedarikci degilse (site / tek seferlik yer)
                                            // urun linki alani acilir.
                                            readonly property bool site: fiyatYukleyici.tedarikciId === 0
                                                                         && fiyatYukleyici.firmaAdi.trim().length > 0
                                            readonly property bool doviz: fiyatYukleyici.paraBirimi !== "TL"
                                            readonly property real tutarTL: fiyatYukleyici.birimFiyat
                                                                            * (fiyatYukleyici.doviz ? fiyatYukleyici.kur : 1)
                                                                            * kalemKarti.miktar
                                            // Karsilastirmali kalemde secilmeyen satir soluk gorunur.
                                            readonly property bool alinacak: fiyatYukleyici.secildi || !kalemKarti.arastirilacak

                                            Layout.fillWidth: true
                                            active: fiyatYukleyici.bizim && !kalemKarti.kilitli
                                            visible: active
                                            sourceComponent: duzenSatiri

                                            Component {
                                                id: duzenSatiri
                                                RowLayout {
                                                    spacing: root.sutunAraligi

                                                    Item {
                                                        Layout.preferredWidth: root.sutunNo
                                                        Layout.preferredHeight: Theme.girdiYuksekligi
                                                        Secici {
                                                            anchors.centerIn: parent
                                                            visible: kalemKarti.arastirilacak
                                                            secili: fiyatYukleyici.secildi
                                                            onTiklandi: root.fiyatSec(fiyatYukleyici.index)
                                                        }
                                                    }

                                                    OneriliMetinKutusu {
                                                        Layout.fillWidth: true
                                                        Layout.preferredWidth: 2
                                                        placeholderText: "Örn. Büyük Aras, direnc.net"
                                                        text: fiyatYukleyici.firmaAdi
                                                        gecikme: 0
                                                        oneriKaynagi: function(metin) {
                                                            const m = metin.toLocaleLowerCase("tr")
                                                            const tedarikci = root.tedarikciler
                                                                .filter(t => t.firmaAdi.toLocaleLowerCase("tr").indexOf(m) >= 0)
                                                                .map(t => ({ firmaAdi: t.firmaAdi, tedarikciId: t.tedarikciId }))
                                                            const site = root.siteler
                                                                .filter(s => s.toLocaleLowerCase("tr").indexOf(m) >= 0)
                                                                .map(s => ({ firmaAdi: s, tedarikciId: 0 }))
                                                            return tedarikci.concat(site).slice(0, 8)
                                                        }
                                                        oneriMetni: function(o) { return o.firmaAdi }
                                                        oneriAltMetni: function(o) { return o.tedarikciId > 0 ? "kayıtlı tedarikçi" : "internet sitesi" }
                                                        onTextEdited: {
                                                            root.fiyatDegistir(fiyatYukleyici.index, "firmaAdi", text)
                                                            // Elle yazilan ad kayitli bir tedarikciyle ayniysa ona baglanir.
                                                            const t = root.tedarikciler.find(
                                                                x => x.firmaAdi.toLocaleLowerCase("tr") === text.trim().toLocaleLowerCase("tr"))
                                                            root.fiyatDegistir(fiyatYukleyici.index, "tedarikciId", t ? t.tedarikciId : 0)
                                                        }
                                                        onOneriSecildi: (o) => {
                                                            root.fiyatDegistir(fiyatYukleyici.index, "firmaAdi", o.firmaAdi)
                                                            root.fiyatDegistir(fiyatYukleyici.index, "tedarikciId", o.tedarikciId)
                                                        }
                                                    }

                                                    TemaMetinKutusu {
                                                        Layout.fillWidth: true
                                                        Layout.preferredWidth: 2
                                                        visible: fiyatYukleyici.site
                                                        placeholderText: "https://…"
                                                        text: fiyatYukleyici.link
                                                        onTextEdited: root.fiyatDegistir(fiyatYukleyici.index, "link", text)
                                                    }

                                                    TemaMetinKutusu {
                                                        Layout.fillWidth: true
                                                        Layout.preferredWidth: fiyatYukleyici.site ? 1 : 3
                                                        placeholderText: "Örn. fiyat soruldu, kargo dahil"
                                                        text: fiyatYukleyici.notu
                                                        onTextEdited: root.fiyatDegistir(fiyatYukleyici.index, "notu", text)
                                                    }

                                                    // Birim fiyat + para birimi, "ne icin" sutununda.
                                                    RowLayout {
                                                        Layout.preferredWidth: root.sutunNeIcin
                                                        Layout.fillWidth: false
                                                        spacing: 6
                                                        SayiKutusu {
                                                            Layout.fillWidth: true
                                                            sifirdaBos: true
                                                            placeholderText: "0,00"
                                                            deger: fiyatYukleyici.birimFiyat
                                                            onDegisti: (yeni) => root.fiyatDegistir(fiyatYukleyici.index, "birimFiyat", yeni)
                                                            // Son kalemde Enter: yeni kalem.
                                                            onAccepted: if (!kalemKarti.arastirilacak && kalemKarti.index === kalemModel.count - 1)
                                                                            root.kalemEkle(true)
                                                        }
                                                        Rectangle {
                                                            Layout.preferredWidth: 64
                                                            Layout.preferredHeight: Theme.girdiYuksekligi
                                                            radius: Theme.radiusKucuk
                                                            color: Theme.arkaplan
                                                            border.width: 1
                                                            border.color: Theme.kenarlik
                                                            TemaComboBox {
                                                                anchors.fill: parent
                                                                model: SatinalmaBicim.paraBirimleri
                                                                currentIndex: Math.max(0, model.indexOf(fiyatYukleyici.paraBirimi))
                                                                onActivated: root.fiyatDegistir(fiyatYukleyici.index, "paraBirimi", currentText)
                                                            }
                                                        }
                                                    }

                                                    // Kur yalnizca dovizli fiyatta (miktar sutununda).
                                                    Item {
                                                        Layout.preferredWidth: root.sutunMiktar
                                                        Layout.preferredHeight: Theme.girdiYuksekligi
                                                        SayiKutusu {
                                                            anchors.fill: parent
                                                            visible: fiyatYukleyici.doviz
                                                            ondalik: 4
                                                            sifirdaBos: true
                                                            vurgulu: !(fiyatYukleyici.kur > 0)
                                                            placeholderText: "0,0000"
                                                            deger: fiyatYukleyici.kur
                                                            onDegisti: (yeni) => root.fiyatDegistir(fiyatYukleyici.index, "kur", yeni)
                                                        }
                                                    }

                                                    Item { Layout.preferredWidth: root.sutunBirim }

                                                    ColumnLayout {
                                                        Layout.preferredWidth: root.sutunDurum
                                                        spacing: 0
                                                        Label {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: fiyatYukleyici.tutarTL > 0 ? SatinalmaBicim.para(fiyatYukleyici.tutarTL) : "—"
                                                            color: fiyatYukleyici.tutarTL > 0 && fiyatYukleyici.alinacak
                                                                   ? Theme.metinBirincil : Theme.metinSoluk
                                                            font.family: Theme.fontAilesi
                                                            font.pixelSize: Theme.fontBoyutNormal
                                                            font.bold: fiyatYukleyici.alinacak && fiyatYukleyici.tutarTL > 0
                                                        }
                                                        Label {
                                                            Layout.alignment: Qt.AlignRight
                                                            visible: kalemKarti.enUcuz === fiyatYukleyici.anahtar
                                                            text: "en ucuz"
                                                            color: Theme.basariAcik
                                                            font.family: Theme.fontAilesi
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                        }
                                                    }

                                                    Item {
                                                        Layout.preferredWidth: root.sutunSil
                                                        Layout.preferredHeight: Theme.girdiYuksekligi
                                                        TemaButon {
                                                            anchors.fill: parent
                                                            tur: "sade"
                                                            kucuk: true
                                                            text: "✕"
                                                            visible: kalemKarti.arastirilacak
                                                            ToolTip.visible: hovered
                                                            ToolTip.text: "Bu fiyatı sil"
                                                            onClicked: root.fiyatSil(fiyatYukleyici.index)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    TemaButon {
                                        Layout.leftMargin: root.sutunNo + root.sutunAraligi - 12
                                        visible: !kalemKarti.kilitli
                                        tur: "sade"
                                        kucuk: true
                                        text: "+ Alternatif fiyat ekle"
                                        onClicked: root.fiyatEkle(kalemKarti.anahtar)
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 4 }
                    }
                }
            }
        }

        // ---- Siparise donusturme seridi (yalnizca hazir kalem varken) ----
        Rectangle {
            Layout.fillWidth: true
            visible: root.duzenlenebilir && root.siparisGruplari.length > 0
            implicitHeight: seritSatiri.implicitHeight + 28
            radius: Theme.radiusNormal
            color: Theme.panelYukseltilmis
            border.width: 1
            border.color: Theme.kenarlikVurguSoluk

            RowLayout {
                id: seritSatiri
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 14
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 18

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        spacing: 12
                        Label {
                            text: root.durumSayilari.hazir + " kalem siparişe hazır"
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            font.bold: true
                        }
                        Label {
                            text: SatinalmaBicim.para(root.seciliToplamTL)
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutOrta
                            font.bold: true
                        }
                    }
                    KisalanMetin {
                        Layout.fillWidth: true
                        text: root.siparisGruplari.map(g => g.firmaAdi).join("  ·  ")
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk + 1
                    }
                }

                TemaButon {
                    tur: "birincil"
                    text: root.siparisGruplari.length > 1
                          ? root.siparisGruplari.length + " Sipariş Oluştur"
                          : "Sipariş Oluştur"
                    onClicked: root.siparisOlusturBaslat()
                }
            }
        }
    }

    OnayDialog { id: onayDialogu }

    // Kalemin siparisi talepten cikmadan acilir (ayrinti, teslim, fatura).
    SiparisPencereleri {
        id: siparisPencereleri
        anchors.fill: parent
        duzenleyebilir: root.duzenleyebilir
        talepBaglantisi: false
        onHataOldu: (mesaj) => {
            root.hata = mesaj
            root.bilgi = ""
        }
        onIslemYapildi: (mesaj) => {
            // Iptal edilen siparisin kalemleri talepte yeniden acilir: kayitli
            // degisiklik yoksa talep bastan okunur, varsa yalnizca siparisler.
            if (root.degisti)
                root.siparisler = database.talepGetir(root.talepId).siparisler || []
            else
                root.ac(root.talepId, true)
            root.hata = ""
            root.bilgi = mesaj
            root.kaydedildi()
        }
    }

    // ---- Talep iptal ----
    TemaDialog {
        id: iptalDialogu
        baslik: "Talebi İptal Et — " + SatinalmaBicim.talepNo(root.talepNo)
        onayMetni: "İptal Et"
        tehlikeli: true
        elleKapat: true
        width: 460

        onOpened: {
            iptalSebebi.text = ""
            iptalHatasi.text = ""
        }
        onOnaylandi: {
            const sonuc = database.talepIptalEt(root.talepId, iptalSebebi.text)
            if (!sonuc.basarili) {
                iptalHatasi.text = sonuc.hata
                return
            }
            iptalDialogu.close()
            root.ac(root.talepId, true)
            root.kaydedildi()
        }

        contentItem: ColumnLayout {
            spacing: 10
            EtiketliAlan {
                id: iptalSebebi
                etiket: "SEBEP (OPSİYONEL)"
                placeholderText: "Vazgeçildi, stoktan karşılandı…"
            }
            Label {
                id: iptalHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- Siparis olusturma ----
    // Tedarikci basina bir kart: teslimat sekli, beklenen teslim, (esik
    // ustuyse) patron onayi.
    TemaDialog {
        id: siparisDialogu
        baslik: siparisBilgiModel.count > 1 ? siparisBilgiModel.count + " Sipariş Oluştur" : "Sipariş Oluştur"
        onayMetni: "Oluştur"
        elleKapat: true
        width: Math.min(root.width - 80, 680)

        function ac() {
            siparisBilgiModel.clear()
            for (const g of root.siparisGruplari) {
                const onay = root.onayEsigi > 0 && g.oncekiTL + g.toplamTL > root.onayEsigi
                siparisBilgiModel.append({
                    teklifFirmaId: g.teklifFirmaId, firmaAdi: g.firmaAdi, toplamTL: g.toplamTL,
                    oncekiTL: g.oncekiTL,
                    kalemMetni: g.kalemler.join("\n"), kalemSayisi: g.kalemler.length,
                    teslimatSekli: g.kaynak === "İnternet" ? "Kargo" : "",
                    beklenen: g.teslimSuresiGun > 0 ? SatinalmaBicim.gunEkle(g.teslimSuresiGun) : "",
                    onayGerekli: onay, patronOnayli: false })
            }
            siparisHatasi.text = ""
            siparisDialogu.open()
        }

        onOnaylandi: {
            var bilgiler = []
            for (var i = 0; i < siparisBilgiModel.count; ++i) {
                const b = siparisBilgiModel.get(i)
                if (b.teslimatSekli.length === 0) {
                    siparisHatasi.text = "\"" + b.firmaAdi + "\" için teslimat şeklini seçin."
                    return
                }
                bilgiler.push({ teklifFirmaId: b.teklifFirmaId, teslimatSekli: b.teslimatSekli,
                                beklenenTeslimTarihi: b.beklenen, patronOnayli: b.patronOnayli })
            }
            const sonuc = database.talepSiparisOlustur(root.talepId, bilgiler)
            if (!sonuc.basarili) {
                siparisHatasi.text = sonuc.hata
                return
            }
            siparisDialogu.close()
            root.ac(root.talepId, true)
            const nolar = sonuc.siparisler.map(s => SatinalmaBicim.siparisNo(s.siparisNo))
            const onayda = sonuc.siparisler.filter(s => s.durum === "Patron Onayı Bekliyor").length
            root.bilgi = nolar.join(", ") + " oluşturuldu."
                         + (onayda > 0 ? " " + onayda + " sipariş patron onayı bekliyor." : "")
            root.kaydedildi()
        }

        contentItem: ColumnLayout {
            spacing: 12

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(kartlar.implicitHeight, root.height - 300)
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: kartlar
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: siparisBilgiModel
                        delegate: Rectangle {
                            id: grupKarti
                            required property int index
                            required property string firmaAdi
                            required property real toplamTL
                            required property real oncekiTL
                            required property string kalemMetni
                            required property int kalemSayisi
                            required property string teslimatSekli
                            required property string beklenen
                            required property bool onayGerekli
                            required property bool patronOnayli

                            Layout.fillWidth: true
                            implicitHeight: grupSutun.implicitHeight + 24
                            radius: Theme.radiusNormal
                            color: Theme.panelVurgu
                            border.width: 1
                            border.color: grupKarti.onayGerekli ? Theme.uyari : Theme.kenarlik

                            ColumnLayout {
                                id: grupSutun
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    KisalanMetin {
                                        Layout.fillWidth: true
                                        text: grupKarti.firmaAdi
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutOrta
                                        font.bold: true
                                    }
                                    Label {
                                        text: grupKarti.kalemSayisi + " kalem · " + SatinalmaBicim.para(grupKarti.toplamTL)
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: grupKarti.kalemMetni
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    wrapMode: Text.WordWrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        AlanEtiketi { text: "TESLİMAT ŞEKLİ" }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.girdiYuksekligi
                                            radius: Theme.radiusKucuk
                                            color: Theme.arkaplan
                                            border.width: 1
                                            border.color: grupKarti.teslimatSekli.length === 0 ? Theme.uyari : Theme.kenarlik
                                            TemaComboBox {
                                                anchors.fill: parent
                                                model: SatinalmaBicim.teslimatSekilleri
                                                currentIndex: model.indexOf(grupKarti.teslimatSekli)
                                                displayText: currentIndex < 0 ? "Seçin…" : currentText
                                                onActivated: siparisBilgiModel.setProperty(grupKarti.index, "teslimatSekli", currentText)
                                            }
                                        }
                                    }

                                    TarihSecici {
                                        Layout.preferredWidth: 190
                                        etiket: "BEKLENEN TESLİM"
                                        gecmisKapali: true
                                        deger: grupKarti.beklenen
                                        onSecildi: (tarih) => siparisBilgiModel.setProperty(grupKarti.index, "beklenen", tarih)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: grupKarti.onayGerekli
                                    implicitHeight: onaySatiri.implicitHeight + 16
                                    radius: Theme.radiusKucuk
                                    color: Theme.uyariZemin
                                    RowLayout {
                                        id: onaySatiri
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 10
                                        Label {
                                            Layout.fillWidth: true
                                            text: "Onay eşiği (" + SatinalmaBicim.para(root.onayEsigi) + ") aşıldı"
                                                  + (grupKarti.oncekiTL > 0
                                                     ? " · önceki siparişlerle toplam "
                                                       + SatinalmaBicim.para(grupKarti.oncekiTL + grupKarti.toplamTL)
                                                     : "")
                                            color: Theme.uyariAcik
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                            wrapMode: Text.WordWrap
                                        }
                                        TemaOnayKutusu {
                                            text: "Patron onayı alındı"
                                            checked: grupKarti.patronOnayli
                                            onToggled: siparisBilgiModel.setProperty(grupKarti.index, "patronOnayli", checked)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Label {
                id: siparisHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }
}
