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
//
// DURUM DEGISIKLIGI: Her satirin durum rozeti tiklanabilir bir menudur ve teklifi
// mevcut durumundan BASKA HERHANGI BIR duruma alabilir -- uc sekmede de. Yani
// "Kabul Edildi" yapilmis bir teklif, musteri sonradan vazgecerse Alınan
// Tekliflerim'den "Reddedildi"ye, kararsiz kalirsa "Beklemede"ye cekilebilir;
// tamamlanmis bir teklif de geri alinabilir. Degisimlerin izi, menudeki
// "Durum Geçmişi" penceresinden goruntulenir.
Item {
    id: root

    // Tarih sutunlarinin basligi: dar sutuna sigmayan basliklar iki satira sarilir.
    // (KisalanMetin: iki satira da sigmayip kirpilirsa tam baslik ipucunda cikar.)
    component TarihBasligi: KisalanMetin {
        color: Theme.metinCokSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutKucuk
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.9
        Layout.preferredWidth: root.sutunTarih
        Layout.maximumWidth: root.sutunTarih
    }

    // Veri satirindaki tarih hucresi. Uretim PDF tarihi "dd.MM.yyyy HH:mm"
    // geldigi icin saat ikinci satira, daha soluk yazilir.
    component TarihHucresi: Column {
        property string deger: ""
        Layout.preferredWidth: root.sutunTarih
        Layout.maximumWidth: root.sutunTarih
        Layout.alignment: Qt.AlignVCenter
        spacing: 0
        KisalanMetin {
            width: root.sutunTarih
            text: parent.deger.length > 0 ? parent.deger.split(" ")[0] : "—"
            // Saatli degerlerde ipucu tam tarihi/saati birlikte verir.
            ipucuMetni: parent.deger
            color: parent.deger.length > 0 ? Theme.metinIkincil : Theme.metinCokSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
        }
        Text {
            visible: parent.deger.indexOf(" ") > 0
            text: parent.deger.substring(parent.deger.indexOf(" ") + 1)
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk - 1
        }
    }

    // Bir satirda "Detay" butonuna basildiginda yayinlanir; SatisModuluPage bunu
    // dinleyip "Teklif Ver" sekmesine gecip TeklifVerPage.duzenlemeyeBasla()'yi
    // cagirir -- Detay, o teklifin verileriyle DOLU Teklif Ver ekranini acar.
    signal detayIstendi(int teklifId)

    // "Kopya" butonuna basildiginda yayinlanir; SatisModuluPage bunu dinleyip ayni
    // alt sayfada TeklifVerPage.kopyalamayaBasla()'yi cagirir -- teklifin ICERIGI
    // dolu, MUSTERISI bos bir "yeni teklif" ekrani acilir. Detay'dan farki: kaydedince
    // revizyon degil, kaynak teklife hic dokunmayan BAGIMSIZ bir teklif olusur
    // (satis personeli ayni teklifi farkli firmalara verebilsin diye).
    signal kopyaIstendi(int teklifId)

    readonly property int sayfaBoyutu: 50

    // --- Tablo sutun genislikleri -------------------------------------------
    // Baslik satiri ile veri satirlari AYNI degerleri kullanmak zorunda; bu yuzden
    // genislikler tek bir yerde tanimlanip iki tarafta da buradan okunur. Bir sutunu
    // genisletmek/daraltmak icin sadece asagidaki sayiyi degistirmek yeterli.
    // FIRMA ADI sutunu kalan tum alani kaplar (her iki tarafta da Layout.fillWidth).
    readonly property int sutunBosluk: 8
    readonly property int sutunKenarBosluk: 12
    // SUTUN OLCULERI: hepsi sabit; FİRMA ADI sutunu artan TUM alani alir.
    // Satirdaki en onemli bilgi firma adi oldugu icin sabit sutunlar iceriklerinin
    // gercek ihtiyacina gore dar tutulur -- her kazanilan piksel dogrudan firma
    // adina gider. (Sigmayan degerler "…" ile kirpilir ve KisalanMetin sayesinde
    // uzerine gelindiginde tam haliyle okunur; bu yuzden bol pay birakmak gerekmez.)
    //
    // Teklif no + revizyon rozeti + not ikonu ("5517 Rev.2 📝").
    readonly property int sutunTeklifNo: 86
    // Teklif / Kabul / Planlanan Teslim / Teslim / Uretim PDF tarihlerinin her biri.
    // "08.10.2026" bu font boyutunda ~62px; 72 tam sigar (5 sutun x 8px kazanc).
    readonly property int sutunTarih: 72
    // Icerik personelin kisa kullanici adidir ("EÖ"); sutunu belirleyen sey
    // basligin kendisiydi, o yuzden baslik "TEKLİFİ YAPAN" -> "PERSONEL" oldu.
    readonly property int sutunPersonel: 72
    // Genel toplam (KDV dahil, teklifin kendi para biriminde): "15.600,00 ₺".
    readonly property int sutunTutar: 104

    function paraSembolu(pb) {
        return pb === "USD" ? "$" : (pb === "EUR" ? "€" : "₺")
    }
    function tutarMetni(tutar, pb) {
        return Number(tutar || 0).toLocaleString(Qt.locale("tr_TR"), 'f', 2) + " " + root.paraSembolu(pb)
    }
    // Alınan/Biten Tekliflerim basligindaki sekme toplami: para birimi bazinda
    // ("12.500,00 ₺ · 3.200,00 $"); farkli para birimleri toplanmaz.
    readonly property string sekmeToplamiMetni: {
        const liste = root.sayfaSonucu.paraBirimiToplamlari || []
        return liste.map(t => root.tutarMetni(t.toplam, t.paraBirimi)).join("  ·  ")
    }
    // Durum rozeti artik tiklanabilir bir menu acicisi oldugu icin icinde bir de
    // "▾" isareti tasiyor; sutun ona gore bir miktar genisletildi.
    readonly property int sutunDurum: 126
    // Detay + PDF (+ Uretim + İrsaliye) + Sil butonlari ve aralarindaki 6px
    // bosluklar; "Kopya" butonu gosterildiginde kendisi + boslugu icin +64.
    //
    // Alınan/Biten sekmesindeki olcu butonlarin GERCEK ihtiyacindan turetilir:
    // Detay 58 + PDF 50 + Uretim 64 + İrsaliye 70 + 4 x 6px bosluk = 266; uzun
    // metin/DPI icin pay birakilip 272 kullanilir. Burada eskiden 340
    // yaziyordu: bu fazlalik dar ekranda (1920 ekranda bile) satirin
    // toplam genisligini pencereye sigmayacak hale getiriyor, RowLayout da
    // once FİRMA ADI sutununu sifira eziyor, sonra artani tasirip son butonu
    // -- "İrsaliye" -- sagdan kirpiyordu.
    readonly property int sutunIslemler: (root.uretimButonuGoster ? 272 : 190)
                                         + (root.kopyaButonuGoster ? 64 : 0)
    // FİRMA ADI satirin en onemli bilgisidir: pencere daralsa bile sutun bu
    // olcunun altina ezilmez (eskiden tek "esneyen" sutun o oldugu icin once o
    // sifirlaniyor, basligi bile kaybolup satirda "F…" kaliyordu).
    readonly property int firmaSutunuEnAz: 150

    // Firma adina bu kadar yer kalmayacak kadar dar pencerelerde, satirin ikincil
    // tarih sutunlari (PLANLANAN TESLİM ve ÜRETİM PDF) gizlenir. Boylece daralma
    // firma adindan degil en az kullanilan sutunlardan karsilanir; satir hicbir
    // zaman pencereyi tasirip son butonu ("İrsaliye") kirpmaz.
    readonly property bool ikincilTarihSutunlariGoster: root.width >= 1200

    // Aciklamalar sutunu yalnizca yer oldugunda gosterilir; dar ekranda Firma Adi
    // sutunu ezilmesin diye gizlenir (icerik yine satirin tooltip'inde okunur).
    readonly property bool aciklamaSutunuGoster: root.width >= 1360

    // "Üretim" (uretim PDF'i) butonu: siparis kesinlesmis teklifler icin anlamli
    // oldugundan Alınan ve Biten Tekliflerim'de gosterilir.
    readonly property bool uretimButonuGoster: root.durumFiltresi === "Kabul Edildi" || root.durumFiltresi === "Tamamlandı"

    // "Kopya" butonu YALNIZCA Giden Tekliflerim'de (durumFiltresi bos olan sekme)
    // gosterilir. Kopya, teklif hazirlama akisina ait bir kisayoldur: ayni icerigi
    // baska bir firmaya teklif etmek icindir. Alınan (kabul edilmis) ve Biten
    // (tamamlanmis) tekliflerde ise is artik satis degil takip/uretim asamasindadir;
    // oradan yeni teklif uretmek anlamsiz kaliyordu.
    readonly property bool kopyaButonuGoster: root.durumFiltresi === "" && root.duzenleyebilir

    // "İrsaliye" (sevk ve irsaliye bilgileri) butonu da ayni iki sekmede
    // gosterilir: fatura/irsaliye basligi ve siparis sartlari ancak siparis
    // kesinlestikten sonra netlesir (bkz. root.irsaliyeAc).
    readonly property bool irsaliyeButonuGoster: root.uretimButonuGoster

    // --- Yuksekliklerin 4'un katina yuvarlanmasi (piksel hizalamasi) ----------
    // Windows'ta ekran olcegi genelde %125'tir (devicePixelRatio = 1.25). Bu
    // olcekte MANTIKSAL bir olcu ancak 4'un kati oldugunda tam FIZIKSEL piksele
    // denk gelir (54 * 1.25 = 67.5 -> yarim piksel; 56 * 1.25 = 70 -> tam).
    // Satir delegate'i layer.enabled ile ayri bir texture'a render edildiginden,
    // yarim piksele denk gelen satirlarda texture 0.5 piksel kayik cizilir ve
    // 1px'lik kenarliklar tamamen kaybolur -- listede her ikinci/besinci satirda
    // "Detay butonunun ust cizgisi yok" goruntusunun sebebi buydu.
    //
    // Bu yuzden: satir yuksekligi + ListView spacing (52 + 4 = 56) ve icerikten
    // turetilen tum oge yukseklikleri 4'un katidir. Ikisi de 4'un kati oldugunda
    // dikey ortalama farki da ((52-28)/2 = 12) tam piksele oturur.
    function hizalanmisYukseklik(h) { return 4 * Math.ceil(h / 4) }
    readonly property int satirYuksekligi: 52

    // Hangi sekme oldugumuzu belirler (bkz. yukaridaki not) ve baslikta gosterilir.
    property string durumFiltresi: ""
    property string baslikMetni: "Giden Tekliflerim"

    // Durum degisikligini yapan personel; durum gecmisi logunda "kim degistirdi"
    // olarak saklanir. SatisModuluPage oturumdaki kullaniciyi buraya aktarir.
    property int kullaniciId: 0

    // Kullanicinin Satis modulunde duzenleme yetkisi (rol_yetkileri.Duzenleyebilir).
    // Yoksa liste salt goruntulemedir: durum degistirme, Kopya, Sil ve sevk
    // bilgisi kaydetme kapalidir; Detay/PDF/gecmis acilabilir.
    property bool duzenleyebilir: true

    // --- Durum degistirme -----------------------------------------------------
    // Teklif durumu TEK YONLU DEGILDIR: musteri kabul ettikten sonra vazgecebilir,
    // kararsiz kalip "bekleyin" diyebilir, tamamlanmis bir teklif yanlislikla
    // tamamlanmis olabilir. Bu yuzden HER satirin durum rozeti tiklanabilir bir
    // menudur ve mevcut durum ne olursa olsun diger tum durumlara gecis yapilabilir
    // -- ustelik uc sekmenin (Giden/Alınan/Biten) hepsinde. Gecerli durum listesi
    // C++ tarafindan (Database::gecerliDurumlar) gelir; tek kaynak orasidir.
    readonly property var durumSecenekleri: database.gecerliDurumlar()

    function digerDurumlar(mevcutDurum) {
        return root.durumSecenekleri.filter(d => d !== mevcutDurum)
    }

    // Bu satir GECERSIZ KILINMIS bir surum mu? Yani zincirde yerine gecen (daha
    // yeni) bir teklif GERCEKTEN var mi? guncelTeklifId zincirin en son kaydini
    // gosterir; bu satirin kendisiyse (yeni revizyon silinmis olabilir) kayit
    // gecerlidir. Durum sutununa bakilmaz: eskiden yalnizca "Revize Edildi"
    // satirlar kilitleniyordu ve yerine yeni revizyon gecmis "Reddedildi" bir
    // surum menuden "Kabul Edildi" yapilabiliyordu (C++ tarafi da ayni kurali uygular).
    function revizeEdilmisMi(kayit) {
        return kayit.guncelTeklifId > 0 && kayit.guncelTeklifId !== kayit.teklifId
    }

    // Rozet menusunde gosterilecek durumlar. Revize edilmis (gecersiz) bir teklifte
    // HICBIRI gosterilmez: eski surumu "Kabul Edildi" yapmak, guncel revizyon
    // beklemede dururken ayni teklifin iki fiyatli surumunu birden gecerli
    // gostermek olurdu. Kural C++ tarafinda da uygulanir (teklifDurumGuncelle),
    // burasi yalnizca kullaniciya sebebi gosteren yuzu.
    // "Tamamlandı" yalnizca kabul edilmis teklifte sunulur: kabul edilmemis bir
    // teklif tamamlanamaz (ayni kural C++ teklifDurumGuncelle'de de var).
    function durumMenusuSecenekleri(kayit) {
        if (root.revizeEdilmisMi(kayit) || !root.duzenleyebilir)
            return []
        return root.digerDurumlar(kayit.durum)
                   .filter(d => d !== "Tamamlandı" || kayit.durum === "Kabul Edildi")
    }

    // Menuden bir durum secildiginde cagrilir. "Reddedildi" secildiginde once red
    // sebebi sorulur, diger gecislerde kisa bir onay penceresi acilir -- zira bu
    // islem satiri bulundugu sekmeden tamamen dusurebilir (ornegin Alınan
    // Tekliflerim'deki bir teklif "Reddedildi" yapilinca artik o listede gorunmez).
    // Kullaniciya gosterilen numara ("1203", "1203/Rev.2"). teklifId sistemin ic
    // anahtaridir: islemler onunla yapilir ama ekrana/mesaja hic yazilmaz.
    // Satir o an listede yoksa (ornegin sayfa bu arada yenilendiyse) veritabanina sorulur.
    function teklifNo(teklifId) {
        const kayit = root.kayitlarListesi.find(k => k.teklifId === teklifId)
        return kayit ? kayit.teklifNo : database.teklifNoGetir(teklifId)
    }

    function durumDegistirmeyiBaslat(teklifId, eskiDurum, yeniDurum) {
        if (yeniDurum === "Reddedildi") {
            redSebebiGirisi.text = ""
            reddetDialogu.hedefTeklifId = teklifId
            reddetDialogu.eskiDurum = eskiDurum
            reddetDialogu.open()
            return
        }
        durumOnayDialogu.hedefTeklifId = teklifId
        durumOnayDialogu.eskiDurum = eskiDurum
        durumOnayDialogu.yeniDurum = yeniDurum
        // Kabulde planlanan teslim tarihi zorunlu; teklifte zaten girilmisse
        // (liste "dd.MM.yyyy" verir) onunla baslar.
        const kayit = root.kayitlarListesi.find(k => k.teklifId === teklifId)
        const p = kayit && kayit.teslimatTarihi ? kayit.teslimatTarihi.split(".") : []
        durumOnayDialogu.teslimatTarihi = p.length === 3 ? p[2] + "-" + p[1] + "-" + p[0] : ""
        durumOnayDialogu.open()
    }

    // Asil guncelleme tek bir yerden gecer; boylece basari/hata mesaji ve listenin
    // yenilenmesi her cagri noktasinda tekrar yazilmak zorunda kalmaz.
    function durumUygula(teklifId, yeniDurum, redSebebi) {
        const basarili = database.teklifDurumGuncelle(teklifId, yeniDurum, redSebebi || "", root.kullaniciId)
        if (!basarili) {
            // C++ tarafi reddin sebebini yaziyorsa (ornegin revize edilmis teklif)
            // kullaniciya onu gosteriyoruz; yoksa genel mesaja duseriz.
            const sebep = database.sonHataMesaji()
            root.pdfMesaji = sebep && sebep.length > 0
                             ? sebep
                             : "Teklif " + root.teklifNo(teklifId) + " durumu güncellenemedi."
            root.pdfMesajiHata = true
            // Engel bir yarista (baska kullanici bu arada revizyon kaydetmis olabilir)
            // dogmus olabilir; listeyi yenileyerek satiri guncel haliyle gosteriyoruz.
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            return false
        }

        // Filtreli bir sekmedeysek (Alınan/Biten) ve yeni durum o filtreye uymuyorsa
        // satir bu listeden kaybolur; kullanici "kayboldu" sanmasin diye nerede
        // bulacagini soyluyoruz.
        var mesaj = "Teklif " + root.teklifNo(teklifId) + " → " + yeniDurum
        if (root.durumFiltresi !== "" && root.durumFiltresi !== yeniDurum)
            mesaj += " (" + (yeniDurum === "Kabul Edildi" ? "Alınan Tekliflerim"
                             : yeniDurum === "Tamamlandı" ? "Biten Tekliflerim"
                             : "Giden Tekliflerim") + ")"
        root.pdfMesaji = mesaj
        root.pdfMesajiHata = false
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        return true
    }

    function durumGecmisiniAc(teklifId) {
        gecmisDialogu.hedefTeklifId = teklifId
        gecmisDialogu.kayitlar = database.teklifDurumGecmisiGetir(teklifId)
        gecmisDialogu.open()
    }

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

    // Asenkron yuklemenin durumu (bkz. root.sayfayiYukle). "bekleyenIstek", en
    // son baslatilan sorgunun numarasi: yalnizca BU numarayla donen sonuc
    // ekrana basilir, boylece hizli yazarken gecikmis sonuc guncelini ezmez.
    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    property string aramaMetni: ""
    property string secilenTarihFiltresi: "Hepsi"
    property string baslangicTarihi: ""
    property string bitisTarihi: ""
    property string pdfMesaji: ""
    property bool pdfMesajiHata: false

    // Ust koşedeki bildirim gecici bir geri bildirimdir; mesaj her degistiginde
    // 5 saniyelik sayac bastan baslar ve sure dolunca yazi kendiliginden kaybolur.
    // Mesaji kimin yazdigi onemli degil (durum degisikligi, PDF, hata, revizyon
    // bildirimi) -- hepsi pdfMesaji uzerinden gectigi icin tek yerden yonetilir.
    onPdfMesajiChanged: {
        if (root.pdfMesaji.length > 0)
            mesajZamanlayici.restart()
        else
            mesajZamanlayici.stop()
    }

    Timer {
        id: mesajZamanlayici
        interval: 5000
        onTriggered: root.pdfMesaji = ""
    }

    // Sayfanin ust kosesindeki durum mesaji alanini disaridan (SatisModuluPage --
    // ornegin revizyon kaydedilip listeye donuldugunde) beslemek icin.
    function durumMesajiGoster(metin) {
        root.pdfMesaji = metin
        root.pdfMesajiHata = false
    }

    // PDF onizlemede acilir (uretim hatasi da orada yazar); klasore kaydetmek
    // onizlemedeki "İndir" ile olur.
    function pdfOlusturVeAc(teklifId) {
        PdfOnizleme.ac("teklif", teklifId, "Teklif " + root.teklifNo(teklifId))
    }

    // Teknik ekip icin fiyatsiz uretim PDF'i. Teklifin "Üretim PDF" tarihi
    // onizlemede degil, "İndir"e basilinca dolar (asagidaki Connections).
    function uretimPdfOlusturVeAc(teklifId) {
        PdfOnizleme.ac("uretim", teklifId, "Üretim · Teklif " + root.teklifNo(teklifId))
    }

    // Uretim PDF'i indirildiyse "Üretim PDF" tarihi degisti; listede hemen gorunsun.
    Connections {
        target: PdfOnizleme
        function onKaydedildi(pdf, dosyaYolu) {
            if (pdf.tur === "uretim")
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        }
    }

    // --- Sevk ve irsaliye bilgileri ------------------------------------------
    // Siparis kesinlestikten sonra faturanin/irsaliyenin hangi baslik, adres ve
    // vergi bilgileriyle kesilecegi ile siparis sartlari (KDV, garanti, teslimat,
    // odeme, nakliye...) satis personeli ve buro personeli tarafindan bu
    // pencerede doldurulur; sonradan ayni butondan okunur. Veri teklif basina
    // tek kayittir (dbo.sevk_bilgileri).
    //
    // Tamamlanmis teklifte pencere SALT OKUNUR acilir -- is bitmis bir siparisin
    // sevk bilgileri artik degistirilemez (ayni kural C++ tarafinda da uygulanir,
    // bkz. Database::sevkBilgileriKaydet).
    function irsaliyeAc(kayit) {
        const sonuc = database.sevkBilgileriGetir(kayit.teklifId)
        if (!sonuc.basarili) {
            root.pdfMesaji = "Teklif " + kayit.teklifNo + " sevk bilgileri açılamadı: " + sonuc.hata
            root.pdfMesajiHata = true
            return
        }
        sevkDialogu.teklifId = kayit.teklifId
        sevkDialogu.teklifNo = kayit.teklifNo
        sevkDialogu.firmaAdi = kayit.firmaAdi
        sevkDialogu.saltOkunur = kayit.durum === "Tamamlandı" || !root.duzenleyebilir
        sevkDialogu.faturaSaltOkunur = !root.duzenleyebilir
        sevkDialogu.veri = sonuc
        sevkDialogu.open()
    }

    // Sevk alanlari ile fatura/irsaliye numaralari ayri kaydedilir: teklif
    // "Tamamlandı" ise sevk alanlari kilitlidir ama numaralar yine yazilir.
    function sevkBilgileriniKaydet(teklifId, sevk) {
        if (!sevkDialogu.saltOkunur) {
            const sonuc = database.sevkBilgileriKaydet(teklifId, sevk)
            if (!sonuc.basarili) {
                root.pdfMesaji = "Teklif " + root.teklifNo(teklifId) + " sevk bilgileri kaydedilemedi: " + sonuc.hata
                root.pdfMesajiHata = true
                return
            }
        }
        if (sevkDialogu.faturaAlanlariVar && !sevkDialogu.faturaSaltOkunur && sevkDialogu.faturaDegistiMi(sevk)) {
            const faturaSonucu = database.faturaBilgisiKaydet(teklifId, sevkDialogu.faturaDegisiklikleri(sevk))
            if (!faturaSonucu.basarili) {
                root.pdfMesaji = "Teklif " + root.teklifNo(teklifId) + ": " + faturaSonucu.hata
                root.pdfMesajiHata = true
                root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
                return
            }
        }
        root.pdfMesaji = "Teklif " + root.teklifNo(teklifId) + " sevk bilgileri kaydedildi."
        root.pdfMesajiHata = false
        // AÇIKLAMALAR sutunu bu kayittan beslendigi icin (bkz. aciklamaMetni)
        // listeyi yenileyip yeni aciklamayi hemen gosteriyoruz.
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
    }

    // Aciklamalar sutunu: sevk kaydinin aciklamasi ("İrsaliye" penceresindeki
    // AÇIKLAMALAR alani; eski programdan gocen kayitlarda da ayni alan). Notlar
    // burada metin olarak yer kaplamaz; Teklif No hucresindeki not ikonuyla gosterilir.
    // Faturalanmis teklifte fatura no basa eklenir.
    function aciklamaMetni(kayit) {
        const aciklama = (kayit.aciklamalar || "").trim()
        const faturaNo = (kayit.faturaNo || "").trim()
        if (faturaNo.length === 0 || !root.irsaliyeButonuGoster)
            return aciklama
        return "Fatura " + faturaNo + (aciklama.length > 0 ? "  ·  " + aciklama : "")
    }

    // Satirda gosterilecek not, sekmeye gore tek bir tanedir.
    // Giden Tekliflerim satis tarafinin listesidir -> teklif notu.
    // Alınan/Biten Tekliflerim uretime giden siparislerdir -> YALNIZCA uretim notu;
    // teklif notu burada (ve uretim PDF'inde) uretimciye gorunmez.
    readonly property bool teklifNotuSekmesi: root.durumFiltresi === ""

    function satirNotu(kayit) {
        return ((root.teklifNotuSekmesi ? kayit.musteriNotu : kayit.uretimNotu) || "").trim()
    }

    function notuGoster(kayit) {
        notGoruntuleDialogu.baslik = "Teklif " + kayit.teklifNo + " — "
                                     + (root.teklifNotuSekmesi ? "Teklif Notu" : "Üretim Notu")
        notGoruntuleDialogu.metin = root.satirNotu(kayit)
        notGoruntuleDialogu.open()
    }

    // Kabul edilmis / tamamlanmis teklif kilitlidir: silinemez (bkz. Database::teklifKilitliMi).
    function teklifKilitliMi(durum) {
        return durum === "Kabul Edildi" || durum === "Tamamlandı"
    }

    // YUKLEME ASENKRONDUR: sorgu, canli arama ve diger sayfali listelerle ayni
    // worker thread'i uzerinde calisir, sonuc database.teklifListesiHazir
    // sinyaliyle gelir. Eskiden burada gecmisTekliflerGetir SENKRON cagriliyordu
    // ve sorgu (ozellikle arama metni varken) UI thread'ini saniyelerce bloke
    // edip pencereyi "Yanıt Vermiyor" durumuna dusuruyordu.
    function sayfayiYukle(sayfaNo) {
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.gecmisTekliflerGetirBaslat(
            root.aramaMetni, root.secilenTarihFiltresi, root.baslangicTarihi,
            root.bitisTarihi, sayfaNo, root.sayfaBoyutu, root.durumFiltresi)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onTeklifListesiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return                       // eskimis sonuc -- yok say
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            // Worker baglanti kuramadiysa bos harita yayinlar.
            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "Teklif listesi yüklenemedi: veritabanına bağlanılamadı."
                root.sayfaSonucu = ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
                root.kayitlarListesi = []
                return
            }

            root.sayfaSonucu = sonuc
            // Model'i once bosaltip sonra doldurmak, ListView'in olasi hatali bir
            // "change-set" (ekleme/silme farki) hesaplamasi yerine temiz bir
            // "reset" yapmasini garantiler.
            root.kayitlarListesi = []
            root.kayitlarListesi = sonuc.kayitlar
        }
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle(1)

    // Arama kutusunda her tus vurusunda degil, kullanici yazmayi biraktiktan
    // kisa bir sure sonra sorgu atiyoruz (WPF tarafindaki DispatcherTimer ile ayni fikir).

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
            root.listeHatasi = "Teklif listesi sunucudan yanıt alınamadığı için yüklenemedi. "
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
                    text: root.baslikMetni
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.sayfaSonucu.toplamKayit + " kayıt"
                          + (root.sekmeToplamiMetni.length > 0 ? "   —   Toplam (KDV dahil): " + root.sekmeToplamiMetni : "")
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            // Gecici bildirim (durum degisti / PDF olusturuldu / hata): 5 saniye
            // sonra kendiliginden kaybolur, bkz. root.mesajZamanlayici.
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

                TemaComboBox {
                    id: tarihCombo
                    anchors.fill: parent
                    model: ["Hepsi", "1 Gün", "1 Hafta", "15 Gün", "30 Gün", "Özel Tarih"]
                    onActivated: {
                        root.secilenTarihFiltresi = currentText
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
            // "PLANLANAN TESLİM" gibi uzun tarih basliklari dar sutunda iki satira sarilir.
            height: 44
            color: Theme.panel
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.sutunKenarBosluk
                anchors.rightMargin: root.sutunKenarBosluk
                spacing: root.sutunBosluk

                // NOT: Basliklarda da Layout.preferredWidth'in gercekten uygulanmasi
                // icin maximumWidth ile sinirliyoruz; aksi halde "TEKLİFİ YAPAN" gibi
                // uzun bir baslik metni kendi dogal genisligiyle sutunu sisirip veri
                // satirlariyla arasinda kayma olusturabiliyor.
                KisalanMetin { text: "TEKLİF NO"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunTeklifNo; Layout.maximumWidth: root.sutunTeklifNo }
                KisalanMetin { text: "FİRMA ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.fillWidth: true; Layout.horizontalStretchFactor: 2; Layout.preferredWidth: 0; Layout.minimumWidth: root.firmaSutunuEnAz }
                TarihBasligi { text: "TEKLİF TARİHİ" }
                TarihBasligi { text: "KABUL TARİHİ" }
                TarihBasligi { text: "PLANLANAN TESLİM"; visible: root.ikincilTarihSutunlariGoster }
                TarihBasligi { text: "TESLİM TARİHİ" }
                TarihBasligi { text: "ÜRETİM PDF"; visible: root.ikincilTarihSutunlariGoster }
                KisalanMetin { text: "PERSONEL"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunPersonel; Layout.maximumWidth: root.sutunPersonel }
                KisalanMetin { text: "TUTAR"; horizontalAlignment: Text.AlignRight; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunTutar; Layout.maximumWidth: root.sutunTutar }
                KisalanMetin { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunDurum; Layout.maximumWidth: root.sutunDurum }
                KisalanMetin { visible: root.aciklamaSutunuGoster; text: "AÇIKLAMALAR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.fillWidth: true; Layout.horizontalStretchFactor: 1; Layout.preferredWidth: 0 }
                KisalanMetin { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunIslemler; Layout.maximumWidth: root.sutunIslemler }
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

            // Bos liste / yukleniyor / baglanti hatasi gostergesi. Yukleme artik
            // asenkron oldugu icin liste sorgu suresince bos gorunur; kullanici
            // neyi bekledigini bilmeli. "parent: teklifListesi" ile gosterge
            // icerikle birlikte kaydirilmaz, gorunumun uzerine sabit serilir.
            ListeDurumu {
                parent: teklifListesi
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.kayitlarListesi.length
                aramaVar: root.aramaMetni.trim().length > 0
                bosMetin: "Gösterilecek teklif yok."
                aramaBosMetni: "Aramanıza uygun teklif bulunamadı."
            }

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
                // Satir yuksekligi + ListView spacing = 56 (4'un kati); bkz.
                // root.hizalanmisYukseklik yanindaki piksel hizalamasi notu.
                height: root.satirYuksekligi
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
                    anchors.leftMargin: root.sutunKenarBosluk
                    anchors.rightMargin: root.sutunKenarBosluk
                    spacing: root.sutunBosluk

                    RowLayout {
                        // fillWidth ACIKCA kapatilir: ic ice bir layout, icinde
                        // genisleyebilen bir oge oldugunda dis layout tarafindan da
                        // "genisleyebilir" kabul edilir ve preferredWidth'i asar.
                        Layout.fillWidth: false
                        Layout.preferredWidth: root.sutunTeklifNo
                        Layout.maximumWidth: root.sutunTeklifNo
                        Layout.fillHeight: true
                        spacing: 4

                        // Teklif No: kok numara + (revizyonsa) yanindaki "Rev.N"
                        // rozeti; birlikte PDF'teki "1203/Rev.2" ile ayni numarayi
                        // okutur. Sistemin ic kayit numarasi (teklifId) gosterilmez.
                        Text {
                            text: satir.modelData.kokTeklifNo
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillHeight: true
                        }

                        // Bu satir bir revizyonsa (RevizyonNo > 0) kucuk bir "Rev.{n}"
                        // rozeti gosterir; orijinal teklifler icin gizli.
                        Rectangle {
                            visible: satir.modelData.revizyonNo > 0
                            Layout.preferredWidth: revRozetMetni.implicitWidth + 8
                            Layout.preferredHeight: 16
                            radius: 4
                            color: Theme.panelVurgu
                            border.width: 1
                            border.color: Theme.kenarlikVurgu

                            Text {
                                id: revRozetMetni
                                anchors.centerIn: parent
                                text: "Rev." + satir.modelData.revizyonNo
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: 9
                                font.bold: true
                            }

                            ToolTip.visible: revRozetAlani.containsMouse
                            ToolTip.text: "Teklif No: " + satir.modelData.teklifNo
                            MouseArea {
                                id: revRozetAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        // Bu teklif baska bir teklifin KOPYASI olarak olusturulduysa
                        // kucuk bir "⧉" izi. Revizyon rozetinden (R1/R2) farkli:
                        // gecerlilikle ilgisi yoktur, iki teklif de bagimsiz ve
                        // gecerlidir -- yalnizca "bu icerik #X'ten geldi" bilgisidir.
                        // Kaynak teklif silinmis olabilir; id yine de gosterilir.
                        Text {
                            visible: satir.modelData.kopyaKaynakTeklifId > 0
                            text: "⧉"
                            color: Theme.metinCokSoluk
                            font.pixelSize: Theme.fontBoyutKucuk + 1
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillHeight: true

                            ToolTip.visible: kopyaIziAlani.containsMouse
                            ToolTip.delay: 300
                            ToolTip.text: "Teklif " + satir.modelData.kopyaKaynakTeklifNo + " kopyası"
                            MouseArea {
                                id: kopyaIziAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }
                        }

                        // Not varsa kucuk ikon: uzerine gelince not ipucunda
                        // gorunur, tiklaninca not penceresinde tam metin okunur.
                        Text {
                            visible: root.satirNotu(satir.modelData).length > 0
                            text: root.teklifNotuSekmesi ? "📝" : "🔧"
                            font.pixelSize: Theme.fontBoyutKucuk + 1
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillHeight: true

                            ToolTip.visible: notIkonuAlani.containsMouse
                            ToolTip.delay: 300
                            ToolTip.text: {
                                const not = root.satirNotu(satir.modelData)
                                return (root.teklifNotuSekmesi ? "Teklif notu: " : "Üretim notu: ")
                                       + (not.length > 300 ? not.substring(0, 300) + "…" : not)
                            }
                            MouseArea {
                                id: notIkonuAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.notuGoster(satir.modelData)
                            }
                        }

                        // Artan alani yutar; boylece teklif no + rozet sola yaslanir.
                        Item { Layout.fillWidth: true }
                    }
                    // Firma; arama bir urune uyduysa altinda o kalem ("etüv"
                    // aranınca bu firmaya hangi etüvün verildigi).
                    ColumnLayout {
                        // ONEMLI: Layout.preferredWidth: 0 olmadan RowLayout, metnin
                        // (kirpilmemis) dogal genisligini "tercih edilen" boyut sayiyor ve
                        // uzun firma adlarinda satiri kendi genisliginin otesine tasiyor --
                        // bu da sonraki sutunlarin (tarih/kullanici/durum) satirdan satira
                        // farkli miktarda saga kaymis gibi gorunmesine yol aciyordu.
                        // preferredWidth: 0 RowLayout'a bu ogeyi kalan alana KISALTMASINI
                        // soyler, boylece elide gercekten calisir ve sutunlar hizali kalir.
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.minimumWidth: root.firmaSutunuEnAz
                        Layout.horizontalStretchFactor: 2
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        KisalanMetin {
                            text: satir.modelData.firmaAdi
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.fillWidth: true
                        }
                        KisalanMetin {
                            visible: text.length > 0
                            text: {
                                const urun = satir.modelData.eslesenUrun || ""
                                if (urun.length === 0)
                                    return ""
                                const diger = (satir.modelData.eslesenSayi || 0) - 1
                                return satir.modelData.eslesenAdet + " × " + urun
                                       + (diger > 0 ? "  (+" + diger + " kalem)" : "")
                            }
                            color: Theme.vurguAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            Layout.fillWidth: true
                        }
                    }
                    // Teklif -> kabul -> planlanan teslim -> gercek teslim -> uretim PDF.
                    // Bos tarihler "—" ile gosterilir.
                    TarihHucresi { deger: satir.modelData.teklifTarihi }
                    TarihHucresi { deger: satir.modelData.kabulTarihi }
                    TarihHucresi { deger: satir.modelData.teslimatTarihi; visible: root.ikincilTarihSutunlariGoster }
                    TarihHucresi { deger: satir.modelData.teslimTarihi }
                    TarihHucresi { deger: satir.modelData.uretimPdfTarihi; visible: root.ikincilTarihSutunlariGoster }
                    KisalanMetin {
                        text: satir.modelData.personelKullaniciAdi
                        // Hucrede personelin kisa kullanici adi ("EÖ") yazar; tam
                        // adi ipucunda okunur, bu yuzden kirpilmasa da gosterilir.
                        ipucuMetni: (satir.modelData.personelAdSoyad || "").length > 0
                                    ? satir.modelData.personelAdSoyad
                                    : satir.modelData.personelKullaniciAdi
                        ipucuHepGoster: true
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: root.sutunPersonel
                        Layout.maximumWidth: root.sutunPersonel
                        Layout.fillHeight: true
                        clip: true
                    }
                    // Genel toplam (KDV dahil), teklifin kendi para biriminde.
                    KisalanMetin {
                        text: root.tutarMetni(satir.modelData.genelToplam, satir.modelData.paraBirimi)
                        color: satir.modelData.durum === "Revize Edildi" ? Theme.metinCokSoluk : Theme.metinBirincil
                        font.family: "Consolas"
                        font.pixelSize: Theme.fontBoyutKucuk + 1
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: root.sutunTutar
                        Layout.maximumWidth: root.sutunTutar
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                        elide: Text.ElideLeft
                    }

                    // DURUM rozeti, sutunun tamamini kaplayip metnini ortalamak yerine
                    // sabit genislikli bir slotun SOL kenarina yaslanir; boylece rozetin
                    // sol kenari "DURUM" basliginin sol kenariyla ayni hizada olur.
                    //
                    // Rozet ayni zamanda bir MENU ACICISIDIR: uzerine tiklaninca mevcut
                    // durum disindaki tum durumlar listelenir. Boylece "kabul edildi"
                    // dedigimiz bir teklif, musteri sonradan vazgecerse "Reddedildi"ye,
                    // kararsiz kalirsa "Beklemede"ye geri alinabilir -- Alınan/Biten
                    // sekmelerinde de. Menunun en altindaki "Durum Geçmişi" ise tum bu
                    // ileri-geri gecislerin kaydini gosterir.
                    Item {
                        Layout.preferredWidth: root.sutunDurum
                        Layout.maximumWidth: root.sutunDurum
                        Layout.fillHeight: true

                        Rectangle {
                            id: durumRozeti
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            // Rozetin olculeri sabit degil, ICERIKTEN turetilir: metnin
                            // genisligi/yuksekligi font ve DPI ile degistiginden sabit
                            // 24px yukseklik "Tamamlandı"/"Kabul Edildi" gibi uzun ve
                            // alt uzantili (ı, ğ, ç) metinleri kirpiyordu.
                            width: Math.min(root.sutunDurum, Math.ceil(rozetIcerik.implicitWidth) + 24)
                            height: root.hizalanmisYukseklik(Math.max(28, durumMetni.implicitHeight + 10))
                            radius: 5
                            color: {
                                const d = satir.modelData.durum
                                if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basariZemin
                                if (d === "Beklemede") return Theme.vurguZeminSoluk
                                if (d === "Reddedildi") return Theme.tehlikeZemin
                                if (d === "Revize Edildi") return Theme.uyariZemin
                                return Theme.panel
                            }
                            border.width: 1
                            border.color: {
                                const d = satir.modelData.durum
                                if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basari
                                if (d === "Beklemede") return Theme.vurgu
                                if (d === "Reddedildi") return Theme.tehlike
                                if (d === "Revize Edildi") return Theme.uyari
                                return Theme.kenarlik
                            }

                            readonly property color durumRengi: {
                                const d = satir.modelData.durum
                                if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basariAcik
                                if (d === "Beklemede") return Theme.vurguAcik
                                if (d === "Reddedildi") return Theme.tehlikeAcik
                                if (d === "Revize Edildi") return Theme.uyariAcik
                                return Theme.metinIkincil
                            }

                            Row {
                                id: rozetIcerik
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    id: durumMetni
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: satir.modelData.durum
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    color: durumRozeti.durumRengi
                                }

                                // Rozetin tiklanabilir bir menu oldugunu belli eden isaret.
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "▾"
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 9
                                    color: durumRozeti.durumRengi
                                    opacity: 0.7
                                }
                            }

                            ToolTip.visible: durumAlani.containsMouse && ToolTip.text.length > 0
                            ToolTip.delay: 300
                            ToolTip.text: {
                                const d = satir.modelData.durum
                                if (d === "Reddedildi" && satir.modelData.redSebebi.length > 0)
                                    return "Red sebebi: " + satir.modelData.redSebebi
                                // Revize edilmis teklif artik gecerli degildir; yerine gecen
                                // (zincirin en son) teklifin numarasi C++ tarafindan gelir.
                                if (root.revizeEdilmisMi(satir.modelData))
                                    return "Güncel teklif: " + satir.modelData.guncelTeklifNo
                                return ""
                            }
                            MouseArea {
                                id: durumAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: durumMenusu.popup()
                            }

                            // Mevcut durum DISINDAKI tum durumlar + gecmis kaydi.
                            // Instantiator, Menu'nun icerigini bir model'den uretmenin
                            // desteklenen yoludur (Repeater dogrudan MenuItem uretmez).
                            Menu {
                                id: durumMenusu

                                background: Rectangle {
                                    implicitWidth: 180
                                    color: Theme.panel
                                    radius: Theme.radiusKucuk
                                    border.width: 1
                                    border.color: Theme.kenarlik
                                }

                                // Revize edilmis (gecersiz) teklifte durum secenegi yoktur;
                                // menu yalnizca sebebi ve "Durum Geçmişi..."ni gosterir.
                                MenuItem {
                                    id: revizeBilgisi
                                    visible: root.revizeEdilmisMi(satir.modelData)
                                    height: revizeBilgisi.visible ? revizeBilgisiMetni.implicitHeight + 12 : 0
                                    enabled: false
                                    background: Rectangle { color: "transparent" }
                                    contentItem: Text {
                                        id: revizeBilgisiMetni
                                        text: "Güncel teklif: " + satir.modelData.guncelTeklifNo
                                        color: Theme.uyariAcik
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk
                                        wrapMode: Text.WordWrap
                                        leftPadding: 8
                                        rightPadding: 8
                                    }
                                }

                                Instantiator {
                                    model: root.durumMenusuSecenekleri(satir.modelData)
                                    onObjectAdded: (index, object) => durumMenusu.insertItem(index, object)
                                    onObjectRemoved: (index, object) => durumMenusu.removeItem(object)

                                    delegate: MenuItem {
                                        id: durumSecenegi
                                        required property string modelData
                                        text: durumSecenegi.modelData + " yap"
                                        height: 32
                                        onTriggered: root.durumDegistirmeyiBaslat(
                                            satir.modelData.teklifId, satir.modelData.durum, durumSecenegi.modelData)
                                        background: Rectangle {
                                            color: durumSecenegi.highlighted ? Theme.panelHover : "transparent"
                                        }
                                        contentItem: Text {
                                            text: durumSecenegi.text
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 8
                                        }
                                    }
                                }

                                MenuSeparator {
                                    contentItem: Rectangle { implicitHeight: 1; color: Theme.kenarlik }
                                }

                                MenuItem {
                                    id: gecmisMenuOgesi
                                    text: "Teklif Geçmişi..."
                                    height: 32
                                    onTriggered: root.durumGecmisiniAc(satir.modelData.teklifId)
                                    background: Rectangle {
                                        color: gecmisMenuOgesi.highlighted ? Theme.panelHover : "transparent"
                                    }
                                    contentItem: Text {
                                        text: gecmisMenuOgesi.text
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 8
                                    }
                                }
                            }
                        }
                    }

                    // Aciklamalar (sevk aciklamasi). Tam metin tooltip'te.
                    KisalanMetin {
                        visible: root.aciklamaSutunuGoster
                        text: root.aciklamaMetni(satir.modelData)
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk + 1
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: 1
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        // fillWidth ACIKCA kapatilir. Daha once bu satirda yoktu ve
                        // asagidaki butonlarin bulundugu layout kendini "genisleyebilir"
                        // ilan edip 336px'i asiyordu; bu da FİRMA ADI sutununu ezip
                        // tum veri sutunlarinin baslik sutunlariyla kaymasina yol
                        // aciyordu (baslik satirinda boyle bir esneme yok).
                        Layout.fillWidth: false
                        Layout.preferredWidth: root.sutunIslemler
                        Layout.maximumWidth: root.sutunIslemler
                        Layout.fillHeight: true
                        spacing: 6

                        // Teklifin kaydedildigi andaki TUM verisiyle Teklif Ver ekranini
                        // (birebir ayni ekran) doldurup acar. "Giden Tekliflerim"de
                        // kullanici degisiklik yapip kaydederse bu YENI bir revizyon
                        // olarak eklenir, orijinal teklif degismez. Alınan/Biten
                        // Tekliflerim'de revize yapilamadigi icin "Teklifi Kaydet"
                        // butonu gizlidir; detay salt goruntulemedir.
                        // Bkz. SatisModuluPage.qml (detayIstendi baglantisi).
                        Button {
                            id: detayButonu
                            text: "Detay"
                            // Rozette oldugu gibi buton olculeri de metinden turetilir:
                            // sabit 58x28 slot, font/DPI degisince "Detay" metnini
                            // kenarlardan kirpiyordu.
                            // Genislikler de tam sayiya yuvarlanir: ondalik bir genislik,
                            // yanindaki butonlarin x konumunu da yarim piksele kaydirip
                            // dikey kenarliklari ayni sekilde yok edebiliyor.
                            Layout.preferredWidth: Math.max(58, Math.ceil(detayMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, detayMetni.implicitHeight + 10))
                            onClicked: root.detayIstendi(satir.modelData.teklifId)
                            background: Rectangle {
                                radius: 5
                                color: detayButonu.hovered ? Theme.panelHover : "transparent"
                                border.color: Theme.kenarlikVurgu
                                border.width: 1
                            }
                            contentItem: Text {
                                id: detayMetni
                                text: "Detay"
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Teklifin icerigini yeni bir teklif formuna kopyalar. Kaynak
                        // teklife HICBIR SEY yapmaz (durumu degismez, revizyon
                        // olusmaz) -- bu yuzden Giden Tekliflerim'deki kilitli/revize
                        // edilmis tekliflerde de gosterilir. Ayni veya cok benzer
                        // teklifin farkli firmalara verilmesi icindir; bu yuzden
                        // yalnizca Giden Tekliflerim'de durur (bkz. kopyaButonuGoster).
                        // Bkz. SatisModuluPage.qml (kopyaIstendi).
                        Button {
                            id: kopyaButonu
                            visible: root.kopyaButonuGoster
                            text: "Kopya"
                            Layout.preferredWidth: Math.max(56, Math.ceil(kopyaMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, kopyaMetni.implicitHeight + 10))
                            onClicked: root.kopyaIstendi(satir.modelData.teklifId)
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                            ToolTip.text: "Yeni teklif olarak kopyala"
                            background: Rectangle {
                                radius: 5
                                color: kopyaButonu.hovered ? Theme.panelHover : "transparent"
                                border.color: Theme.kenarlik
                                border.width: 1
                            }
                            contentItem: Text {
                                id: kopyaMetni
                                text: "Kopya"
                                color: Theme.metinIkincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // NOT: Burada eskiden duruma gore degisen "Kabul Et / Reddet /
                        // Tamamlandı" butonlari vardi. Artik her gecis (ileri VE geri)
                        // DURUM sutunundaki rozet menusunden yapildigi icin bu butonlar
                        // ayni isi ikinci kez yapiyordu; kaldirildilar. Satirda kalan
                        // islemler yalnizca Detay / PDF / Sil.
                        Item { Layout.fillWidth: true }

                        Button {
                            id: pdfButonu
                            text: "PDF"
                            Layout.preferredWidth: Math.max(50, Math.ceil(pdfMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, pdfMetni.implicitHeight + 10))
                            onClicked: root.pdfOlusturVeAc(satir.modelData.teklifId)
                            background: Rectangle {
                                radius: 5
                                color: pdfButonu.hovered ? Theme.panelHover : "transparent"
                                border.color: Theme.kenarlik
                                border.width: 1
                            }
                            contentItem: Text {
                                id: pdfMetni
                                text: "PDF"
                                color: Theme.metinIkincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Teknik ekip icin fiyatsiz uretim PDF'i (Alınan/Biten Tekliflerim).
                        Button {
                            id: uretimButonu
                            visible: root.uretimButonuGoster
                            text: "Üretim"
                            Layout.preferredWidth: Math.max(64, Math.ceil(uretimMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, uretimMetni.implicitHeight + 10))
                            onClicked: root.uretimPdfOlusturVeAc(satir.modelData.teklifId)
                            ToolTip.visible: hovered
                            ToolTip.delay: 500
                            ToolTip.text: satir.modelData.uretimPdfTarihi.length > 0
                                          ? "Üretim PDF'i (son: " + satir.modelData.uretimPdfTarihi + ")"
                                          : "Üretim PDF'i"
                            background: Rectangle {
                                radius: 5
                                color: uretimButonu.hovered ? Theme.panelHover : "transparent"
                                border.color: Theme.basari
                                border.width: 1
                            }
                            contentItem: Text {
                                id: uretimMetni
                                text: "Üretim"
                                color: Theme.basariAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Sevk ve irsaliye bilgileri penceresi (Alınan/Biten Tekliflerim).
                        // Satis + buro personelinin ortak doldurdugu fatura/irsaliye
                        // basligi, vergi bilgileri ve siparis sartlari buradan girilir
                        // ve buradan okunur.
                        // Rengi fatura durumunu gosterir (bkz. faturaDurumu, AramaSorgulari):
                        // eksik -> turuncu dolu (unutulmasin), hazir -> sade,
                        // faturalandi -> yesil.
                        Button {
                            id: irsaliyeButonu
                            readonly property string faturaDurumu: satir.modelData.faturaDurumu || "eksik"
                            visible: root.irsaliyeButonuGoster
                            text: "İrsaliye"
                            Layout.preferredWidth: Math.max(70, Math.ceil(irsaliyeMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, irsaliyeMetni.implicitHeight + 10))
                            onClicked: root.irsaliyeAc(satir.modelData)
                            ToolTip.visible: hovered
                            ToolTip.delay: 300
                            ToolTip.text: faturaDurumu === "faturalandi"
                                          ? "Faturalandı: " + satir.modelData.faturaNo
                                            + (satir.modelData.irsaliyeNo ? "  ·  İrsaliye: " + satir.modelData.irsaliyeNo : "")
                                          : faturaDurumu === "hazir" ? "Faturaya hazır"
                                          : "İrsaliye bilgileri eksik"
                            background: Rectangle {
                                radius: 5
                                color: irsaliyeButonu.faturaDurumu === "eksik"
                                       ? (irsaliyeButonu.hovered ? Theme.uyariZeminHover : Theme.uyariZemin)
                                       : (irsaliyeButonu.hovered ? Theme.panelHover : "transparent")
                                border.color: irsaliyeButonu.faturaDurumu === "faturalandi" ? Theme.basari
                                            : irsaliyeButonu.faturaDurumu === "hazir" ? Theme.kenarlik : Theme.uyari
                                border.width: 1
                            }
                            contentItem: Text {
                                id: irsaliyeMetni
                                // Metin sabit: islemler sutunu butonun genisligine gore olculu.
                                text: "İrsaliye"
                                color: irsaliyeButonu.faturaDurumu === "faturalandi" ? Theme.basariAcik
                                     : irsaliyeButonu.faturaDurumu === "hazir" ? Theme.metinIkincil : Theme.uyariAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Kabul edilmis / tamamlanmis teklifte gizli: kilitli teklif silinemez.
                        Button {
                            id: silButonu
                            visible: root.duzenleyebilir && !root.teklifKilitliMi(satir.modelData.durum)
                            text: "Sil"
                            Layout.preferredWidth: Math.max(50, Math.ceil(silMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, silMetni.implicitHeight + 10))
                            onClicked: {
                                const id = satir.modelData.teklifId
                                sifreDialogu.iste("Teklifi Sil", "Teklif " + satir.modelData.teklifNo + " kalıcı olarak silinsin mi?",
                                                  "Sil", true, function() { root.teklifiSil(id) })
                            }
                            background: Rectangle {
                                radius: 5
                                color: silButonu.hovered ? Theme.tehlikeZeminHover : "transparent"
                                border.color: silButonu.hovered ? Theme.tehlikeHover : Theme.kenarlik
                                border.width: 1
                            }
                            contentItem: Text {
                                id: silMetni
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
                enabled: root.sayfaSonucu.mevcutSayfa > 1 && !root.yukleniyor
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
                enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa && !root.yukleniyor
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

    // Satirdaki not ikonuna tiklaninca notun tam metnini salt okunur gosterir.
    // Not duzenleme "Detay" ekranindaki not butonlarindan yapilir.
    NotDuzenleDialog {
        id: notGoruntuleDialogu
        saltOkunur: true
        renk: root.teklifNotuSekmesi ? Theme.vurgu : Theme.basari
        bilgi: root.teklifNotuSekmesi ? "İç not, PDF'e basılmaz." : "Üretim PDF'ine basılır."
    }

    // "İrsaliye" butonunun actigi sevk/irsaliye formu. Pencere kendisi kaydetmez;
    // "Kaydet"e basilinca alanlari sinyalle geri verir (bkz. irsaliyeAc).
    SevkBilgileriDialog {
        id: sevkDialogu
        onKaydedildi: (sevk) => root.sevkBilgileriniKaydet(sevkDialogu.teklifId, sevk)
    }

    // Silme yonetici sifresiyle onaylanir (WPF'teki gibi).
    SifreOnayDialog { id: sifreDialogu }

    function teklifiSil(teklifId) {
        const no = root.teklifNo(teklifId)
        if (!database.teklifSil(teklifId)) {
            // Sebep C++ tarafindan gelir (ör. "önce revizyonlar silinmeli").
            const sebep = database.sonHataMesaji()
            root.pdfMesaji = sebep && sebep.length > 0 ? sebep : "Teklif " + no + " silinemedi."
            root.pdfMesajiHata = true
        }
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
    }

    // Durum degisikligi onayi. "Reddedildi" disindaki her gecis buradan gecer.
    TemaDialog {
        id: durumOnayDialogu
        property int hedefTeklifId: -1
        property string eskiDurum: ""
        property string yeniDurum: ""
        property string teslimatTarihi: ""
        readonly property bool kabul: yeniDurum === "Kabul Edildi"
        baslik: "Durumu Değiştir"
        onayMetni: "Değiştir"
        onayEtkin: !kabul || teslimatTarihi.length > 0
        width: 400

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "Teklif " + root.teklifNo(durumOnayDialogu.hedefTeklifId) + ": "
                      + durumOnayDialogu.eskiDurum + " → " + durumOnayDialogu.yeniDurum
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                wrapMode: Text.WordWrap
            }

            TarihSecici {
                Layout.fillWidth: true
                visible: durumOnayDialogu.kabul
                etiket: "PLANLANAN TESLİM TARİHİ *"
                gecmisKapali: true
                deger: durumOnayDialogu.teslimatTarihi
                onSecildi: (tarih) => durumOnayDialogu.teslimatTarihi = tarih
            }

            // Irsaliye bilgileri sonradan unutuluyordu; kabulle birlikte pencere acilir.
            TemaOnayKutusu {
                id: irsaliyeyiAcKutusu
                visible: durumOnayDialogu.kabul
                text: "İrsaliye bilgilerini şimdi doldur"
                checked: true
            }
        }

        onAccepted: {
            if (durumOnayDialogu.kabul
                    && !database.teklifTeslimatTarihiGuncelle(durumOnayDialogu.hedefTeklifId,
                                                              durumOnayDialogu.teslimatTarihi)) {
                const sebep = database.sonHataMesaji()
                root.pdfMesaji = sebep && sebep.length > 0
                                 ? sebep : "Planlanan teslim tarihi kaydedilemedi."
                root.pdfMesajiHata = true
                durumOnayDialogu.hedefTeklifId = -1
                return
            }
            const id = durumOnayDialogu.hedefTeklifId
            const kayit = root.kayitlarListesi.find(k => k.teklifId === id)
            if (root.durumUygula(id, durumOnayDialogu.yeniDurum, "")
                    && durumOnayDialogu.kabul && irsaliyeyiAcKutusu.checked) {
                root.irsaliyeAc({ teklifId: id, teklifNo: root.teklifNo(id),
                                  firmaAdi: kayit ? kayit.firmaAdi : "", durum: "Kabul Edildi" })
            }
            durumOnayDialogu.hedefTeklifId = -1
        }
        onRejected: durumOnayDialogu.hedefTeklifId = -1
    }

    // Teklifin REVIZYON ZINCIRININ tamaminin gecmisi (olusturma, revizyonlar,
    // durum degisimleri, duzeltmeler), eskiden yeniye tek zaman cizelgesi.
    // Hangi surumden acilirsa acilsin ayni akis gorunur; o surumun satirlari
    // vurgulanir.
    TemaDialog {
        id: gecmisDialogu
        property int hedefTeklifId: -1
        property var kayitlar: []
        // Zincirin ilk satiri kok teklifin olusturulmasidir.
        baslik: "Teklif " + (gecmisDialogu.kayitlar.length > 0 && gecmisDialogu.kayitlar[0].teklifNo
                             ? gecmisDialogu.kayitlar[0].teklifNo
                             : root.teklifNo(gecmisDialogu.hedefTeklifId)) + " — Teklif Geçmişi"
        onayGorunur: false
        iptalMetni: "Kapat"
        width: 620

        function renk(tur) {
            if (tur === "duzeltme") return Theme.uyariAcik
            if (tur === "revizyon" || tur === "olusturma") return Theme.vurgu
            return Theme.metinBirincil
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label {
                Layout.fillWidth: true
                visible: gecmisDialogu.kayitlar.length > 0
                text: "Tüm revizyonlar dahil, eskiden yeniye. Açtığınız sürümün (Teklif "
                      + root.teklifNo(gecmisDialogu.hedefTeklifId) + ") satırları vurgulu."
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }

            Label {
                visible: gecmisDialogu.kayitlar.length === 0
                Layout.fillWidth: true
                text: "Kayıtlı geçmiş yok."
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }

            ListView {
                id: gecmisListesi
                visible: gecmisDialogu.kayitlar.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(440, contentHeight)
                clip: true
                spacing: 4
                model: gecmisDialogu.kayitlar
                ScrollBar.vertical: ScrollBar { policy: gecmisListesi.contentHeight > gecmisListesi.height
                                                        ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: gecmisSatiri
                    required property var modelData
                    readonly property bool buSurum: gecmisSatiri.modelData.teklifId === gecmisDialogu.hedefTeklifId
                    width: ListView.view.width - 10
                    height: satirIcerigi.implicitHeight + 16
                    radius: Theme.radiusKucuk
                    color: Theme.arkaplan
                    border.width: 1
                    border.color: gecmisSatiri.buSurum ? Theme.kenarlikVurgu : Theme.kenarlik

                    RowLayout {
                        id: satirIcerigi
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 10

                        // Olayin ait oldugu surum
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 76
                            Layout.preferredHeight: 22
                            radius: Theme.radiusKucuk
                            color: "transparent"
                            border.width: 1
                            border.color: gecmisSatiri.buSurum ? Theme.kenarlikVurgu : Theme.kenarlik
                            Text {
                                anchors.centerIn: parent
                                text: gecmisSatiri.modelData.teklifNo
                                color: gecmisSatiri.buSurum ? Theme.metinBirincil : Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                font.bold: gecmisSatiri.buSurum
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: (gecmisSatiri.modelData.tur === "duzeltme" ? "✎  " : "")
                                      + gecmisSatiri.modelData.baslik
                                color: gecmisDialogu.renk(gecmisSatiri.modelData.tur)
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: gecmisSatiri.modelData.tarih
                                      + (gecmisSatiri.modelData.personel.length > 0 ? "  •  " + gecmisSatiri.modelData.personel : "")
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: gecmisSatiri.modelData.aciklama.length > 0
                                text: gecmisSatiri.modelData.aciklama
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    // Red sebebi (istege bagli) girisi; durum menusunden "Reddedildi" secilince acilir.
    TemaDialog {
        id: reddetDialogu
        property int hedefTeklifId: -1
        property string eskiDurum: ""
        baslik: "Teklif " + root.teklifNo(reddetDialogu.hedefTeklifId) + " — Reddet"
        onayMetni: "Reddet"
        tehlikeli: true
        width: 420

        onAccepted: {
            root.durumUygula(reddetDialogu.hedefTeklifId, "Reddedildi", redSebebiGirisi.text)
            reddetDialogu.hedefTeklifId = -1
        }
        onRejected: reddetDialogu.hedefTeklifId = -1

        contentItem: ColumnLayout {
            spacing: 6
            Label {
                text: "RED SEBEBİ"
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            TextArea {
                id: redSebebiGirisi
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                wrapMode: TextArea.Wrap
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                placeholderTextColor: Theme.metinCokSoluk
                placeholderText: "İsteğe bağlı (en fazla 500 karakter)"
                // Veritabanindaki RedSebebi sutunu 500 karakter.
                onTextChanged: if (length > 500) remove(500, length)
                background: Rectangle {
                    color: Theme.arkaplan
                    radius: Theme.radiusKucuk
                    border.width: 1
                    border.color: redSebebiGirisi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                }
            }
        }
    }
}