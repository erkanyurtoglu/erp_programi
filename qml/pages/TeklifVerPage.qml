import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Teklif Ver ekrani: WPF'teki TeklifVerViewModel + TeklifVer.xaml ikilisinin
// Qt/QML karsiligi. Musteri secimi, urun sepeti, indirim/KDV/paketleme/tasima
// hesabi ve teklifKaydet() ile kaydetme burada. PDF uretimi ve dinamik doviz
// kuru cekme bu ilk surumde STUB -- kur alanlari elle girilir, PDF butonu
// simdilik sadece "yakinda" mesaji gosterir (WPF'teki KaydetVePdfIndirCommand'in
// PDF kismi bir sonraki adimda eklenecek).
Item {
    id: root

    property int kullaniciId: 0

    // Revizyon modunda (bkz. duzenlemeyeBasla) ust soldaki geri butonunda
    // gosterilen kaynak liste adi: "Giden Tekliflerim" vb.
    property string geriDonusEtiketi: "Giden Tekliflerim"

    // Detay ekraninda acik teklifin durumu (yeni teklifte bos).
    property string teklifDurumu: ""

    // Kabul edilmis / tamamlanmis bir teklif KILITLIDIR: musteri, sepet, ticari
    // sartlar, teslimat, dil/para birimi, teklif notu ve sozlesme metni
    // degistirilemez, revize edilemez (bkz. Database::teklifKilitliMi -- ayni kural
    // C++ tarafinda da uygulanir). Normal "Teklif Ver" ekraninda hep false.
    readonly property bool teklifKilitli: root.duzenlenenKaynakTeklifId > 0
                                          && (root.teklifDurumu === "Kabul Edildi" || root.teklifDurumu === "Tamamlandı")

    // Planlanan teslim tarihi ve uretim notu uretim planlamasidir; kabulden sonra
    // da yazilabilir, yalnizca tamamlanmis teklifte kilitlenir.
    readonly property bool uretimBilgisiKilitli: root.teklifDurumu === "Tamamlandı"

    // Giden Tekliflerim'den acilan detayda (bkz. SatisModuluPage) kilitli teklif de
    // REVIZE edilebilir: form duzenlenir, "Teklifi Kaydet" orijinale dokunmadan yeni
    // bir revizyon olusturur. Kilitli teklifin KENDISINE yerinde yazma (teklif notu,
    // sozlesme; tamamlanmissa teslim tarihi/uretim notu) yine yapilmaz -- bu
    // degisiklikler yalnizca kaydedilecek revizyona gider.
    property bool revizyonIzinli: false

    // Ekrandaki alanlarin salt okunur olup olmadigi.
    readonly property bool formKilitli: root.teklifKilitli && !root.revizyonIzinli

    // Kilitli teklifin detayi (Alınan/Biten Tekliflerim) salt goruntulemedir:
    // sepete urun eklenemeyecegi icin soldaki "Ürün Ara" paneli hic gosterilmez,
    // sepet tum genisligi kullanir. Revize moduna gecilirse panel geri gelir.
    readonly property bool urunAramaGorunur: !root.formKilitli

    // Urun arama sorgusu: panel gizliyken bosuna SQL Server'a gidilmesin.
    function urunAramaTazele() {
        if (!root.urunAramaGorunur)
            return
        database.urunAraBaslat(urunAramaKutusu.text, 40, dilCombo.currentText)
    }
    readonly property bool uretimAlaniKilitli: root.uretimBilgisiKilitli && !root.revizyonIzinli

    // Revizyon modunda geri butonuna basilinca; SatisModuluPage bunu dinleyip
    // gelinen listeye geri doner.
    signal geriDonuldu()

    // Revizyon basariyla kaydedilince yayinlanir; SatisModuluPage listeye donup
    // tazeler ve kullaniciya sonucu gosterir. revizeEdilenIdler: bu revizyon
    // yuzunden "Revize Edildi" durumuna alinan ESKI tekliflerin id listesi
    // (kilitli teklifler isaretlenmedigi icin bos da olabilir).
    signal revizyonKaydedildi(int yeniTeklifId, int kaynakTeklifId, var revizeEdilenIdler)

    // Kopya basariyla kaydedilince yayinlanir (bkz. kopyalamayaBasla). Revizyondan
    // ayri bir sinyal: kaynak teklifte hicbir degisiklik olmadigi icin gosterilecek
    // mesaj da farklidir ("#X gecersizlesti" gibi bir bilgi YOKTUR).
    signal kopyaKaydedildi(int yeniTeklifId, int kaynakTeklifId)

    // Kucuk yardimci bilesenler: dosya icinde birden fazla yerde kullanildigi
    // icin inline "component" olarak (dosyanin en ustunde, root'un dogrudan
    // cocugu olarak) tanimlaniyor -- QML'de inline component'ler boyle, tek
    // seviyeli olarak tanimlanmalidir.
    // Manuel urun ekleme dialogundaki alan stili (bkz. UrunlerimPage.qml'deki
    // ayni amacli FormAlani bileseni).
    component ManuelUrunAlani: TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.girdiYuksekligi + 6
        color: Theme.metinBirincil
        placeholderTextColor: Theme.metinCokSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutNormal
        leftPadding: 12
        rightPadding: 12
        background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
    }

    component UcretAlani: Rectangle {
        id: ucretAlani
        property string birim: "%"
        // Kutunun sayisal degeri -- metin artik "15.200,50" gibi bicimli oldugu
        // icin disaridan okurken/yazarken hep bu ikisi kullanilir.
        readonly property real deger: ucretBicimi.deger
        property real baslangicDegeri: 0
        function ayarla(sayi) { ucretBicimi.ayarla(sayi) }

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.girdiYuksekligi
        radius: Theme.radiusKucuk
        color: Theme.arkaplan
        border.width: 1
        border.color: girdi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 2
            TextField {
                id: girdi
                Layout.fillWidth: true
                leftPadding: 0
                rightPadding: 0
                background: null
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                verticalAlignment: TextInput.AlignVCenter
                // Binlik ayraci/ondalik virgul yonetimi (validator dahil) buna ait.
                SayiBicimlendirici { id: ucretBicimi; ondalik: 2 }
            }
            Label { text: parent.parent.birim; color: Theme.metinSoluk; font.pixelSize: Theme.fontBoyutKucuk }
        }

        Component.onCompleted: ucretBicimi.ayarla(ucretAlani.baslangicDegeri)
    }

    // Sepet satirlarindaki elle degistirilebilir Maliyet/Birim Fiyat hucreleri
    // icin kompakt sayisal girdi kutusu.
    component SepetSayiAlani: Rectangle {
        id: sepetSayiAlani
        // Gosterilecek deger. Metin kutusuna BINDING ile degil, degistikce
        // sayiBicimi.ayarla() ile yazilir -- canli bicimlendirme metne elle
        // atama yaptigi icin binding ilk duzenlemede kopardi.
        property real deger: 0
        property int ondalik: 2
        signal degisti(real yeniDeger)

        onDegerChanged: if (!sayiGirdisi.activeFocus) sayiBicimi.ayarla(deger)
        Component.onCompleted: sayiBicimi.ayarla(deger)
        Layout.preferredWidth: 80
        Layout.preferredHeight: 30
        radius: Theme.radiusKucuk
        color: Theme.arkaplan
        border.width: 1
        border.color: sayiGirdisi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

        // Basic stilin varsayilan ic boslugu (~10px) dar kutuda metin alanini
        // yarisina dusuruyordu; bosluk sadece anchor margin'lerle veriliyor.
        // Metin soldan baslar ve odak disindayken imlec basa alinir -- aksi
        // halde sigmayan degerin sadece SONU gorunuyordu ("100000.00" -> "0000.00").
        TextField {
            id: sayiGirdisi
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            leftPadding: 0
            rightPadding: 0
            background: null
            color: Theme.metinBirincil
            font.family: "Consolas"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            onEditingFinished: sepetSayiAlani.degisti(sayiBicimi.deger)

            SayiBicimlendirici { id: sayiBicimi; ondalik: sepetSayiAlani.ondalik }
        }
    }

    // Baslik satirindaki "Teklif Notu" / "Üretim Notu" butonu. Not doluysa kenarlik
    // notun renginde olur ve sagda kucuk bir nokta yanar; boylece pencereyi acmadan
    // not olup olmadigi anlasilir. Uzerine gelince notun kendisi (bossa ne ise
    // yaradigi) ipucunda gorunur.
    component NotButonu: Button {
        id: notButonu
        property string ikon: ""
        property string etiket: ""
        property string notMetni: ""
        property string ipucu: ""
        property color renk: Theme.vurgu
        readonly property bool dolu: notMetni.trim().length > 0

        Layout.preferredHeight: 38
        leftPadding: 12
        rightPadding: 12
        ToolTip.visible: hovered
        ToolTip.delay: 400
        ToolTip.text: dolu
            ? (notMetni.length > 300 ? notMetni.substring(0, 300) + "…" : notMetni)
            : ipucu

        background: Rectangle {
            radius: Theme.radiusKucuk
            color: notButonu.hovered ? Theme.panelHover : Theme.panel
            border.width: 1
            border.color: notButonu.dolu || notButonu.hovered ? notButonu.renk : Theme.kenarlik
        }
        contentItem: RowLayout {
            spacing: 6
            Text {
                text: notButonu.ikon
                font.pixelSize: Theme.fontBoyutNormal
            }
            Text {
                text: notButonu.etiket
                color: notButonu.dolu ? Theme.metinBirincil : Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                font.bold: notButonu.dolu
            }
            Rectangle {
                visible: notButonu.dolu
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: notButonu.renk
            }
        }
    }

    component Ozet: ColumnLayout {
        property string baslik: ""
        property string deger: ""
        property color renk: Theme.metinBirincil
        spacing: 2
        Label { text: parent.baslik; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
        Label { text: parent.deger; color: parent.renk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutOrta; font.bold: true }
    }

    // Kart baslik + ince ayirici cizgi: sol "Teklif Bilgileri" seridindeki
    // mantiksal gruplari (musteri, ticari sartlar, teslimat, dil/para birimi)
    // birbirinden gorsel olarak ayirmak icin kullanilir. Vurgu renginde kucuk
    // bir "bayrak" isaretiyle grubun kimligini one cikarir.
    component BolumBasligi: ColumnLayout {
        property string baslik: ""
        spacing: 10
        Layout.fillWidth: true

        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Rectangle {
                width: 4
                height: 14
                radius: 2
                color: Theme.vurgu
            }
            Label {
                text: parent.parent.baslik
                color: Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.kenarlik
        }
    }

    // --- Musteri secimi ---
    property int secilenMusteriId: 0
    property string secilenFirmaAdi: ""

    // --- Sepet ---
    property var sepet: []

    // --- Detay -> Revize Et akisi (Giden/Alınan/Biten Tekliflerim'deki "Detay"
    // butonu) ---
    // duzenlenenAnaTeklifId > 0 iken "Teklifi Kaydet", teklifKaydet()'e bu
    // degeri anaTeklifId olarak gonderir -- boylece yeni kayit bir REVIZYON
    // olur, orijinal teklif degismez/silinmez. Varsayilan (0) durumda bu
    // ekranin normal "yeni teklif" davranisi HICBIR SEKILDE degismez.
    property int duzenlenenAnaTeklifId: 0
    property int duzenlenenKaynakTeklifId: 0

    // --- Kopyala akisi (Giden/Alınan/Biten Tekliflerim'deki "Kopya" butonu) ---
    // Satis personeli ayni icerikli teklifi farkli firmalara verebiliyor. Kopya,
    // REVIZYON DEGILDIR: kaynak teklife hic dokunulmaz (durumu degismez, "Revize
    // Edildi" olmaz), yeni kayit bastan bagimsiz bir teklif olur -- iki teklif ayni
    // anda gecerli olabilir. Bu yuzden kopya modunda duzenlenenAnaTeklifId ve
    // duzenlenenKaynakTeklifId 0'DIR (yani ekran "yeni teklif" gibi davranir,
    // kaynaga yerinde yazma yapan hicbir yol tetiklenmez); tek fark, kaydedilirken
    // teklifKaydet()'e izlenebilirlik icin gonderilen bu id.
    property int kopyaKaynakTeklifId: 0
    readonly property bool kopyaModu: root.kopyaKaynakTeklifId > 0

    // Ekran, sol menude maddesi olmayan bir ALT SAYFA olarak mi acildi? (Detay ya
    // da Kopya akisi.) Geri butonu ve baslik buna gore gorunur.
    readonly property bool altSayfaModu: root.duzenlenenAnaTeklifId > 0 || root.kopyaModu

    // --- Satis sozlesmesi metni ("Satış Sözleşmesi" butonu/penceresi) ---
    // Teklif PDF'inin son sayfasindaki maddeler. BOS ise "kullanici degistirmedi"
    // demektir: kaydedilirken SatisSozlesmesiMetni NULL kalir ve PDF, dilin
    // varsayilan metnini kullanir (bkz. TeklifPdfOlusturucu). Kullanici pencerede
    // kaydederse buraya yazilir ve teklifle birlikte saklanir.
    property string sozlesmeMetni: ""

    // --- Planlanan teslim tarihi, teklif notu ve uretim notu ---
    // teslimatTarihi "yyyy-MM-dd" (TarihTakvimi ciktisi) veya bos. Veritabaninda
    // TeslimatTarihi sutununa yazilir; GERCEK teslim tarihi (TeslimTarihi) ise
    // teklif "Tamamlandı" yapilinca otomatik dolar.
    //
    // Iki ayri not vardir:
    //   Teklif notu (MusteriNotu): buro/satis personelinin ic notu; teklif PDF'ine
    //                              de uretim PDF'ine de BASILMAZ. Kabul edilince kilitlenir.
    //   Uretim notu (UretimNotu):  uretim personeli icindir; uretim PDF'ine basilir.
    //
    // Notlar ekranda yer kaplamasin diye baslik satirindaki "Teklif Notu" /
    // "Üretim Notu" butonlariyla acilan pencerede (NotDuzenleDialog) yazilir.
    // Yeni teklifte not ekranda bekler ve "Teklifi Kaydet" ile kaydedilir. Kayitli
    // bir teklif acikken (Detay) pencerede "Kaydet"e basilinca REVIZYON
    // OLUSTURMADAN aninda o teklife yazilir. Teslim tarihi ve uretim notu genelde
    // teklif kabul edildikten sonra belli oldugu icin kilitli (Alınan Tekliflerim)
    // teklifte de guncellenebilir; teklif notu ise kilitli teklifte salt okunurdur.
    property string teslimatTarihi: ""
    property string musteriNotu: ""
    property string uretimNotu: ""

    function tarihGoster(yyyyAaGg) {
        if (!yyyyAaGg || yyyyAaGg.length !== 10)
            return ""
        const p = yyyyAaGg.split("-")
        return p[2] + "." + p[1] + "." + p[0]
    }

    function teslimatTarihiniAyarla(yeniTarih) {
        if (root.uretimAlaniKilitli)
            return
        root.teslimatTarihi = yeniTarih
        // Tamamlanmis teklifte (Giden'den revize) tarih yalnizca revizyona gider.
        if (root.duzenlenenKaynakTeklifId <= 0 || root.uretimBilgisiKilitli)
            return
        if (database.teklifTeslimatTarihiGuncelle(root.duzenlenenKaynakTeklifId, yeniTarih)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = "Teklif #" + root.duzenlenenKaynakTeklifId + " planlanan teslim tarihi "
                               + (yeniTarih.length > 0 ? root.tarihGoster(yeniTarih) + " olarak kaydedildi." : "kaldırıldı.")
        } else {
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = "Planlanan teslim tarihi kaydedilemedi."
        }
    }

    // Not penceresinden "Kaydet" ile cagrilir.
    function musteriNotunuKaydet(yeniNot) {
        if (root.formKilitli || yeniNot === root.musteriNotu)
            return
        root.musteriNotu = yeniNot
        // Kilitli teklifin kendisine yazilmaz; not yalnizca revizyona gider.
        if (root.duzenlenenKaynakTeklifId <= 0 || root.teklifKilitli) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = root.teklifKilitli
                ? "Teklif notu \"Teklifi Kaydet\" ile yeni revizyona yazılacak."
                : "Teklif notu, teklif kaydedilince birlikte kaydedilecek."
            return
        }
        if (database.teklifMusteriNotuGuncelle(root.duzenlenenKaynakTeklifId, yeniNot)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = "Teklif #" + root.duzenlenenKaynakTeklifId + " teklif notu kaydedildi."
        } else {
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = "Teklif notu kaydedilemedi."
        }
    }

    function uretimNotunuKaydet(yeniNot) {
        if (root.uretimAlaniKilitli || yeniNot === root.uretimNotu)
            return
        root.uretimNotu = yeniNot
        // Tamamlanmis teklifte (Giden'den revize) not yalnizca revizyona gider.
        if (root.duzenlenenKaynakTeklifId <= 0 || root.uretimBilgisiKilitli) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = root.uretimBilgisiKilitli
                ? "Üretim notu \"Teklifi Kaydet\" ile yeni revizyona yazılacak."
                : "Üretim notu, teklif kaydedilince birlikte kaydedilecek."
            return
        }
        if (database.teklifUretimNotuGuncelle(root.duzenlenenKaynakTeklifId, yeniNot)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = "Teklif #" + root.duzenlenenKaynakTeklifId + " üretim notu kaydedildi."
        } else {
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = "Üretim notu kaydedilemedi."
        }
    }

    // --- SATIR BAZLI uretim takibi (sepet satirindaki ✓ kutusu + not butonu) ---
    // Teklifin TAMAMI icin tek bir uretim notu, birden fazla urunlu tekliflerde
    // yetmiyor: hangi urunun bittigi ve hangi urune ait not oldugu kaybolur.
    // Bu yuzden her sepet satiri kendi "tamamlandi" bayragini ve kendi notunu
    // tasir (dbo.teklif_kalemleri.Tamamlandi / UretimNotu) -- ikisi de uretim
    // PDF'inde o satirin hizasinda basilir.
    //
    // Satir bazli takip yalnizca KAYITLI bir teklif acikken anlamlidir: uretim
    // teklif kabul edildikten sonra baslar, kaydedilmemis formda ya da kopyada
    // takip edilecek bir uretim yoktur.
    readonly property bool uretimTakibiGorunur: root.duzenlenenKaynakTeklifId > 0 && !root.kopyaModu

    // Bu satirin uretim bilgisi veritabanina YERINDE yazilabilir mi? Kalem
    // henuz kaydedilmemisse (sepete yeni eklenmis satir) veya teklif
    // tamamlanmissa yazilmaz; deger ekranda bekler, "Teklifi Kaydet" ile gider.
    function kalemYerindeYazilirMi(dizinIndex) {
        const kalem = root.sepet[dizinIndex]
        return !root.uretimBilgisiKilitli && kalem && (kalem.teklifKalemId || 0) > 0
    }

    function kalemTamamlandiAyarla(dizinIndex, tamamlandi) {
        if (root.uretimAlaniKilitli)
            return
        const kalemId = root.sepet[dizinIndex].teklifKalemId || 0
        const kalemAdi = root.sepet[dizinIndex].urunKodu || "Kalem"
        root.sepetAlaniGuncelle(dizinIndex, "tamamlandi", tamamlandi)

        if (!root.kalemYerindeYazilirMi(dizinIndex)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = root.uretimBilgisiKilitli
                ? kalemAdi + " üretim durumu \"Teklifi Kaydet\" ile yeni revizyona yazılacak."
                : kalemAdi + " üretim durumu, teklif kaydedilince birlikte kaydedilecek."
            return
        }

        if (database.teklifKalemTamamlandiGuncelle(kalemId, tamamlandi)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = kalemAdi + (tamamlandi ? " üretimi tamamlandı olarak işaretlendi."
                                                      : " üretim işareti kaldırıldı.")
        } else {
            // Yazilamadiysa ekrandaki kutu da eski haline donsun -- aksi halde
            // kullanici isaretlenmis saniyor, uretim formunda gorunmuyordu.
            root.sepetAlaniGuncelle(dizinIndex, "tamamlandi", !tamamlandi)
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = kalemAdi + " üretim durumu kaydedilemedi."
        }
    }

    function kalemUretimNotunuKaydet(dizinIndex, yeniNot) {
        if (root.uretimAlaniKilitli || dizinIndex < 0 || dizinIndex >= root.sepet.length)
            return
        const eskiNot = root.sepet[dizinIndex].uretimNotu || ""
        if (yeniNot === eskiNot)
            return
        const kalemId = root.sepet[dizinIndex].teklifKalemId || 0
        const kalemAdi = root.sepet[dizinIndex].urunKodu || "Kalem"
        root.sepetAlaniGuncelle(dizinIndex, "uretimNotu", yeniNot)

        if (!root.kalemYerindeYazilirMi(dizinIndex)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = root.uretimBilgisiKilitli
                ? kalemAdi + " üretim notu \"Teklifi Kaydet\" ile yeni revizyona yazılacak."
                : kalemAdi + " üretim notu, teklif kaydedilince birlikte kaydedilecek."
            return
        }

        if (database.teklifKalemUretimNotuGuncelle(kalemId, yeniNot)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = kalemAdi + " üretim notu kaydedildi."
        } else {
            root.sepetAlaniGuncelle(dizinIndex, "uretimNotu", eskiNot)
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = kalemAdi + " üretim notu kaydedilemedi."
        }
    }

    // Giden Tekliflerim'deki "Detay" butonundan cagrilir (bkz. SatisModuluPage.qml).
    // Ilgili teklifin kayitli TUM verisini ceker ve formu/sepeti onunla doldurur.
    function duzenlemeyeBasla(teklifId) {
        // guncelKur=false: revizyon ayni teklifin yeni surumudur, doviz tutarlari
        // teklifin kaydedildigi kurla gelir.
        const veri = root.teklifVerisiniYukle(teklifId, false)
        if (!veri)
            return

        root.secilenMusteriId = veri.musteriId
        root.secilenFirmaAdi = veri.musteriAdi
        ilgiliKisiAlani.text = veri.ilgiliKisi
        ilgiliKisiTelAlani.text = veri.ilgiliKisiTelefonu
        ilgiliKisiEpostaAlani.text = veri.ilgiliKisiEposta
        // Dogrudan property'e yazilir (teslimatTarihiniAyarla DEGIL): yukleme
        // sirasinda veritabanina geri yazma yapilmasin.
        root.teslimatTarihi = veri.teslimatTarihi || ""
        root.musteriNotu = veri.musteriNotu || ""
        root.uretimNotu = veri.uretimNotu || ""
        root.teklifDurumu = veri.durum || ""

        root.duzenlenenAnaTeklifId = veri.anaTeklifId
        root.duzenlenenKaynakTeklifId = veri.teklifId
        root.kopyaKaynakTeklifId = 0
    }

    // Listelerdeki "Kopya" butonundan cagrilir (bkz. SatisModuluPage.qml).
    // Kaynak teklifin TICARI ICERIGINI (sepet -- urun kodlari/aciklamalari, TL
    // fiyatlar ve maliyetler --, indirim/KDV, paketleme/tasima, para birimi, dil,
    // teslimat sekli/yeri, sozlesme metni) forma tasir. KUR ise kaynaktan
    // ALINMAZ, guncel olarak cekilir (bkz. teklifVerisiniYukle).
    // MUSTERIYE/O TEKLIFE ozel olan her sey bilincli olarak BOS gelir:
    //   musteri + ilgili kisi bilgileri -> yeni firma secilecek,
    //   teklif/uretim notu, planlanan teslim tarihi, durum -> yeni teklifin kendi
    //   sureci bastan baslar.
    // Kaynak teklif KILITLI (Kabul Edildi/Tamamlandı) veya "Revize Edildi" olsa da
    // kopya alinabilir: kaynaga hicbir sey yazilmadigi icin kilidin korudugu sey
    // (teklifin kendisi) zarar gormez. teklifDurumu bos kaldigi icin de yeni form
    // kilitli gorunmez.
    function kopyalamayaBasla(teklifId) {
        // guncelKur=true: kopyada tasinmasi istenen sey urun kodlari/aciklamalari ve
        // iceriktir; kur GUNCEL cekilir (bkz. teklifVerisiniYukle).
        const veri = root.teklifVerisiniYukle(teklifId, true)
        if (!veri)
            return

        root.secilenMusteriId = 0
        root.secilenFirmaAdi = ""
        ilgiliKisiAlani.text = ""
        ilgiliKisiTelAlani.text = ""
        ilgiliKisiEpostaAlani.text = ""
        root.teslimatTarihi = ""
        root.musteriNotu = ""
        root.uretimNotu = ""
        root.teklifDurumu = ""

        root.duzenlenenAnaTeklifId = 0
        root.duzenlenenKaynakTeklifId = 0
        root.kopyaKaynakTeklifId = veri.teklifId

        // Satir bazli uretim takibi kaynak teklifin KENDI uretimine aittir:
        // kopya bastan bagimsiz yeni bir teklif oldugu icin hicbir kalem
        // "tamamlandi" gelmez ve kalem notlari tasinmaz. teklifKalemId de
        // sifirlanir -- aksi halde yeni formdaki bir isaret, kaynak teklifin
        // kalemine yazilirdi.
        root.sepet = root.sepet.map(k => Object.assign({}, k, {
            teklifKalemId: 0,
            tamamlandi: false,
            uretimNotu: ""
        }))

        bilgiMesaji.color = Theme.basariAcik
        const dovizli = veri.paraBirimi === "USD" || veri.paraBirimi === "EUR"
        bilgiMesaji.text = "Teklif #" + veri.teklifId + " kopyalandı"
                           + (dovizli ? " (kur güncel olarak çekiliyor). " : ". ")
                           + "Firmayı seçip değişikliklerinizi yapın; \"Teklifi Kaydet\" yeni ve bağımsız bir teklif "
                           + "oluşturur, #" + veri.teklifId + " hiç değişmez."
    }

    // duzenlemeyeBasla + kopyalamayaBasla'nin ortak kismi: teklifin kayitli verisini
    // ceker ve HER IKI akista da AYNEN tasinan alanlari (sepet, ticari sartlar, dil/
    // para birimi, teslimat sekli/yeri, sozlesme metni) forma yazar. Basarisizsa
    // hata mesajini gosterip null doner.
    //
    // guncelKur: KUR bu iki akista farkli davranir.
    //   false (Detay/revizyon) -> teklifin kaydedildigi andaki ORIJINAL kur yuklenir;
    //          revizyon ayni teklifin yeni surumudur, doviz tutarlari kaymamalidir.
    //   true  (Kopya) -> kur GUNCEL olarak internetten cekilir. Kopyada tasinmasi
    //          istenen sey urun kodlari/aciklamalari ve iceriktir; aylar once
    //          kaydedilmis bir teklifin kuruyla yeni bir firmaya teklif verilmesi
    //          yanlis olurdu. Kalem fiyatlari TL tutulur (bkz. teklifDuzenlemeVerisiGetir:
    //          birimFiyatTl), bu yuzden yeni kur yalnizca doviz karsiliklarini
    //          yeniden hesaplar -- TL fiyatlar aynen kalir.
    function teklifVerisiniYukle(teklifId, guncelKur) {
        const veri = database.teklifDuzenlemeVerisiGetir(teklifId)
        if (!veri.basarili) {
            bilgiMesaji.color = Theme.tehlikeAcik
            bilgiMesaji.text = veri.hata.length > 0 ? veri.hata : "Teklif verisi alınamadı."
            return null
        }

        firmaAramaKutusu.text = ""
        teslimatSekliAlani.text = veri.teslimatSekli
        teslimatYeriAlani.text = veri.teslimatYeri

        // Ticari sartlar gorunen UcretAlani kutularina ayarla() ile yazilir --
        // kutudaki metin Turkce bicimde ("1.500,00") tutuldugu icin dogrudan
        // "text = ..." atamasi yapilmamali.
        indirimAlaniWrap.ayarla(veri.genelIndirimOrani)
        kdvAlaniWrap.ayarla(veri.kdvOrani)
        paketlemeAlaniWrap.ayarla(veri.paketlemeUcretiTl)
        tasimaAlaniWrap.ayarla(veri.tasimaUcretiTl)

        dilCombo.currentIndex = Math.max(0, dilCombo.model.indexOf(veri.dil))

        // Kur alanlarini ONCE, para birimi combo'sunu SONRA degistiriyoruz --
        // aksi halde combo degisince tetiklenen onCurrentTextChanged, usdKur/eurKur
        // henuz 0 gordugu icin otomatik olarak GUNCEL kuru internetten cekmeye
        // calisir ve teklifin kaydedildigi andaki ORIJINAL kuru ezer.
        const dovizliMi = veri.paraBirimi === "USD" || veri.paraBirimi === "EUR"
        if (guncelKur === true && dovizliMi) {
            // Kopya: eski kuru hic yuklemiyoruz. Ayrica onceki kurlari TEMIZLIYORUZ --
            // boylece cekme basarisiz olursa (agsizlik) kaydetme, kaynak teklifin
            // eski kuruyla sessizce yapilamaz; "Teklifi Kaydet" kurEksik uyarisi
            // verir ve kullanici kuru elle girer (bkz. kurEksik).
            root.usdKur = 0
            root.eurKur = 0
            usdKurBicimi.temizle()
            eurKurBicimi.temizle()
        } else if (veri.paraBirimi === "USD") {
            root.usdKur = veri.kur
            usdKurBicimi.ayarla(veri.kur)
        } else if (veri.paraBirimi === "EUR") {
            root.eurKur = veri.kur
            eurKurBicimi.ayarla(veri.kur)
        }
        paraBirimiCombo.currentIndex = Math.max(0, paraBirimiCombo.model.indexOf(veri.paraBirimi))

        // Kopyada kuru burada, para birimi secildikten SONRA cekiyoruz. Combo'nun
        // kendi onCurrentTextChanged'i de kur 0 oldugunda cekmeyi tetikler; ancak
        // para birimi DEGISMEDIYSE (ornegin ust uste iki USD teklif kopyalanirsa)
        // o sinyal hic gelmez -- bu yuzden cagriyi acikca yapiyoruz.
        if (guncelKur === true && dovizliMi && !root.kurCekiliyor)
            root.guncelKuruCek()

        root.sepet = veri.kalemler

        // Bu teklife ozel bir sozlesme metni kaydedilmisse onu tasi; yoksa bos
        // kalir ve "Satış Sözleşmesi" penceresi varsayilan metinle acilir.
        root.sozlesmeMetni = veri.sozlesmeMetni !== undefined ? veri.sozlesmeMetni : ""

        // Hangi teklifte oldugumuz zaten basliktan ("#2264 Teklif Bilgileri") ve
        // geri butonundan belli; ayrica bir "yuklendi" bildirimi gosterilmiyor.
        // Bilgi kutusu, onceki bir hatadan kalan metni tasimasin diye temizlenir.
        // (Kopya akisi bunun uzerine kendi aciklama mesajini yazar.)
        bilgiMesaji.color = Theme.basariAcik
        bilgiMesaji.text = ""

        return veri
    }

    // Revizyon / kopya modundan cikip formu bos "yeni teklif" durumuna dondurur.
    function duzenlemeyiIptalEt() {
        root.duzenlenenAnaTeklifId = 0
        root.duzenlenenKaynakTeklifId = 0
        root.kopyaKaynakTeklifId = 0
        root.sozlesmeMetni = ""

        root.sepet = []
        root.secilenMusteriId = 0
        root.secilenFirmaAdi = ""
        firmaAramaKutusu.text = ""
        ilgiliKisiAlani.text = ""
        ilgiliKisiTelAlani.text = ""
        ilgiliKisiEpostaAlani.text = ""
        teslimatSekliAlani.text = ""
        teslimatYeriAlani.text = ""
        root.teslimatTarihi = ""
        root.musteriNotu = ""
        root.uretimNotu = ""
        root.teklifDurumu = ""

        // Ticari sartlar da ekranin acilistaki varsayilanlarina doner.
        indirimAlaniWrap.ayarla(0)
        kdvAlaniWrap.ayarla(20)
        paketlemeAlaniWrap.ayarla(0)
        tasimaAlaniWrap.ayarla(0)

        bilgiMesaji.text = ""
    }

    // --- Doviz kurlari (elle girilir veya "Kuru Güncelle" ile internetten cekilir) ---
    property real usdKur: 0
    property real eurKur: 0
    property bool kurCekiliyor: false
    property string kurMesaji: ""
    property bool kurMesajiHata: false
    // Kur karti varsayilan olarak kompakt/salt-okunur gorunur; kullanici
    // "Elle düzenle"ye basarsa true olur, "Otomatik görünüme dön" ile geri doner.
    property bool kurElleDuzenleModu: false

    function paraBirimiSembol(pb) {
        return pb === "USD" ? "$" : (pb === "EUR" ? "€" : "₺")
    }

    // open.er-api.com'dan USD bazli kurlari ceker: rates.TRY dogrudan USD->TRY,
    // rates.TRY / rates.EUR ise EUR->TRY olarak hesaplanir. Basarisiz olursa
    // (agsizlik, zaman asimi, beklenmeyen yanit) mevcut elle giris alanlari
    // fallback olarak calismaya devam eder -- kullaniciya hata mesaji gosterilir.
    function guncelKuruCek() {
        root.kurCekiliyor = true
        root.kurMesaji = ""
        root.kurMesajiHata = false

        const istek = new XMLHttpRequest()
        istek.timeout = 8000
        istek.onreadystatechange = function() {
            if (istek.readyState !== XMLHttpRequest.DONE)
                return

            root.kurCekiliyor = false

            if (istek.status !== 200) {
                root.kurMesaji = "Kur alınamadı (sunucu hatası). Lütfen elle girin."
                root.kurMesajiHata = true
                return
            }

            try {
                const veri = JSON.parse(istek.responseText)
                const usdTry = veri && veri.rates ? Number(veri.rates.TRY) : NaN
                const eur = veri && veri.rates ? Number(veri.rates.EUR) : NaN

                if (!isFinite(usdTry) || usdTry <= 0 || !isFinite(eur) || eur <= 0) {
                    root.kurMesaji = "Kur verisi okunamadı. Lütfen elle girin."
                    root.kurMesajiHata = true
                    return
                }

                const eurTry = usdTry / eur

                root.usdKur = usdTry
                root.eurKur = eurTry
                usdKurAlani.text = usdTry.toFixed(4)
                eurKurAlani.text = eurTry.toFixed(4)
                root.kurMesaji = "Kurlar güncellendi (open.er-api.com)."
                root.kurMesajiHata = false
            } catch (e) {
                root.kurMesaji = "Kur verisi okunamadı. Lütfen elle girin."
                root.kurMesajiHata = true
            }
        }

        try {
            istek.open("GET", "https://open.er-api.com/v6/latest/USD")
            istek.send()
        } catch (e) {
            root.kurCekiliyor = false
            root.kurMesaji = "Kur alınamadı (bağlantı hatası). Lütfen elle girin."
            root.kurMesajiHata = true
        }
    }

    // TL tutarini secili teklif para birimine cevirir. Kur girilmemisse (0)
    // TL olarak birakir -- yanlislikla 0'a bolme veya anlamsiz deger olmasin.
    function tlDenCevir(tlTutar) {
        if (paraBirimiCombo.currentText === "USD" && root.usdKur > 0)
            return tlTutar / root.usdKur
        if (paraBirimiCombo.currentText === "EUR" && root.eurKur > 0)
            return tlTutar / root.eurKur
        return tlTutar
    }

    // tlDenCevir'in tersi: secili para biriminde girilen tutari TL'ye cevirir.
    function tlYeCevir(tutar) {
        if (paraBirimiCombo.currentText === "USD" && root.usdKur > 0)
            return tutar * root.usdKur
        if (paraBirimiCombo.currentText === "EUR" && root.eurKur > 0)
            return tutar * root.eurKur
        return tutar
    }

    // TL disi para birimi secili ama kur henuz yok (cekilemedi/girilmedi):
    // bu durumda tutarlar cevrilemez, teklif kaydedilmemeli.
    readonly property bool kurEksik: (paraBirimiCombo.currentText === "USD" && root.usdKur <= 0)
                                     || (paraBirimiCombo.currentText === "EUR" && root.eurKur <= 0)

    // Sepet kaleminin secili teklif dilindeki aciklamasi. Kalem her iki dili de
    // tasir (aciklamaTr/aciklamaEn); EN cevirisi yoksa TR'ye duser. Eski yapidaki
    // tek "aciklama" alani da geriye donuk olarak desteklenir.
    function kalemAciklamasi(k) {
        const tr = (k.aciklamaTr !== undefined && k.aciklamaTr.length > 0) ? k.aciklamaTr : (k.aciklama || "")
        if (dilCombo.currentText === "EN" && k.aciklamaEn && k.aciklamaEn.trim().length > 0)
            return k.aciklamaEn
        return tr
    }

    // Sepetteki Maliyet/Fiyat kutulari secili para biriminde gosterilir, ama
    // deger her zaman TL olarak saklanir. Kullanici kutuya dokunup degistirmeden
    // ciktiginda (editingFinished yine tetiklenir) yuvarlanmis gorunen deger
    // TL'ye geri cevrilip elle girilmis fiyati kaydirmasin diye, sadece gercekten
    // degisen deger yazilir.
    function sepetTutarGuncelle(dizinIndex, alanAdi, yeniDeger) {
        const mevcutTl = root.sepet[dizinIndex][alanAdi]
        if (yeniDeger.toFixed(2) === root.tlDenCevir(mevcutTl).toFixed(2))
            return
        const yeniTl = root.tlYeCevir(yeniDeger)
        root.sepetAlaniGuncelle(dizinIndex, alanAdi, yeniTl)
        // Maliyet, bu teklife ozel bir dokunus degil urunun GUNCEL maliyetidir:
        // elle duzeltildiginde katalogdaki deger de (dbo.urunler.GuncelMaliyetTL)
        // ayni anda guncellenir. Birim fiyat bunun DISINDADIR -- o teklifin
        // pazarligina gore degisir, katalog fiyatini baglamaz.
        if (alanAdi === "maliyet")
            root.urunMaliyetiniKatalogaYaz(dizinIndex, yeniTl)
    }

    // Sepetteki bir kalemin yeni maliyetini urun kataloguna isler. Manuel
    // kalemlerin (urunId yok) katalogda karsiligi olmadigi icin atlanir.
    function urunMaliyetiniKatalogaYaz(dizinIndex, maliyetTl) {
        const kalem = root.sepet[dizinIndex]
        const urunId = kalem.urunId || 0
        if (urunId <= 0)
            return

        if (database.urunMaliyetiGuncelle(urunId, maliyetTl)) {
            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = (kalem.urunKodu || "Ürün") + " maliyeti güncellendi: "
                               + root.paraFormat(maliyetTl) + " ₺"
            // Soldaki arama sonuclari maliyeti kendi icinde tasir; tazelenmezse
            // ayni urun sepetten cikarilip yeniden eklendiginde ESKI maliyetiyle
            // gelirdi.
            root.urunAramaTazele()
        } else {
            // Urun bulunamadiysa/manuel satirsa hata mesaji bos gelir -- bu
            // durumda kullaniciyi bosuna uyarmayiz, sepetteki deger yine gecerli.
            const hata = database.sonHataMesaji()
            if (hata.length > 0) {
                bilgiMesaji.color = Theme.tehlikeAcik
                bilgiMesaji.text = "Maliyet kataloğa kaydedilemedi: " + hata
            }
        }
    }

    // Sepet + form alanlarindan teklifKaydet()/satisSozlesmesiOlustur() icin
    // ortak QVariantMap'i uretir. "Teklifi Kaydet" ve "Satış Sözleşmesi"
    // butonlari AYNI veriyi kullanir; sozlesme butonu teklif henuz
    // kaydedilmemis olsa bile calisabilsin diye musteriAdi'ni de tasir.
    // Secili para birimi icin gecerli kur degerini dondurur (TL ise 1).
    function gecerliKur() {
        if (paraBirimiCombo.currentText === "USD") return root.usdKur > 0 ? root.usdKur : 1
        if (paraBirimiCombo.currentText === "EUR") return root.eurKur > 0 ? root.eurKur : 1
        return 1
    }

    // Sepet + form alanlarindan teklifKaydet()/satisSozlesmesiOlustur() icin
    // ortak QVariantMap'i uretir. Tum parasal tutarlar (kalemler ve toplamlar)
    // KAYDEDILECEGI para birimine (paraBirimiCombo) cevrilerek gonderilir --
    // boylece "USD teklif" veritabaninda da gercekten USD tutarlarla, dogru
    // ParaBirimi etiketiyle saklanir; PDF/sozlesme de dogrudan bu degerleri
    // kullanabilir (ayrica cevirmeye gerek kalmaz).
    function teklifVerisiOlustur() {
        const secilenParaBirimi = paraBirimiCombo.currentText
        const kur = root.gecerliKur()

        const kalemler = root.sepet.map(k => {
            const indirimliBirim = k.birimFiyatTl * (1 - root.indirimOrani / 100)
            return {
                urunId: k.urunId || 0,
                urunKodu: k.urunKodu || "MANUEL",
                aciklama: root.kalemAciklamasi(k),
                adet: k.adet,
                birimFiyat: root.tlDenCevir(k.birimFiyatTl),
                indirimliBirimFiyat: root.tlDenCevir(indirimliBirim),
                toplamTutar: root.tlDenCevir(indirimliBirim * k.adet),
                maliyetFiyati: root.tlDenCevir(k.maliyet),
                paraBirimi: secilenParaBirimi,
                kur: kur
            }
        })

        return {
            musteriId: root.secilenMusteriId,
            musteriAdi: root.secilenFirmaAdi,
            kullaniciId: root.kullaniciId,
            genelIndirimOrani: root.indirimOrani,
            kdvOrani: root.kdvOrani,
            paketlemeUcreti: root.tlDenCevir(root.paketlemeUcretiTl),
            tasimaUcreti: root.tlDenCevir(root.tasimaUcretiTl),
            paraBirimi: secilenParaBirimi,
            dil: dilCombo.currentText,
            ilgiliKisi: ilgiliKisiAlani.text,
            ilgiliKisiTelefonu: ilgiliKisiTelAlani.text,
            ilgiliKisiEposta: ilgiliKisiEpostaAlani.text,
            teslimatSekli: teslimatSekliAlani.text,
            teslimatYeri: teslimatYeriAlani.text,
            teslimatTarihi: root.teslimatTarihi,
            musteriNotu: root.musteriNotu.trim(),
            uretimNotu: root.uretimNotu.trim(),
            indirimliToplam: root.tlDenCevir(root.indirimliToplamTl),
            kdvTutari: root.tlDenCevir(root.kdvTutariTl),
            genelToplam: root.tlDenCevir(root.genelToplamTl),
            kalemler: kalemler,
            // Bos ise teklifKaydet() SatisSozlesmesiMetni'ni NULL birakir ve
            // PDF, dilin varsayilan sozlesme metnini kullanir.
            sozlesmeMetni: root.sozlesmeMetni,
            // 0 ise (normal "yeni teklif" akisi) teklifKaydet() bunu tamamen
            // yok sayar -- davranis degismez. >0 ise (Detay -> Revize Et akisi)
            // yeni kayit bu teklifin (kok) revizyonu olarak eklenir.
            anaTeklifId: root.duzenlenenAnaTeklifId,
            // Kopya akisi: yalnizca "hangi tekliften kopyalandi" izi olarak
            // saklanir. Kaynak teklife hicbir sey yapilmaz (bkz. kopyalamayaBasla);
            // 0 ise hic yazilmaz. anaTeklifId ile ayni anda dolu olmaz.
            kopyaKaynakTeklifId: root.kopyaKaynakTeklifId
        }
    }

    // "Satış Sözleşmesi" butonu: pencereyi, gosterilecek metin ve secili dilin
    // varsayilan metniyle doldurup acar.
    //
    // Gosterilen metin sirasi: (1) bu oturumda pencerede duzenlenmis metin,
    // (2) teklif kayitliysa veritabanindaki metni, (3) dilin varsayilan metni.
    // (2) ve (3) tek cagriyla halledilir -- teklifSozlesmeMetniGetir, kayit
    // yoksa varsayilani doner.
    function sozlesmeDuzenleyiciyiAc() {
        const dil = dilCombo.currentText
        sozlesmeDialogu.varsayilanMetin = database.varsayilanSozlesmeMetni(dil)
        sozlesmeDialogu.metin = root.sozlesmeMetni.length > 0
            ? root.sozlesmeMetni
            : database.teklifSozlesmeMetniGetir(root.duzenlenenKaynakTeklifId, dil)
        sozlesmeDialogu.open()
    }

    function sepeteEkle(kalem) {
        const yeniSepet = root.sepet.slice()
        // Ayni urun zaten sepette varsa yeni bir satir eklemek yerine
        // mevcut satirin adedini artir (manuel eklenen kalemler haric).
        if (kalem.urunKodu !== "MANUEL" && kalem.urunId) {
            const mevcutIndex = yeniSepet.findIndex(k => k.urunId === kalem.urunId)
            if (mevcutIndex !== -1) {
                yeniSepet[mevcutIndex] = Object.assign({}, yeniSepet[mevcutIndex])
                yeniSepet[mevcutIndex].adet += kalem.adet
                root.sepet = yeniSepet
                return
            }
        }
        yeniSepet.push(kalem)
        root.sepet = yeniSepet
    }

    function sepettenCikar(dizinIndex) {
        const yeniSepet = root.sepet.slice()
        yeniSepet.splice(dizinIndex, 1)
        root.sepet = yeniSepet
    }

    // --- Sepet satirlarini surukleyerek siralama ---
    // Sepet dizisinin sirasi teklif kalemlerinin kayit sirasi, dolayisiyla
    // PDF'teki satir sirasidir (bkz. Database::teklifKaydet + ORDER BY
    // TeklifKalemId); musteri belli bir siralama istediginde kalemler sepette
    // tutamagindan surukleyerek duzenlenir.
    //
    // Surukleme suresince sepet dizisine DOKUNULMAZ: model degisirse ListView
    // delegate'leri yeniden kurar ve suruklemeyi baslatan MouseArea yok olurdu.
    // Bunun yerine sadece iki durum degiskeni tutulur, dizi tek seferde birakma
    // aninda guncellenir.
    property int suruklenenIndex: -1      // suruklenen satirin dizideki yeri
    property int suruklemeHedefIndex: -1  // kalemin birakilacagi ARALIK (0..uzunluk)

    // Kaynak satiri, hedef aralik gostergesinin bulundugu yere tasir.
    function sepetSiraTasi(kaynakIndex, aralikIndex) {
        if (kaynakIndex < 0 || kaynakIndex >= root.sepet.length)
            return
        // Aralik indeksi satir aralarini sayar; kaynak satir listeden cikinca
        // kendisinden SONRAKI araliklar bir kayar.
        let hedefIndex = aralikIndex > kaynakIndex ? aralikIndex - 1 : aralikIndex
        hedefIndex = Math.max(0, Math.min(root.sepet.length - 1, hedefIndex))
        if (hedefIndex === kaynakIndex)
            return
        const yeniSepet = root.sepet.slice()
        const tasinan = yeniSepet.splice(kaynakIndex, 1)[0]
        yeniSepet.splice(hedefIndex, 0, tasinan)
        root.sepet = yeniSepet
    }

    // Sepet satirindaki adet/maliyet/birim fiyat elle degistirildiginde cagrilir --
    // alttaki tum ozet hesaplamalari (readonly property'ler) sepet'e bagli oldugu
    // icin bu atama tek basina hepsini yeniden hesaplatir.
    function sepetAlaniGuncelle(dizinIndex, alanAdi, deger) {
        const yeniSepet = root.sepet.slice()
        yeniSepet[dizinIndex] = Object.assign({}, yeniSepet[dizinIndex])
        yeniSepet[dizinIndex][alanAdi] = deger
        root.sepet = yeniSepet
    }

    // --- Canli hesaplamalar ---
    readonly property real indirimOrani: indirimAlaniWrap.deger
    readonly property real kdvOrani: kdvAlaniWrap.deger
    readonly property real paketlemeUcretiTl: paketlemeAlaniWrap.deger
    readonly property real tasimaUcretiTl: tasimaAlaniWrap.deger

    readonly property real toplamMaliyetTl: sepet.reduce((acc, k) => acc + (k.maliyet * k.adet), 0)
    readonly property real indirimsizToplamTl: sepet.reduce((acc, k) => acc + (k.birimFiyatTl * k.adet), 0)
    readonly property real indirimliToplamTl: indirimsizToplamTl * (1 - indirimOrani / 100)
    readonly property real kdvTutariTl: indirimliToplamTl * (kdvOrani / 100)
    readonly property real genelToplamTl: indirimliToplamTl + kdvTutariTl + paketlemeUcretiTl + tasimaUcretiTl
    readonly property real karTutariTl: indirimliToplamTl - toplamMaliyetTl
    // Kar orani maliyet uzerinden hesaplanir (kar tutari / toplam maliyet).
    readonly property real karOrani: toplamMaliyetTl > 0 ? (karTutariTl / toplamMaliyetTl * 100) : 0

    function paraFormat(deger) {
        return deger.toLocaleString(Qt.locale("tr_TR"), 'f', 2)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    // Bos alana (herhangi bir kontrole denk gelmeyen bolgeye) tiklaninca
    // aktif odagi (ornegin Firma ara kutusundaki imleci) birakmak icin --
    // QtQuick'te odaklanabilir olmayan bir alana tiklamak varsayilan olarak
    // hicbir seyi odaktan cikarmiyor, bu yuzden acikca root'a odak veriyoruz.
    // Diger kontroller bunun uzerinde durdugu icin onlara tiklamalar buraya
    // gecmeden once kendi MouseArea/TextField'larinca yakalanir.
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    // Sag ustteki bildirim kutusu. Gecici bir geri bildirim oldugu icin
    // ekranda kalici degil: metin her degistiginde 5 saniyelik sayac
    // bastan baslar ve sure dolunca kutu kendiliginden kaybolur. Art arda
    // gelen mesajlarda (ornegin "PDF hazırlanıyor..." -> "PDF: ...") sayac
    // sifirlanir, yani her mesaj kendi 5 saniyesini yasar.
    //
    // ONEMLI: kutu bilerek baslik satirinin (RowLayout) DISINDA, sayfanin
    // uzerinde yuzen bir katman olarak duruyor. Layout'un icinde oldugunda
    // uzun bir mesaj (ornegin kopyalama bildirimi) satirin minimum genisligini
    // buyutuyor, bu da mesaj ekranda kaldigi surece tum sayfayi saga
    // tasiriyordu. Yuzen katman hicbir seyin yerini degistirmez; ustunden
    // gecer ve kendiliginden kaybolur. Icinde MouseArea olmadigi icin
    // altindaki butonlara yapilan tiklamalari da engellemez.
    Rectangle {
        id: bilgiMesajiKutusu
        z: 100
        visible: bilgiMesaji.text.length > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 24
        anchors.rightMargin: 24
        radius: Theme.radiusNormal
        color: bilgiMesaji.color === Theme.tehlikeAcik ? Qt.rgba(0.14, 0.08, 0.09, 0.97) : Qt.rgba(0.07, 0.14, 0.10, 0.97)
        border.width: 1
        border.color: bilgiMesaji.color === Theme.tehlikeAcik ? Theme.tehlikeAcik : Theme.basariAcik

        // Metin sigmazsa alt satira sarsin; kutu pencereyi asmasin.
        readonly property int enFazlaGenislik: Math.min(420, root.width - 96)
        implicitWidth: Math.min(bilgiMesaji.implicitWidth, enFazlaGenislik) + 24
        implicitHeight: bilgiMesaji.height + 14

        Timer {
            id: bilgiMesajiZamanlayici
            interval: 5000
            onTriggered: bilgiMesaji.text = ""
        }

        Label {
            id: bilgiMesaji
            anchors.centerIn: parent
            width: Math.min(implicitWidth, bilgiMesajiKutusu.enFazlaGenislik)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.basariAcik
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            font.bold: true

            // Mesaji kimin yazdigi onemli degil (PDF, kayit, hata...):
            // hepsi bu tek yerden otomatik kapanir.
            onTextChanged: {
                if (bilgiMesaji.text.length > 0)
                    bilgiMesajiZamanlayici.restart()
                else
                    bilgiMesajiZamanlayici.stop()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Baslik ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Revizyon modunda, gelinen listeye (Giden/Alınan/Biten Tekliflerim)
            // geri donus. Normal "Teklif Ver" akisinda tamamen gizlidir.
            Button {
                id: geriButonu
                visible: root.altSayfaModu
                Layout.preferredHeight: 38
                leftPadding: 14
                rightPadding: 14
                onClicked: {
                    root.duzenlemeyiIptalEt()
                    root.geriDonuldu()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: geriButonu.hovered ? Theme.panelHover : Theme.panel
                    border.width: 1
                    border.color: geriButonu.hovered ? Theme.kenarlikVurgu : Theme.kenarlik
                }
                contentItem: Text {
                    text: "◀  " + root.geriDonusEtiketi
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            ColumnLayout {
                spacing: 2
                Label {
                    // Mevcut bir teklif acikken baslik teklifin kendisini soyler
                    // ("#2264 Teklif Bilgileri"); hangi teklifte oldugumuz tek bakista
                    // bellidir, bu yuzden ayrica bir rozet/aciklama satiri tasinmiyor.
                    text: root.duzenlenenAnaTeklifId > 0
                        ? "#" + root.duzenlenenKaynakTeklifId + " Teklif Bilgileri"
                        : root.kopyaModu
                        ? "#" + root.kopyaKaynakTeklifId + " Kopyası — Yeni Teklif"
                        : "Teklif Oluştur"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                // Kilitli teklifte formun neden degistirilemedigini acikca soyler.
                Label {
                    visible: root.teklifKilitli
                    text: root.revizyonIzinli
                          ? "🔒  " + root.teklifDurumu + " — bu teklifin kendisi değişmez; yaptığınız değişiklikler \"Teklifi Kaydet\" ile yeni revizyon olarak kaydedilir."
                          : root.uretimBilgisiKilitli
                          ? "🔒  " + root.teklifDurumu + " — bu teklif değiştirilemez."
                          : "🔒  " + root.teklifDurumu + " — teklif değiştirilemez; yalnızca teslim tarihi, üretim notu ve sepetteki ürünlerin üretim durumu/notu güncellenebilir."
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
                // Revize edilmis teklif kilitli DEGILDIR (tekrar revize edilebilir),
                // ama artik gecerli degildir: yerine daha yeni bir revizyon gecmistir.
                // Kullanici eski bir surumu actigini bilmeli.
                Label {
                    visible: root.teklifDurumu === "Revize Edildi"
                    text: "⟳  Bu teklif revize edildi — artık geçerli değil; PDF'i yeniden üretilirse üstüne \"geçerli değildir\" bandı basılır."
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.uyariAcik
                }
                // Kopya modu: kullanici bunun kaynak teklifi DEGISTIRMEDIGINI, yeni
                // ve bagimsiz bir teklif hazirladigini her an gorsun.
                Label {
                    visible: root.kopyaModu
                    text: "⧉  Teklif #" + root.kopyaKaynakTeklifId + " kopyalandı — kaynak teklif hiç değişmez. "
                          + "Kaydedince bağımsız, yeni bir teklif oluşur (revizyon değil)."
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.vurguAcik
                }
            }

            Item { Layout.fillWidth: true }

            // Notlar: formda kalici metin kutusu yerine baslikta iki kucuk buton;
            // tiklaninca not penceresi acilir (bkz. musteriNotuDialogu/uretimNotuDialogu).
            NotButonu {
                ikon: "📝"
                etiket: "Teklif Notu"
                notMetni: root.musteriNotu
                renk: Theme.vurgu
                ipucu: "Büro ve satış personeli için iç not. Teklif ve üretim PDF'ine basılmaz."
                onClicked: musteriNotuDialogu.open()
            }

            NotButonu {
                ikon: "🔧"
                etiket: "Üretim Notu"
                notMetni: root.uretimNotu
                renk: Theme.basari
                ipucu: "Üretim personeli için not. Üretim PDF'ine basılır."
                onClicked: uretimNotuDialogu.open()
            }
        }

        // ---- Ust "Teklif Bilgileri" seridi: musteri/ticari sartlar/teslimat/dil-para
        // alanlari artik SOLDA dikey bir kolonda degil, ekranin USTUNDE iki satirlik
        // yatay bir seritte topluca yer aliyor. Boylece hem yukseklik hem genislik
        // olarak ekranin buyuk cogunlugu Urun Ara + Sepet'e ayrilabiliyor.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: ustBilgiSutunu.implicitHeight + 28
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            ColumnLayout {
                id: ustBilgiSutunu
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ---- 4 mantiksal grup, yan yana; her grup kendi icinde 2 satir ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    // --- Grup 1: MUSTERI (firma/ilgili kisi/telefon/eposta) -- genis, esnek ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Firma tek basina, satirin tamamini kaplar -- arama/secim
                            // kutusu en genis alani hak ediyor.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Label { text: "🏢  FİRMA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.girdiYuksekligi
                                    radius: Theme.radiusKucuk
                                    color: Theme.arkaplan
                                    border.width: 1
                                    border.color: firmaAramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        TextField {
                                            id: firmaAramaKutusu
                                            enabled: !root.formKilitli
                                            Layout.fillWidth: true
                                            background: null
                                            color: Theme.metinBirincil
                                            placeholderTextColor: Theme.metinCokSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            placeholderText: root.secilenFirmaAdi.length > 0 ? root.secilenFirmaAdi : "Firma ara veya seç..."
                                            verticalAlignment: TextInput.AlignVCenter
                                            // Arama artik veritabanina asenkron gidiyor (Database::musteriAraBaslat
                                            // + musteriSonuclariHazir sinyali, ayri thread'de calisir -- bkz.
                                            // AramaWorker) ve her tus basisinda degil, kullanici yazmayi
                                            // kestikten kisa bir sure sonra tetiklenir (debounce). Bu ikisi
                                            // birlikte, once her karakterde UI thread'ini bloke eden senkron
                                            // sorgularin sebep oldugu donma/kasmayi gideriyor.
                                            onTextChanged: {
                                                musteriAramaTimer.restart()
                                                musteriPopup.open()
                                            }
                                            onFocusChanged: {
                                                if (focus) {
                                                    database.musteriAraBaslat(text, 15)
                                                    musteriPopup.open()
                                                }
                                            }

                                            Timer {
                                                id: musteriAramaTimer
                                                interval: 250
                                                onTriggered: database.musteriAraBaslat(firmaAramaKutusu.text, 15)
                                            }

                                            Connections {
                                                target: database
                                                function onMusteriSonuclariHazir(arama, sonuclar) {
                                                    // Kullanici bu sonuc donene kadar yazmaya devam etmis
                                                    // olabilir -- artik guncel olmayan (eskimis) sonucu
                                                    // gormezden gel.
                                                    if (arama === firmaAramaKutusu.text)
                                                        musteriSonuclari.model = sonuclar
                                                }
                                            }
                                        }
                                    }

                                    Popup {
                                        id: musteriPopup
                                        y: parent.height + 4
                                        width: parent.width
                                        padding: 4
                                        modal: false
                                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                                        background: Rectangle {
                                            color: Theme.panel
                                            radius: Theme.radiusNormal
                                            border.width: 1
                                            border.color: Theme.kenarlik
                                        }

                                        contentItem: ListView {
                                            id: musteriSonuclari
                                            implicitHeight: Math.min(240, count * 44)
                                            clip: true
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: musteriSonuclari.width
                                                height: 44
                                                color: musteriSatiriAlani.containsMouse ? Theme.panelHover : "transparent"
                                                radius: Theme.radiusKucuk

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 0
                                                    Label {
                                                        text: modelData.firmaAdi
                                                        color: Theme.metinBirincil
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: Theme.fontBoyutNormal
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    Label {
                                                        text: modelData.ilgiliKisi
                                                        visible: text.length > 0
                                                        color: Theme.metinSoluk
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                MouseArea {
                                                    id: musteriSatiriAlani
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.secilenMusteriId = modelData.musteriId
                                                        root.secilenFirmaAdi = modelData.firmaAdi
                                                        ilgiliKisiAlani.text = modelData.ilgiliKisi
                                                        ilgiliKisiAlani.cursorPosition = 0
                                                        ilgiliKisiTelAlani.text = modelData.ilgiliKisiTelefonu
                                                        ilgiliKisiTelAlani.cursorPosition = 0
                                                        ilgiliKisiEpostaAlani.text = modelData.firmaEposta
                                                        ilgiliKisiEpostaAlani.cursorPosition = 0
                                                        firmaAramaKutusu.text = ""
                                                        musteriPopup.close()
                                                        // Odak firma kutusunda kalirsa bir sonraki
                                                        // tiklama onFocusChanged'i tetiklemez (odak
                                                        // zaten true'dur) ve popup acilmaz; odagi
                                                        // birakip bir sonraki tiklamada yeniden
                                                        // acilmasini sagliyoruz.
                                                        firmaAramaKutusu.focus = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        }

                        // Telefon / Ilgili Kisi / Ilgili Kisi E-posta -- Firma'nin
                        // altinda, ucu esit genislikte 3 kutu.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                Layout.minimumWidth: 150
                                Layout.maximumWidth: 150
                                spacing: 4
                                Label { text: "TELEFON"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.girdiYuksekligi
                                    radius: Theme.radiusKucuk
                                    color: Theme.arkaplan
                                    border.width: 1
                                    border.color: ilgiliKisiTelAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                    TextField {
                                        id: ilgiliKisiTelAlani
                                        readOnly: root.formKilitli
                                        onTextChanged: if (!activeFocus) cursorPosition = 0
                                        onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        background: null
                                        color: Theme.metinBirincil
                                        placeholderTextColor: Theme.metinCokSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                Layout.minimumWidth: 150
                                Layout.maximumWidth: 150
                                spacing: 4
                                Label { text: "İLGİLİ KİŞİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.girdiYuksekligi
                                    radius: Theme.radiusKucuk
                                    color: Theme.arkaplan
                                    border.width: 1
                                    border.color: ilgiliKisiAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                    TextField {
                                        id: ilgiliKisiAlani
                                        readOnly: root.formKilitli
                                        onTextChanged: if (!activeFocus) cursorPosition = 0
                                        onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        background: null
                                        color: Theme.metinBirincil
                                        placeholderTextColor: Theme.metinCokSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Label { text: "İLGİLİ KİŞİ E-POSTA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.girdiYuksekligi
                                    radius: Theme.radiusKucuk
                                    color: Theme.arkaplan
                                    border.width: 1
                                    border.color: ilgiliKisiEpostaAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                    TextField {
                                        id: ilgiliKisiEpostaAlani
                                        readOnly: root.formKilitli
                                        onTextChanged: if (!activeFocus) cursorPosition = 0
                                        onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        background: null
                                        color: Theme.metinBirincil
                                        placeholderTextColor: Theme.metinCokSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 2: TICARI SARTLAR (indirim/kdv/paketleme/tasima) -- kisa degerler, dar ---
                    // NOT: minimumWidth/maximumWidth de sabitlenmezse, ic alanlarin
                    // (TextField/Label) dogal minimum genisligi preferredWidth'i ezip
                    // grubu istenenden cok daha genis gosterebiliyor -- ucu ucuna
                    // sabitlemek genislik farkinin gercekten gorunur olmasini saglar.
                    ColumnLayout {
                        enabled: !root.formKilitli
                        Layout.preferredWidth: 210
                        Layout.minimumWidth: 210
                        Layout.maximumWidth: 210
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "💳  İNDİRİM %"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; elide: Text.ElideRight; Layout.maximumWidth: 100 }
                                UcretAlani { id: indirimAlaniWrap; baslangicDegeri: 0; birim: "%" }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "KDV %"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                UcretAlani { id: kdvAlaniWrap; baslangicDegeri: 20; birim: "%" }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "PAKETLEME"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; elide: Text.ElideRight; Layout.maximumWidth: 100 }
                                UcretAlani { id: paketlemeAlaniWrap; baslangicDegeri: 0; birim: "TL" }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "TAŞIMA"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                UcretAlani { id: tasimaAlaniWrap; baslangicDegeri: 0; birim: "TL" }
                            }
                        }

                        // NOT: Eskiden burada, UcretAlani kutularinin metnini yansitan gizli
                        // hesap TextField'lari vardi. Artik UcretAlani sayisal degerini
                        // dogrudan "deger" property'si ile veriyor (bkz. indirimOrani vb.),
                        // bu yuzden gizli alanlara gerek kalmadi.
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 3: TESLIMAT (sekli / yeri; Detay ekraninda + planlanan tarih) ---
                    // Normal Teklif Ver ekraninda eski 240px genislik aynen korunur.
                    ColumnLayout {
                        Layout.preferredWidth: root.duzenlenenAnaTeklifId > 0 ? 340 : 240
                        Layout.minimumWidth: root.duzenlenenAnaTeklifId > 0 ? 340 : 240
                        Layout.maximumWidth: root.duzenlenenAnaTeklifId > 0 ? 340 : 240
                        spacing: 8

                        RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "🚚  TESLİMAT ŞEKLİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.girdiYuksekligi
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: teslimatSekliAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                TextField {
                                    id: teslimatSekliAlani
                                    readOnly: root.formKilitli
                                    onTextChanged: if (!activeFocus) cursorPosition = 0
                                    onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    background: null
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    verticalAlignment: TextInput.AlignVCenter
                                }
                            }
                        }

                        // Planlanan teslim tarihi: takvimden secilir, "✕" ile temizlenir.
                        // SADECE Detay ekraninda gorunur.
                        ColumnLayout {
                            visible: root.duzenlenenAnaTeklifId > 0
                            Layout.preferredWidth: 130
                            Layout.minimumWidth: 130
                            Layout.maximumWidth: 130
                            spacing: 4
                            Label { text: "TESLİM TARİHİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.girdiYuksekligi
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: teslimTakvimi.visible ? Theme.kenarlikVurgu : Theme.kenarlik

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !root.uretimAlaniKilitli
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: teslimTakvimi.open()
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 4
                                    Text {
                                        Layout.fillWidth: true
                                        text: root.teslimatTarihi.length > 0 ? root.tarihGoster(root.teslimatTarihi) : "Tarih seçin"
                                        color: root.teslimatTarihi.length > 0 ? Theme.metinBirincil : Theme.metinCokSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: root.teslimatTarihi.length > 0 && !root.uretimAlaniKilitli
                                        text: "✕"
                                        color: temizleAlani.containsMouse ? Theme.tehlikeAcik : Theme.metinSoluk
                                        font.pixelSize: Theme.fontBoyutKucuk
                                        MouseArea {
                                            id: temizleAlani
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.teslimatTarihiniAyarla("")
                                        }
                                    }
                                }

                                TarihTakvimi {
                                    id: teslimTakvimi
                                    y: parent.height + 4
                                    onTarihSecildi: (tarih) => root.teslimatTarihiniAyarla(tarih)
                                }
                            }
                        }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "TESLİMAT YERİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.girdiYuksekligi
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: teslimatYeriAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                TextField {
                                    id: teslimatYeriAlani
                                    readOnly: root.formKilitli
                                    onTextChanged: if (!activeFocus) cursorPosition = 0
                                    onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    background: null
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    verticalAlignment: TextInput.AlignVCenter
                                }
                            }
                        }
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 4: DIL & PARA BIRIMI -- kisa secim kutulari, en dar ---
                    ColumnLayout {
                        enabled: !root.formKilitli
                        Layout.preferredWidth: 150
                        Layout.minimumWidth: 150
                        Layout.maximumWidth: 150
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "🌐  DİL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.girdiYuksekligi
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik
                                ComboBox {
                                    id: dilCombo
                                    anchors.fill: parent
                                    background: null
                                    model: ["TR", "EN"]
                                    // Dil degisince urun arama sonuclarini (ve dolayisiyla
                                    // aciklamalari) hemen yeniden cek -- kullanici tekrar
                                    // yazmak zorunda kalmasin.
                                    onCurrentTextChanged: root.urunAramaTazele()
                                    contentItem: Text {
                                        text: dilCombo.displayText
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 12
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "PARA BİRİMİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.girdiYuksekligi
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik
                                ComboBox {
                                    id: paraBirimiCombo
                                    anchors.fill: parent
                                    background: null
                                    model: ["TL", "USD", "EUR"]
                                    // TL disi bir para birimine gecildiginde, kur henuz
                                    // girilmemisse (0) otomatik olarak internetten cekmeyi
                                    // dene -- kullanicinin ayrica "Kuru Güncelle"ye
                                    // basmasini beklemeden. Basarisiz olursa (agsizlik vs.)
                                    // guncelKuruCek() zaten hata mesaji gosterip elle giris
                                    // alanlarini fallback olarak birakiyor.
                                    onCurrentTextChanged: {
                                        if (paraBirimiCombo.currentText === "USD" && root.usdKur <= 0)
                                            root.guncelKuruCek()
                                        else if (paraBirimiCombo.currentText === "EUR" && root.eurKur <= 0)
                                            root.guncelKuruCek()
                                    }
                                    contentItem: Text {
                                        text: paraBirimiCombo.displayText
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Urun ara + sepet: ust serit artik yatayda oldugu icin bu alan
        // ekranin TAM genisligini kullanabiliyor -- Sepet'teki Aciklama sutunu
        // dahil her sutun cok daha rahat nefes alir.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // Urun arama -- kilitli (salt goruntulenen) teklifte gizlenir; gizli
            // oge Layout'ta yer kaplamadigi icin sepet tam genislige yayilir.
            Rectangle {
                visible: root.urunAramaGorunur
                // Revize moduna gecilip panel yeniden gorunur oldugunda liste bos
                // kalmasin diye aramayi tazeliyoruz.
                onVisibleChanged: if (visible) root.urunAramaTazele()
                Layout.fillHeight: true
                Layout.preferredWidth: 360
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    BolumBasligi { baslik: "🔍  ÜRÜN ARA" }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.girdiYuksekligi
                        radius: Theme.radiusKucuk
                        color: Theme.arkaplan
                        border.width: 1
                        border.color: urunAramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                        TextField {
                            id: urunAramaKutusu
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            background: null
                            color: Theme.metinBirincil
                            placeholderTextColor: Theme.metinCokSoluk
                            placeholderText: "Ürün kodu veya açıklaması ara..."
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            verticalAlignment: TextInput.AlignVCenter
                            // Sayfa acilir acilmaz (Component.onCompleted) ve her tus basisinda
                            // eskiden database.urunAra() DOGRUDAN ve SENKRON cagriliyordu -- SQL
                            // Server'a agdan yapilan bu sorgu bitene kadar tum pencere donuyordu
                            // ("Yanit Vermiyor"). Artik urunAraBaslat() sadece istegi ayri thread'e
                            // (AramaWorker) yolluyor; sonuc asagidaki Connections uzerinden asenkron
                            // geliyor. Yazarken de her karakterde degil, debounce ile tetikleniyor.
                            onTextChanged: urunAramaTimer.restart()
                            Component.onCompleted: root.urunAramaTazele()

                            Timer {
                                id: urunAramaTimer
                                interval: 250
                                onTriggered: root.urunAramaTazele()
                            }

                            Connections {
                                target: database
                                function onUrunSonuclariHazir(arama, dil, sonuclar) {
                                    if (arama === urunAramaKutusu.text && dil === dilCombo.currentText)
                                        urunListesi.model = sonuclar
                                }
                            }
                        }
                    }

                    ListView {
                        id: urunListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        reuseItems: false

                        // ONEMLI: delegate'in KOKU cerceveyi cizen Rectangle OLMAMALI.
                        // layer.enabled icerigi tam olarak item sinirlarina kirpar;
                        // radius'lu bir Rectangle'in kenarligi ise antialias icin
                        // yarim piksel disari tasar. Kenarlik dogrudan layer'in
                        // kenarinda kalirsa (ozellikle dikey kenarlar) kirpilip
                        // gorunmez oluyordu. Bu yuzden layer disdaki seffaf Item'da,
                        // cerceve ise 1px iceri alinmis cocuk Rectangle'da.
                        delegate: Item {
                            id: urunSatiri
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 54
                            layer.enabled: true
                            layer.smooth: true

                            Rectangle {
                                id: urunSatiriCerceve
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Theme.radiusKucuk
                                color: urunSatiriAlani.containsMouse ? Theme.panelHover : (urunSatiri.index % 2 === 0 ? Theme.arkaplanIkincil : Theme.panel)
                                border.width: 1
                                border.color: urunSatiriAlani.containsMouse ? Theme.kenarlikVurgu : Theme.kenarlik
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: urunSatiriAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            RowLayout {
                                anchors.fill: urunSatiriCerceve
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Label {
                                        text: urunSatiri.modelData.urunKodu
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.bold: true
                                        font.pixelSize: Theme.fontBoyutKucuk
                                    }
                                    Label {
                                        text: urunSatiri.modelData.urunAciklamasi
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 0
                                        Layout.minimumWidth: 0
                                        maximumLineCount: 1
                                    }
                                }

                                Label {
                                    text: root.paraFormat(urunSatiri.modelData.birimFiyat) + " ₺"
                                    color: Theme.vurguAcik
                                    font.family: "Consolas"
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    Layout.rightMargin: 8
                                }

                                Button {
                                    text: "Seç"
                                    enabled: !root.formKilitli
                                    opacity: enabled ? 1.0 : 0.4
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 30
                                    onClicked: root.sepeteEkle({
                                        urunId: urunSatiri.modelData.urunId,
                                        urunKodu: urunSatiri.modelData.urunKodu,
                                        aciklama: urunSatiri.modelData.urunAciklamasi,
                                        aciklamaTr: urunSatiri.modelData.urunAciklamasiTr,
                                        aciklamaEn: urunSatiri.modelData.urunAciklamasiEn,
                                        adet: 1,
                                        birimFiyatTl: urunSatiri.modelData.birimFiyat,
                                        maliyet: urunSatiri.modelData.maliyet
                                    })
                                    background: Rectangle {
                                        radius: 5
                                        color: Theme.vurgu
                                    }
                                    contentItem: Text {
                                        text: "Seç"
                                        color: "#ffffff"
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
            }

            // Sepet
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { width: 4; height: 14; radius: 2; color: Theme.vurgu }
                        Label { text: "🛒  SEPET"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1.2; font.bold: true }
                        Label {
                            text: root.sepet.length > 0 ? ("(" + root.sepet.length + ")") : ""
                            color: Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        // Eski WPF programindaki gibi kompakt "+" ikon-butonu: buyuk
                        // "+ Manuel Ürün Ekle" butonu yerine az yer kaplayan bir kisayol.
                        Rectangle {
                            id: manuelEkleButonu
                            visible: !root.formKilitli
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: Theme.radiusKucuk
                            color: manuelEkleAlani.containsMouse ? Theme.panelHover : "transparent"
                            border.width: 1
                            border.color: Theme.kenarlikVurgu

                            Label {
                                anchors.centerIn: parent
                                text: "+"
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutOrta
                                font.bold: true
                            }

                            MouseArea {
                                id: manuelEkleAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: manuelUrunDialogu.open()
                            }

                            ToolTip.visible: manuelEkleAlani.containsMouse
                            ToolTip.text: "Sepete manuel ürün ekle"
                            ToolTip.delay: 400
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.sepet.length > 0
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            // Satir tasima (▲/▼) sutununun basligi -- bos, sadece
                            // sepet satirlariyla hizayi korumak icin.
                            Label { text: ""; Layout.preferredWidth: 18 }
                            Label { text: "KOD"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 60 }
                            Label { text: "AÇIKLAMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                            Label { text: "ADET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "MALİYET " + root.paraBirimiSembol(paraBirimiCombo.currentText); color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignLeft }
                            Label { text: "FİYAT " + root.paraBirimiSembol(paraBirimiCombo.currentText); color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignLeft }
                            Label { text: "İNDİRİMLİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 96; horizontalAlignment: Text.AlignLeft }
                            Label { text: "TOPLAM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 112; horizontalAlignment: Text.AlignLeft }
                            // Satir bazli uretim takibi sutunu (✓ kutusu + not
                            // butonu); yalnizca kayitli teklif acikken gorunur.
                            Label {
                                visible: root.uretimTakibiGorunur
                                text: "ÜRETİM"
                                color: Theme.metinCokSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                Layout.preferredWidth: 62
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Label { text: ""; Layout.preferredWidth: 24 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.kenarlik
                        }
                    }

                    ListView {
                        id: sepetListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        reuseItems: false
                        model: root.sepet

                        readonly property int satirYuksekligi: 56
                        readonly property int satirAraligi: satirYuksekligi + spacing

                        // Surukleme sirasinda imlecin liste icindeki dikey konumu
                        // (gorunum koordinati) ve kenara yaklasinca isleyen otomatik
                        // kaydirmanin yonu (-1 yukari, +1 asagi, 0 kapali).
                        property real suruklemeGorunumY: 0
                        property int suruklemeKaydirmaYonu: 0

                        // Imlecin altinda kalan ARALIGI bulur: 0 = ilk satirin ustu,
                        // n = n'inci satirin ustu, uzunluk = listenin sonu.
                        function suruklemeHedefiniGuncelle(gorunumY) {
                            sepetListesi.suruklemeGorunumY = gorunumY
                            const icerikY = gorunumY + sepetListesi.contentY
                            const aralik = Math.round(icerikY / sepetListesi.satirAraligi)
                            root.suruklemeHedefIndex = Math.max(0, Math.min(root.sepet.length, aralik))
                            sepetListesi.suruklemeKaydirmaYonu =
                                gorunumY < 24 ? -1
                                : (gorunumY > sepetListesi.height - 24 ? 1 : 0)
                        }

                        function suruklemeyiBitir(uygula) {
                            if (uygula && root.suruklenenIndex !== -1 && root.suruklemeHedefIndex !== -1)
                                root.sepetSiraTasi(root.suruklenenIndex, root.suruklemeHedefIndex)
                            root.suruklenenIndex = -1
                            root.suruklemeHedefIndex = -1
                            sepetListesi.suruklemeKaydirmaYonu = 0
                        }

                        // Uzun sepetlerde satiri listenin gorunmeyen kismina tasiyabilmek
                        // icin, imlec kenara yaklastiginda liste kendiliginden kayar.
                        Timer {
                            interval: 16
                            repeat: true
                            running: root.suruklenenIndex !== -1 && sepetListesi.suruklemeKaydirmaYonu !== 0
                            onTriggered: {
                                const enFazla = Math.max(0, sepetListesi.contentHeight - sepetListesi.height)
                                const yeniY = Math.max(0, Math.min(enFazla,
                                    sepetListesi.contentY + sepetListesi.suruklemeKaydirmaYonu * 8))
                                if (yeniY === sepetListesi.contentY)
                                    return
                                sepetListesi.contentY = yeniY
                                sepetListesi.suruklemeHedefiniGuncelle(sepetListesi.suruklemeGorunumY)
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: root.sepet.length === 0
                            text: "Sepet boş. Soldan ürün seçerek ekleyin."
                            color: Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                        }

                        // Bkz. urun listesi delegate'i: layer icerigi item sinirina
                        // kirptigi icin cerceve 1px iceri alinmis cocuk Rectangle'da.
                        delegate: Item {
                            id: sepetSatiri
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            height: sepetListesi.satirYuksekligi
                            layer.enabled: true
                            layer.smooth: true

                            // Suruklenen satir "kalkmis" gorunur; birakilacagi yer
                            // asagidaki ince cizgi ile gosterilir.
                            readonly property bool suruklenenSatir: root.suruklenenIndex === sepetSatiri.index
                            opacity: suruklenenSatir ? 0.4 : 1

                            // Birakma gostergesi: satirin ustunde (hedef aralik bu
                            // satirsa) veya son satirin altinda (hedef listenin sonu).
                            // Kalemin zaten bulundugu araliklarda gosterilmez.
                            readonly property bool hedefGostergesiUstte:
                                root.suruklenenIndex !== -1
                                && root.suruklemeHedefIndex === sepetSatiri.index
                                && root.suruklemeHedefIndex !== root.suruklenenIndex
                                && root.suruklemeHedefIndex !== root.suruklenenIndex + 1
                            readonly property bool hedefGostergesiAltta:
                                root.suruklenenIndex !== -1
                                && sepetSatiri.index === root.sepet.length - 1
                                && root.suruklemeHedefIndex === root.sepet.length
                                && root.suruklenenIndex !== root.sepet.length - 1

                            Rectangle {
                                width: parent.width
                                height: 2
                                radius: 1
                                color: Theme.vurguAcik
                                visible: sepetSatiri.hedefGostergesiUstte || sepetSatiri.hedefGostergesiAltta
                                // layer icerigi item sinirina kirptigi icin gosterge
                                // satirin disina degil, tam kenarina cizilir.
                                y: sepetSatiri.hedefGostergesiAltta ? sepetSatiri.height - 2 : 0
                                z: 5
                            }

                            Rectangle {
                                id: sepetSatiriCerceve
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Theme.radiusKucuk
                                color: satirAlani.containsMouse ? Theme.panelHover : (sepetSatiri.index % 2 === 0 ? Theme.arkaplanIkincil : Theme.panel)
                                border.width: 1
                                border.color: satirAlani.containsMouse ? Theme.kenarlikVurgu : Theme.kenarlik
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                z: -1
                            }

                            readonly property real birimIndirimli: sepetSatiri.modelData.birimFiyatTl * (1 - root.indirimOrani / 100)
                            readonly property real satirToplamTl: birimIndirimli * sepetSatiri.modelData.adet

                            MouseArea {
                                id: satirAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                z: -1
                            }

                            RowLayout {
                                // NOT: "enabled" satirin TAMAMINA degil, tek tek
                                // ticari alanlara (adet/maliyet/fiyat/sil/siralama)
                                // veriliyor. Satirin uretim takibi (✓ kutusu ve
                                // kalem notu) kilitli teklifte de calismali:
                                // uretim zaten teklif KABUL EDILDIKTEN sonra
                                // basliyor, yani o alanlar yalnizca teklif
                                // "Tamamlandı"ya gecince kilitlenir (bkz.
                                // uretimAlaniKilitli).
                                anchors.fill: sepetSatiriCerceve
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8

                                // ---- Siralama tutamagi ----
                                // Teklif PDF'indeki kalem sirasi sepetteki sira ile
                                // ayni oldugu icin musterinin istedigi siralama
                                // burada, satiri tutamagindan surukleyerek ayarlanir.
                                // Surukleme sadece tutamaktan baslar; satirin geri
                                // kalani adet/fiyat duzenlemesi icin serbest kalir.
                                Rectangle {
                                    id: suruklemeTutamagi
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 34
                                    radius: Theme.radiusKucuk
                                    opacity: root.formKilitli ? 0 : 1
                                    color: (tutamakAlani.containsMouse || sepetSatiri.suruklenenSatir)
                                        ? Theme.panelHover : "transparent"

                                    // Tutamak deseni: iki sutun x uc nokta.
                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2
                                        rowSpacing: 3
                                        columnSpacing: 3
                                        Repeater {
                                            model: 6
                                            Rectangle {
                                                width: 3
                                                height: 3
                                                radius: 1.5
                                                color: tutamakAlani.containsMouse ? Theme.vurguAcik : Theme.metinCokSoluk
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: tutamakAlani
                                        enabled: !root.formKilitli
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: sepetSatiri.suruklenenSatir ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        // Liste kaydirmasi (Flickable) suruklemeyi calmasin.
                                        preventStealing: true

                                        function hedefiGuncelle(fareY) {
                                            const nokta = tutamakAlani.mapToItem(sepetListesi, 0, fareY)
                                            sepetListesi.suruklemeHedefiniGuncelle(nokta.y)
                                        }

                                        onPressed: (fare) => {
                                            root.suruklenenIndex = sepetSatiri.index
                                            hedefiGuncelle(fare.y)
                                        }
                                        onPositionChanged: (fare) => {
                                            if (root.suruklenenIndex !== -1)
                                                hedefiGuncelle(fare.y)
                                        }
                                        onReleased: sepetListesi.suruklemeyiBitir(true)
                                        onCanceled: sepetListesi.suruklemeyiBitir(false)
                                    }

                                    ToolTip.visible: tutamakAlani.containsMouse && root.suruklenenIndex === -1
                                    ToolTip.text: "Sürükleyerek sırayı değiştir"
                                    ToolTip.delay: 400
                                }

                                Rectangle {
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 22
                                    radius: Theme.radiusKucuk
                                    color: Theme.panelVurgu
                                    border.width: 1
                                    border.color: Theme.kenarlik
                                    Label {
                                        anchors.centerIn: parent
                                        text: sepetSatiri.modelData.urunKodu || "MANUEL"
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                Label {
                                    text: root.kalemAciklamasi(sepetSatiri.modelData)
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    Layout.minimumWidth: 0
                                }

                                SpinBox {
                                    id: adetSpin
                                    enabled: !root.formKilitli
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 30
                                    from: 1
                                    to: 99999
                                    value: sepetSatiri.modelData.adet
                                    editable: true
                                    onValueModified: root.sepetAlaniGuncelle(sepetSatiri.index, "adet", value)

                                    background: Rectangle {
                                        radius: Theme.radiusKucuk
                                        color: Theme.arkaplan
                                        border.width: 1
                                        border.color: adetSpin.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                    }
                                    contentItem: TextInput {
                                        text: adetSpin.textFromValue(adetSpin.value, adetSpin.locale)
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 11
                                        color: Theme.metinBirincil
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        readOnly: !adetSpin.editable
                                        validator: adetSpin.validator
                                        selectByMouse: true
                                    }
                                    up.indicator: Item {}
                                    down.indicator: Item {}
                                }

                                SepetSayiAlani {
                                    enabled: !root.formKilitli
                                    Layout.preferredWidth: 80
                                    deger: root.tlDenCevir(sepetSatiri.modelData.maliyet)
                                    onDegisti: (yeniDeger) => root.sepetTutarGuncelle(sepetSatiri.index, "maliyet", yeniDeger)
                                }

                                SepetSayiAlani {
                                    enabled: !root.formKilitli
                                    Layout.preferredWidth: 80
                                    deger: root.tlDenCevir(sepetSatiri.modelData.birimFiyatTl)
                                    onDegisti: (yeniDeger) => root.sepetTutarGuncelle(sepetSatiri.index, "birimFiyatTl", yeniDeger)
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.birimIndirimli)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.metinIkincil
                                    font.family: "Consolas"
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 96
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.satirToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.vurguAcik
                                    font.family: "Consolas"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 112
                                }

                                // ---- Satir bazli uretim takibi ----
                                // Solda "üretimi tamamlandı" kutusu, sagda o
                                // kaleme ozel uretim notu butonu. Ikisi de teklif
                                // "Tamamlandı"ya gecince kilitlenir; kabul edilmis
                                // teklifte serbesttir (uretim o asamada yapilir).
                                RowLayout {
                                    id: uretimHucresi
                                    visible: root.uretimTakibiGorunur
                                    // Bilincli olarak "enabled: false" YAPILMAZ:
                                    // tamamlanmis teklifte de kalem notu okunabilmeli
                                    // (pencere salt-okunur acilir) ve ipucunda
                                    // gorunebilmeli. DEGISTIRME engeli hem
                                    // kalemTamamlandiAyarla/kalemUretimNotunuKaydet
                                    // icinde hem de C++ tarafinda uygulanir.
                                    Layout.preferredWidth: 62
                                    spacing: 4

                                    readonly property bool tamamlandi: sepetSatiri.modelData.tamamlandi === true
                                    readonly property string kalemNotu: sepetSatiri.modelData.uretimNotu || ""

                                    Rectangle {
                                        id: tamamlandiKutusu
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        radius: Theme.radiusKucuk
                                        color: uretimHucresi.tamamlandi
                                            ? Theme.basari
                                            : (tamamlandiAlani.containsMouse ? Theme.panelHover : "transparent")
                                        border.width: 1
                                        border.color: uretimHucresi.tamamlandi ? Theme.basari : Theme.kenarlik
                                        opacity: root.uretimAlaniKilitli ? 0.55 : 1
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Label {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: uretimHucresi.tamamlandi ? "#ffffff" : Theme.metinCokSoluk
                                            font.pixelSize: 13
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: tamamlandiAlani
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: root.uretimAlaniKilitli
                                                ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: root.kalemTamamlandiAyarla(sepetSatiri.index,
                                                                                  !uretimHucresi.tamamlandi)
                                        }

                                        ToolTip.visible: tamamlandiAlani.containsMouse
                                        ToolTip.delay: 400
                                        ToolTip.text: root.uretimAlaniKilitli
                                            ? "Teklif tamamlandı; üretim durumu değiştirilemez."
                                            : (uretimHucresi.tamamlandi
                                               ? "Bu ürünün üretimi tamamlandı (kaldırmak için tıklayın)."
                                               : "Bu ürünün üretimi tamamlandı olarak işaretle.")
                                    }

                                    Rectangle {
                                        id: kalemNotButonu
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        radius: Theme.radiusKucuk
                                        color: kalemNotAlani.containsMouse ? Theme.panelHover : "transparent"
                                        border.width: 1
                                        // Notu olan satir kenarliktan belli olur:
                                        // pencereyi acmadan hangi urunde not oldugu gorulur.
                                        border.color: uretimHucresi.kalemNotu.trim().length > 0
                                            ? Theme.uyari : Theme.kenarlik

                                        Label {
                                            anchors.centerIn: parent
                                            text: "🗒"
                                            color: Theme.metinIkincil
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: kalemNotAlani
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: kalemUretimNotuDialogu.ac(sepetSatiri.index)
                                        }

                                        ToolTip.visible: kalemNotAlani.containsMouse
                                        ToolTip.delay: 400
                                        ToolTip.text: uretimHucresi.kalemNotu.trim().length > 0
                                            ? uretimHucresi.kalemNotu
                                            : (root.uretimAlaniKilitli
                                               ? "Bu ürün için üretim notu girilmemiş."
                                               : "Bu ürüne özel üretim notu ekle.")
                                    }
                                }

                                Rectangle {
                                    id: silButonu
                                    opacity: root.formKilitli ? 0 : 1
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    radius: Theme.radiusKucuk
                                    color: silAlani.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.15) : "transparent"

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: Theme.tehlikeAcik
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: silAlani
                                        // Buton kilitli teklifte gorunmez (opacity 0)
                                        // olsa da tiklanabilir kalmamali.
                                        enabled: !root.formKilitli
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.sepettenCikar(sepetSatiri.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Doviz kuru bilgi karti ----
        // Varsayilan: kompakt, salt-okunur "USD: .. TL  EUR: .. TL" gosterimi,
        // ekran acilir acilmaz (veya TL disi bir para birimi ilk secildiginde)
        // otomatik cekilir. Kullanici sadece istisnai durumlarda (ozel bir kur
        // girmek istediginde) kalem simgesiyle elle-giris moduna gecebilir.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.kurElleDuzenleModu ? 92 : 52
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik
            // Kilitli teklifte kur, teklifin kaydedildigi andaki degerdir; guncellenemez.
            enabled: !root.formKilitli
            visible: paraBirimiCombo.currentText !== "TL"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                // --- Kompakt, salt-okunur gorunum (varsayilan) ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    visible: !root.kurElleDuzenleModu

                    Label {
                        text: root.kurCekiliyor
                              ? "Kur çekiliyor…"
                              : (root.usdKur > 0 || root.eurKur > 0)
                                ? "USD: " + root.paraFormat(root.usdKur) + " ₺" + "      " +
                                  "EUR: " + root.paraFormat(root.eurKur) + " ₺"
                                : "Kur bilgisi yok"
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        font.bold: true
                    }

                    Label {
                        text: root.kurMesaji
                        visible: text.length > 0
                        color: root.kurMesajiHata ? Theme.tehlikeAcik : Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.italic: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                    }

                    Item { Layout.fillWidth: true; visible: root.kurMesaji.length === 0 }

                    Label {
                        text: root.kurCekiliyor ? "Çekiliyor…" : "Kuru Güncelle"
                        color: kurGuncelleAlani.containsMouse ? Theme.vurguHover : Theme.vurguAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: 11
                        font.underline: kurGuncelleAlani.containsMouse
                        MouseArea {
                            id: kurGuncelleAlani
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.kurCekiliyor
                            onClicked: root.guncelKuruCek()
                        }
                    }

                    Label {
                        text: "✎ Elle düzenle"
                        color: kurElleAlani.containsMouse ? Theme.vurguHover : Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 11
                        MouseArea {
                            id: kurElleAlani
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.usdKur > 0) usdKurBicimi.ayarla(root.usdKur); else usdKurBicimi.temizle()
                                if (root.eurKur > 0) eurKurBicimi.ayarla(root.eurKur); else eurKurBicimi.temizle()
                                root.kurElleDuzenleModu = true
                            }
                        }
                    }
                }

                // --- Elle duzenleme modu (istisnai kullanim) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.kurElleDuzenleModu

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            spacing: 2
                            Label { text: "1 USD KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                            Rectangle {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 30
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik
                                TextField {
                                    id: usdKurAlani
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    background: null
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    verticalAlignment: TextInput.AlignVCenter

                                    SayiBicimlendirici {
                                        id: usdKurBicimi
                                        ondalik: 4
                                        onDegerChanged: root.usdKur = deger
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Label { text: "1 EUR KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                            Rectangle {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 30
                                radius: Theme.radiusKucuk
                                color: Theme.arkaplan
                                border.width: 1
                                border.color: Theme.kenarlik
                                TextField {
                                    id: eurKurAlani
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    background: null
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    verticalAlignment: TextInput.AlignVCenter

                                    SayiBicimlendirici {
                                        id: eurKurBicimi
                                        ondalik: 4
                                        onDegerChanged: root.eurKur = deger
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: "Otomatik görünüme dön"
                            color: kurKapatAlani.containsMouse ? Theme.vurguHover : Theme.vurguAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignBottom
                            MouseArea {
                                id: kurKapatAlani
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.kurElleDuzenleModu = false
                            }
                        }
                    }

                    Label {
                        text: root.kurMesaji.length > 0
                              ? root.kurMesaji
                              : "Kur elle girildi; toplamlar bu değerlere göre hesaplanacak."
                        color: root.kurMesajiHata ? Theme.tehlike : Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.italic: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            // Metrikler tek satira sigmayip alt satira kaydiginda cubuk da
            // birlikte uzar; en az 60 px.
            Layout.preferredHeight: Math.max(60, ozetMetrikleri.implicitHeight + 16)
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                // Butonlar (butonGrubu) bu RowLayout disinda, parent'a sag
                // kenardan sabit anchor ile yerlestirildigi icin bu grup
                // butonGrubu.left'e kadar uzaniyor -- ozet/genel toplam
                // genisligi degistikce (rakamlar buyudukce) butonlar asla
                // hareket etmiyor, sadece bu grup gerekirse sikisiyor.
                anchors.left: parent.left
                anchors.right: butonGrubu.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 18
                clip: true

                // Ozet metrikleri: yer yettikce tek satirda yan yana; rakamlar
                // buyuyup sigmadiginda kalanlar alt satira kayar (Genel Toplam
                // kutusu hic sikismaz).
                Flow {
                    id: ozetMetrikleri
                    spacing: 20
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: implicitHeight

                    Ozet { baslik: "Toplam Maliyet"; deger: root.paraFormat(root.tlDenCevir(root.toplamMaliyetTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Kar Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.karTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText); renk: Theme.basariAcik }
                    Ozet { baslik: "Kar Oranı"; deger: root.paraFormat(root.karOrani) + " %"; renk: Theme.basariAcik }
                    Ozet { baslik: "Toplam Fiyat"; deger: root.paraFormat(root.tlDenCevir(root.indirimliToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "KDV Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.kdvTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Taşıma Ücreti"; deger: root.paraFormat(root.tlDenCevir(root.tasimaUcretiTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Paketleme Ücreti"; deger: root.paraFormat(root.tlDenCevir(root.paketlemeUcretiTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                }

                // Genel Toplam: ekrandaki en kritik rakam oldugu icin diger ozet
                // metriklerinden ayri, vurgulu bir kutuda gosterilir -- ama artik
                // etiket+deger yan yana tek satirda, cubugun tam yuksekligine sigacak sekilde.
                Rectangle {
                    // Sabit genislik yerine icerige gore hesaplanan genislik: rakam
                    // buyudukce (ornegin 25.299.019,20 ₺ gibi) kutu tasmadan otomatik genisler.
                    Layout.preferredWidth: genelToplamIcerik.implicitWidth + 32
                    Layout.minimumWidth: genelToplamIcerik.implicitWidth + 32
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignVCenter
                    radius: Theme.radiusNormal
                    color: Theme.vurguZeminSoluk
                    border.width: 1
                    border.color: Theme.kenarlikVurguSoluk

                    RowLayout {
                        id: genelToplamIcerik
                        anchors.centerIn: parent
                        spacing: 8
                        Label {
                            text: "GENEL TOPLAM"
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1
                        }
                        Label {
                            text: root.paraFormat(root.tlDenCevir(root.genelToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                            color: Theme.vurguAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutBaslik
                            font.bold: true
                        }
                    }
                }
            }

            // Butonlar: alt alta degil yan yana -- cubuk yuksekligini artirmadan sigsin.
            // Sag kenara sabit anchor ile yerlestirilir; solundaki grup (ozet +
            // genel toplam) genisligi degistikce bu grup asla kaymaz.
            RowLayout {
                id: butonGrubu
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                    Button {
                        id: sozlesmeButonu
                        text: "Satış Sözleşmesi"
                        Layout.preferredWidth: 138
                        Layout.preferredHeight: 40
                        // Teklif PDF'inin son sayfasindaki sozlesme maddelerini
                        // goruntuleyip duzenleme penceresini acar. Musteri/sepet
                        // sarti YOK -- sozlesme metni tekliften bagimsiz olarak
                        // her an okunup degistirilebilir.
                        onClicked: root.sozlesmeDuzenleyiciyiAc()
                        background: Rectangle {
                            radius: Theme.radiusKucuk
                            color: sozlesmeButonu.hovered ? Theme.panelHover : "transparent"
                            border.width: 1
                            border.color: sozlesmeButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                        }
                        contentItem: Text {
                            text: "Satış Sözleşmesi"
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        id: kaydetButonu
                        text: "Teklifi Kaydet"
                        // Kabul edilmis / tamamlanmis teklif yalnizca Giden Tekliflerim'den revize edilebilir.
                        visible: !root.formKilitli
                        Layout.preferredWidth: 138
                        Layout.preferredHeight: 40
                        onClicked: {
                            if (root.secilenMusteriId <= 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Lütfen önce bir müşteri seçin."
                                return
                            }
                            if (root.sepet.length === 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Sepette en az bir ürün olmalı."
                                return
                            }
                            // Kur yokken kaydedilirse TL tutarlar USD/EUR etiketiyle
                            // (kur=1) yazilirdi -- teklif tamamen yanlis olurdu.
                            if (root.kurEksik) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = paraBirimiCombo.currentText + " kuru alınamadı. Kuru güncelleyin veya elle girin."
                                return
                            }

                            const revizyonMuydu = root.duzenlenenAnaTeklifId > 0
                            const kopyaMiydi = root.kopyaModu
                            const kopyaKaynagi = root.kopyaKaynakTeklifId
                            const sonuc = database.teklifKaydet(root.teklifVerisiOlustur())
                            if (sonuc.basarili) {
                                bilgiMesaji.color = Theme.basariAcik
                                const onEk = revizyonMuydu
                                    ? "Teklif #" + sonuc.teklifId + " (Teklif #" + root.duzenlenenKaynakTeklifId + " revizyonu) kaydedildi. "
                                    : kopyaMiydi
                                    ? "Teklif #" + sonuc.teklifId + " (Teklif #" + kopyaKaynagi + " kopyası) kaydedildi. "
                                    : "Teklif #" + sonuc.teklifId + " kaydedildi. "
                                bilgiMesaji.text = onEk + "PDF hazırlanıyor..."

                                const pdfSonuc = database.teklifPdfOlustur(sonuc.teklifId)
                                if (pdfSonuc.basarili) {
                                    bilgiMesaji.text = onEk + "PDF: " + pdfSonuc.dosyaYolu
                                    Qt.openUrlExternally("file:///" + pdfSonuc.dosyaYolu)
                                } else {
                                    bilgiMesaji.text = onEk + "ancak PDF oluşturulamadı: " + pdfSonuc.hata
                                }

                                if (revizyonMuydu) {
                                    // Revizyon akisi: formu tamamen bosaltip gelinen
                                    // listeye geri don (SatisModuluPage dinliyor).
                                    const kaynakTeklifId = root.duzenlenenKaynakTeklifId
                                    root.duzenlemeyiIptalEt()
                                    root.revizyonKaydedildi(sonuc.teklifId, kaynakTeklifId,
                                                            sonuc.revizeEdilenTeklifIdler || [])
                                } else if (kopyaMiydi) {
                                    // Kopya akisi da bir ALT SAYFA'da yasar: formu
                                    // bosaltip gelinen listeye donuyoruz. Kaynak
                                    // teklifte hicbir degisiklik olmadigi icin
                                    // "revize edildi" bilgisi gonderilmez.
                                    root.duzenlemeyiIptalEt()
                                    root.kopyaKaydedildi(sonuc.teklifId, kopyaKaynagi)
                                } else {
                                    root.sepet = []
                                    root.secilenMusteriId = 0
                                    root.secilenFirmaAdi = ""
                                    ilgiliKisiAlani.text = ""
                                    ilgiliKisiTelAlani.text = ""
                                    ilgiliKisiEpostaAlani.text = ""
                                    // Tarih ve not teklife ozeldir; sonraki teklife tasinmaz.
                                    root.teslimatTarihi = ""
                                    root.musteriNotu = ""
                                    root.uretimNotu = ""
                                }
                            } else {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = sonuc.hata
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusKucuk
                            color: kaydetButonu.hovered ? Theme.vurguHover : Theme.vurgu
                        }
                        contentItem: Text {
                            text: "Teklifi Kaydet"
                            color: "#ffffff"
                            font.family: Theme.fontAilesi
                            font.bold: true
                            font.pixelSize: Theme.fontBoyutKucuk
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

    // ---- Satis sozlesmesi duzenleme penceresi ----
    // "Satış Sözleşmesi" butonu bunu acar; PDF'in son sayfasindaki maddeler
    // burada goruntulenip degistirilir (bkz. components/SozlesmeDuzenleDialog.qml).
    SozlesmeDuzenleDialog {
        id: sozlesmeDialogu
        saltOkunur: root.formKilitli

        onKaydedildi: function(yeniMetin) {
            if (root.formKilitli)
                return
            // Varsayilanla ayni metni "ozel metin" olarak saklamanin anlami yok:
            // bos birakirsak teklif, varsayilan metne bagli kalir (varsayilan
            // ileride degisirse bu teklif de guncel metni alir).
            const temiz = yeniMetin.trim()
            root.sozlesmeMetni = (temiz === sozlesmeDialogu.varsayilanMetin.trim()) ? "" : temiz

            // Kayitli bir teklif aciksa (Giden Tekliflerim -> Detay) metni hemen
            // o teklife yaziyoruz; boylece listedeki "PDF" butonu da degisen
            // sozlesmeyi basar. Kaydedilmemis yeni teklifte ise metin ekranda
            // bekler ve "Teklifi Kaydet" ile teklifle birlikte kaydedilir.
            if (root.duzenlenenKaynakTeklifId > 0 && !root.teklifKilitli) {
                const yazildi = database.teklifSozlesmeMetniKaydet(root.duzenlenenKaynakTeklifId,
                                                                    root.sozlesmeMetni)
                if (yazildi) {
                    bilgiMesaji.color = Theme.basariAcik
                    bilgiMesaji.text = "Teklif #" + root.duzenlenenKaynakTeklifId
                                       + " satış sözleşmesi güncellendi."
                } else {
                    bilgiMesaji.color = Theme.tehlikeAcik
                    bilgiMesaji.text = "Satış sözleşmesi kaydedilemedi."
                }
                return
            }

            bilgiMesaji.color = Theme.basariAcik
            bilgiMesaji.text = root.teklifKilitli
                ? "Satış sözleşmesi güncellendi; \"Teklifi Kaydet\" ile yeni revizyona yazılacak."
                : "Satış sözleşmesi bu teklif için güncellendi; teklifi kaydedince PDF'e yazılacak."
        }
    }

    // ---- Teklif notu / uretim notu pencereleri ----
    // Baslik satirindaki not butonlari bunlari acar (bkz. components/NotDuzenleDialog.qml).
    NotDuzenleDialog {
        id: musteriNotuDialogu
        baslik: (root.duzenlenenKaynakTeklifId > 0 ? "Teklif #" + root.duzenlenenKaynakTeklifId + " — " : "") + "Teklif Notu"
        bilgi: "Büro ve satış personeli için iç not. Teklif PDF'ine ve üretim PDF'ine basılmaz."
        yerTutucu: "Müşteriyle görüşme, fiyat, takip vb. iç notlar..."
        renk: Theme.vurgu
        metin: root.musteriNotu
        saltOkunur: root.formKilitli
        onKaydedildi: function(yeniMetin) { root.musteriNotunuKaydet(yeniMetin) }
    }

    NotDuzenleDialog {
        id: uretimNotuDialogu
        baslik: (root.duzenlenenKaynakTeklifId > 0 ? "Teklif #" + root.duzenlenenKaynakTeklifId + " — " : "") + "Üretim Notu"
        bilgi: "Üretim personeli için not. Üretim PDF'ine basılır."
        yerTutucu: "Ölçü, malzeme, paketleme, öncelik vb. üretime iletilecek notlar..."
        renk: Theme.basari
        metin: root.uretimNotu
        saltOkunur: root.uretimAlaniKilitli
        onKaydedildi: function(yeniMetin) { root.uretimNotunuKaydet(yeniMetin) }
    }

    // ---- Sepet satirina ozel uretim notu penceresi ----
    // Teklifin GENEL uretim notundan ayridir: bu not yalnizca tek bir urune
    // aittir ve uretim formunda o urunun satirinin altinda basilir. Tek bir
    // pencere tum satirlar icin kullanilir; hangi satirin duzenlendigi
    // ac() ile verilen dizinIndex'te tutulur.
    NotDuzenleDialog {
        id: kalemUretimNotuDialogu

        // Pencere acilirken sabitlenir: sepet dizisi (siralama, silme) pencere
        // acikken degisse bile not, acildigi satira yazilir.
        property int dizinIndex: -1
        property string kalemEtiketi: ""

        function ac(index) {
            const kalem = root.sepet[index]
            if (!kalem)
                return
            kalemUretimNotuDialogu.dizinIndex = index
            kalemUretimNotuDialogu.kalemEtiketi = (kalem.urunKodu || "MANUEL")
                + " — " + root.kalemAciklamasi(kalem)
            kalemUretimNotuDialogu.metin = kalem.uretimNotu || ""
            kalemUretimNotuDialogu.open()
        }

        baslik: "Ürün Üretim Notu"
        bilgi: kalemUretimNotuDialogu.kalemEtiketi
               + "\nSadece bu ürüne ait not; üretim PDF'inde bu ürünün satırının altına basılır."
        yerTutucu: "Bu ürüne özel ölçü, malzeme, renk, öncelik vb. notlar..."
        renk: Theme.uyari
        saltOkunur: root.uretimAlaniKilitli
        onKaydedildi: function(yeniMetin) {
            root.kalemUretimNotunuKaydet(kalemUretimNotuDialogu.dizinIndex, yeniMetin)
        }
    }

    // ---- Manuel urun ekleme dialogu ----
    // WPF'teki manuel urun ekleme penceresiyle ayni bilgi kumesini toplar
    // (kod, kategori, TR/EN aciklama, TL/USD/EUR birim fiyati, yurtici maliyet).
    // USD/EUR alanlari sadece kayit/gorsel amacli tutulur -- sepet hesaplari
    // (bkz. teklifVerisiOlustur) hala tek para biriminde (TL) calisir, WPF'ten
    // gocte alinan karar bu (UrunlerimPage.qml'deki ayni not).
    // "Kaydet" urunu kalici olarak urunler tablosuna ekler (bkz. kaydet()).
    Dialog {
        id: manuelUrunDialogu
        modal: true
        width: 560
        padding: 20
        anchors.centerIn: parent

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        header: Label {
            text: "Manuel Ürün Ekle"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
            padding: 20
        }

        onOpened: {
            manuelKod.text = ""
            manuelKategori.text = ""
            manuelAciklama.text = ""
            manuelAciklamaEn.text = ""
            manuelFiyatBicimi.temizle()
            manuelFiyatUsdBicimi.temizle()
            manuelFiyatEurBicimi.temizle()
            manuelMaliyetBicimi.temizle()
            manuelHataMesaji.text = ""
        }

        function kaydet() {
            if (manuelAciklama.text.trim().length === 0) {
                manuelHataMesaji.text = "Ürün açıklaması zorunludur."
                return
            }
            // Manuel urun once urunler tablosuna normal bir urun olarak kaydedilir
            // (UrunlerimPage ile ayni urunEkle) -- boylece katalogda kaydi kalir,
            // aramalarda bulunur ve sepete gercek UrunId'si ile eklenir.
            const urunKodu = manuelKod.text.trim()
            const birimFiyatTl = manuelFiyatBicimi.deger
            const maliyet = manuelMaliyetBicimi.deger
            const sonuc = database.urunEkle({
                urunKodu: urunKodu,
                kategori: manuelKategori.text.trim(),
                urunAciklamasi: manuelAciklama.text.trim(),
                urunAciklamasiEn: manuelAciklamaEn.text.trim(),
                birimFiyat: birimFiyatTl,
                maliyet: maliyet
            })
            if (!sonuc.basarili) {
                manuelHataMesaji.text = sonuc.hata
                return
            }
            root.sepeteEkle({
                urunId: sonuc.urunId,
                urunKodu: urunKodu,
                kategori: manuelKategori.text,
                aciklama: manuelAciklama.text,
                aciklamaTr: manuelAciklama.text,
                aciklamaEn: manuelAciklamaEn.text,
                adet: 1,
                birimFiyatTl: birimFiyatTl,
                birimFiyatUsd: manuelFiyatUsdBicimi.deger,
                birimFiyatEur: manuelFiyatEurBicimi.deger,
                maliyet: maliyet
            })
            manuelUrunDialogu.close()
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                id: manuelHataMesaji
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "ÜRÜN KODU"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelKod; placeholderText: "Örn: BTP-500" }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "KATEGORİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelKategori; placeholderText: "Örn: Basma-Eğilme Test Cihazları" }
                }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "ÜRÜN AÇIKLAMASI"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelAciklama; placeholderText: "Örn: Otomatik Beton Test Presi" }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "ÜRÜN AÇIKLAMASI (İNGİLİZCE)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelAciklamaEn; placeholderText: "Ex: Automatic Concrete Compression Test Press" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "BİRİM SATIŞ FİYATI (TL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyat; placeholderText: "0,00"; SayiBicimlendirici { id: manuelFiyatBicimi } }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "DOLAR BİRİM FİYATI (USD)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyatUsd; placeholderText: "0,00"; SayiBicimlendirici { id: manuelFiyatUsdBicimi } }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "EURO BİRİM FİYATI (EUR)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyatEur; placeholderText: "0,00"; SayiBicimlendirici { id: manuelFiyatEurBicimi } }
                }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "YURTİÇİ MALİYET BİRİM FİYATI (TL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelMaliyet; placeholderText: "0,00"; SayiBicimlendirici { id: manuelMaliyetBicimi } }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 6
                    text: "Kaydet"
                    onClicked: manuelUrunDialogu.kaydet()
                    background: Rectangle {
                        radius: Theme.radiusKucuk
                        color: parent.hovered ? Theme.vurguHover : Theme.vurgu
                    }
                    contentItem: Text {
                        text: "Kaydet"
                        color: "#ffffff"
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutKucuk
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 6
                    text: "İptal"
                    onClicked: manuelUrunDialogu.close()
                    background: Rectangle {
                        radius: Theme.radiusKucuk
                        color: parent.hovered ? Theme.tehlikeHover : Theme.tehlike
                    }
                    contentItem: Text {
                        text: "İptal"
                        color: "#ffffff"
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutKucuk
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
