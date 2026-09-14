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
    component TarihBasligi: Label {
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
        Text {
            width: root.sutunTarih
            text: parent.deger.length > 0 ? parent.deger.split(" ")[0] : "—"
            color: parent.deger.length > 0 ? Theme.metinIkincil : Theme.metinCokSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
            elide: Text.ElideRight
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

    readonly property int sayfaBoyutu: 50

    // --- Tablo sutun genislikleri -------------------------------------------
    // Baslik satiri ile veri satirlari AYNI degerleri kullanmak zorunda; bu yuzden
    // genislikler tek bir yerde tanimlanip iki tarafta da buradan okunur. Bir sutunu
    // genisletmek/daraltmak icin sadece asagidaki sayiyi degistirmek yeterli.
    // FIRMA ADI sutunu kalan tum alani kaplar (her iki tarafta da Layout.fillWidth).
    readonly property int sutunBosluk: 8
    readonly property int sutunKenarBosluk: 12
    // Teklif no + revizyon rozeti + not ikonu.
    readonly property int sutunTeklifNo: 96
    // Teklif / Kabul / Planlanan Teslim / Teslim / Uretim PDF tarihlerinin her biri.
    readonly property int sutunTarih: 80
    readonly property int sutunPersonel: 104
    // Durum rozeti artik tiklanabilir bir menu acicisi oldugu icin icinde bir de
    // "▾" isareti tasiyor; sutun ona gore bir miktar genisletildi.
    readonly property int sutunDurum: 126
    // Detay + PDF (+ Uretim) + Sil butonlari ve aralarindaki 6px bosluklar.
    readonly property int sutunIslemler: root.uretimButonuGoster ? 262 : 190
    // Aciklamalar sutunu yalnizca yer oldugunda gosterilir; dar ekranda Firma Adi
    // sutunu ezilmesin diye gizlenir (icerik yine satirin tooltip'inde okunur).
    readonly property bool aciklamaSutunuGoster: root.width >= 1360

    // "Üretim" (uretim PDF'i) butonu: siparis kesinlesmis teklifler icin anlamli
    // oldugundan Alınan ve Biten Tekliflerim'de gosterilir.
    readonly property bool uretimButonuGoster: root.durumFiltresi === "Kabul Edildi" || root.durumFiltresi === "Tamamlandı"

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

    // Menuden bir durum secildiginde cagrilir. "Reddedildi" secildiginde once red
    // sebebi sorulur, diger gecislerde kisa bir onay penceresi acilir -- zira bu
    // islem satiri bulundugu sekmeden tamamen dusurebilir (ornegin Alınan
    // Tekliflerim'deki bir teklif "Reddedildi" yapilinca artik o listede gorunmez).
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
        durumOnayDialogu.open()
    }

    // Asil guncelleme tek bir yerden gecer; boylece basari/hata mesaji ve listenin
    // yenilenmesi her cagri noktasinda tekrar yazilmak zorunda kalmaz.
    function durumUygula(teklifId, yeniDurum, redSebebi) {
        const basarili = database.teklifDurumGuncelle(teklifId, yeniDurum, redSebebi || "", root.kullaniciId)
        if (!basarili) {
            root.pdfMesaji = "Teklif #" + teklifId + " durumu güncellenemedi."
            root.pdfMesajiHata = true
            return
        }

        // Filtreli bir sekmedeysek (Alınan/Biten) ve yeni durum o filtreye uymuyorsa
        // satir bu listeden kaybolur; kullanici "kayboldu" sanmasin diye nerede
        // bulacagini soyluyoruz.
        var mesaj = "Teklif #" + teklifId + " durumu → " + yeniDurum
        if (root.durumFiltresi !== "" && root.durumFiltresi !== yeniDurum)
            mesaj += "  (bu teklif artık " + (yeniDurum === "Kabul Edildi" ? "Alınan Tekliflerim"
                                            : yeniDurum === "Tamamlandı" ? "Biten Tekliflerim"
                                            : "Giden Tekliflerim") + "'de)"
        root.pdfMesaji = mesaj
        root.pdfMesajiHata = false
        root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
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

    // Teknik ekip icin fiyatsiz uretim PDF'i. Basarili olursa teklifin "Üretim PDF"
    // tarihi dolar; bunun listede hemen gorunmesi icin sayfa yenilenir.
    function uretimPdfOlusturVeAc(teklifId) {
        const sonuc = database.uretimPdfOlustur(teklifId)
        if (sonuc.basarili) {
            root.pdfMesaji = "Teklif #" + teklifId + " üretim PDF: " + sonuc.dosyaYolu
            root.pdfMesajiHata = false
            Qt.openUrlExternally("file:///" + sonuc.dosyaYolu)
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        } else {
            root.pdfMesaji = "Teklif #" + teklifId + " için üretim PDF'i oluşturulamadı: " + sonuc.hata
            root.pdfMesajiHata = true
        }
    }

    // Aciklamalar sutunu: yalnizca gocten gelen sevk aciklamasi. Notlar burada metin
    // olarak yer kaplamaz; Teklif No hucresindeki not ikonuyla gosterilir.
    function aciklamaMetni(kayit) {
        return (kayit.aciklamalar || "").trim()
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
        notGoruntuleDialogu.baslik = "Teklif #" + kayit.teklifId + " — "
                                     + (root.teklifNotuSekmesi ? "Teklif Notu" : "Üretim Notu")
        notGoruntuleDialogu.metin = root.satirNotu(kayit)
        notGoruntuleDialogu.open()
    }

    // Kabul edilmis / tamamlanmis teklif kilitlidir: silinemez (bkz. Database::teklifKilitliMi).
    function teklifKilitliMi(durum) {
        return durum === "Kabul Edildi" || durum === "Tamamlandı"
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
                Label { text: "TEKLİF NO"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunTeklifNo; Layout.maximumWidth: root.sutunTeklifNo }
                Label { text: "FİRMA ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.fillWidth: true; Layout.horizontalStretchFactor: 2; Layout.preferredWidth: 0 }
                TarihBasligi { text: "TEKLİF TARİHİ" }
                TarihBasligi { text: "KABUL TARİHİ" }
                TarihBasligi { text: "PLANLANAN TESLİM" }
                TarihBasligi { text: "TESLİM TARİHİ" }
                TarihBasligi { text: "ÜRETİM PDF" }
                Label { text: "TEKLİFİ YAPAN"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunPersonel; Layout.maximumWidth: root.sutunPersonel }
                Label { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunDurum; Layout.maximumWidth: root.sutunDurum }
                Label { visible: root.aciklamaSutunuGoster; text: "AÇIKLAMALAR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.fillWidth: true; Layout.horizontalStretchFactor: 1; Layout.preferredWidth: 0 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; elide: Text.ElideRight; Layout.preferredWidth: root.sutunIslemler; Layout.maximumWidth: root.sutunIslemler }
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

                        Text {
                            text: satir.modelData.teklifId
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            verticalAlignment: Text.AlignVCenter
                            Layout.fillHeight: true
                        }

                        // Bu satir bir revizyonsa (RevizyonNo > 0) kucuk bir "R{n}"
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
                                text: "R" + satir.modelData.revizyonNo
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: 9
                                font.bold: true
                            }

                            ToolTip.visible: revRozetAlani.containsMouse
                            ToolTip.text: "Ana teklif: #" + satir.modelData.anaTeklifId
                            MouseArea {
                                id: revRozetAlani
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
                        Layout.horizontalStretchFactor: 2
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    // Teklif -> kabul -> planlanan teslim -> gercek teslim -> uretim PDF.
                    // Bos tarihler "—" ile gosterilir.
                    TarihHucresi { deger: satir.modelData.teklifTarihi }
                    TarihHucresi { deger: satir.modelData.kabulTarihi }
                    TarihHucresi { deger: satir.modelData.teslimatTarihi }
                    TarihHucresi { deger: satir.modelData.teslimTarihi }
                    TarihHucresi { deger: satir.modelData.uretimPdfTarihi }
                    Text {
                        text: satir.modelData.personelKullaniciAdi
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        Layout.preferredWidth: root.sutunPersonel
                        Layout.maximumWidth: root.sutunPersonel
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillHeight: true
                        elide: Text.ElideRight
                        clip: true
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

                            readonly property color durumRengi: {
                                const d = satir.modelData.durum
                                if (d === "Tamamlandı" || d === "Kabul Edildi") return Theme.basariAcik
                                if (d === "Beklemede") return Theme.vurguAcik
                                if (d === "Reddedildi") return Theme.tehlikeAcik
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

                            ToolTip.visible: durumAlani.containsMouse
                            ToolTip.text: satir.modelData.durum === "Reddedildi" && satir.modelData.redSebebi.length > 0
                                          ? "Red sebebi: " + satir.modelData.redSebebi + "\nDurumu değiştirmek için tıklayın"
                                          : "Durumu değiştirmek için tıklayın"
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

                                Instantiator {
                                    model: root.digerDurumlar(satir.modelData.durum)
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
                                    text: "Durum Geçmişi..."
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
                    Text {
                        id: aciklamaHucresi
                        visible: root.aciklamaSutunuGoster
                        text: root.aciklamaMetni(satir.modelData)
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk + 1
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.horizontalStretchFactor: 1
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight

                        ToolTip.visible: aciklamaAlani.containsMouse && aciklamaHucresi.truncated
                        ToolTip.text: aciklamaHucresi.text
                        ToolTip.delay: 400
                        MouseArea {
                            id: aciklamaAlani
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
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
                                          ? "Üretim PDF'i " + satir.modelData.uretimPdfTarihi + " tarihinde alındı; tekrar oluştur"
                                          : "Fiyatsız üretim PDF'i oluştur"
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

                        // Kabul edilmis / tamamlanmis teklifte gizli: kilitli teklif silinemez.
                        Button {
                            id: silButonu
                            visible: !root.teklifKilitliMi(satir.modelData.durum)
                            text: "Sil"
                            Layout.preferredWidth: Math.max(50, Math.ceil(silMetni.implicitWidth) + 20)
                            Layout.preferredHeight: root.hizalanmisYukseklik(Math.max(28, silMetni.implicitHeight + 10))
                            onClicked: silOnayDialogu.acilacakTeklifId = satir.modelData.teklifId
                            background: Rectangle {
                                radius: 5
                                color: silButonu.hovered ? "#3f1d24" : "transparent"
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

    // Satirdaki not ikonuna tiklaninca notun tam metnini salt okunur gosterir.
    // Not duzenleme "Detay" ekranindaki not butonlarindan yapilir.
    NotDuzenleDialog {
        id: notGoruntuleDialogu
        saltOkunur: true
        renk: root.teklifNotuSekmesi ? Theme.vurgu : Theme.basari
        bilgi: root.teklifNotuSekmesi
               ? "Büro ve satış personeli için iç not. PDF'lere basılmaz."
               : "Üretim personeli için not. Üretim PDF'ine basılır."
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
            if (!database.teklifSil(acilacakTeklifId)) {
                root.pdfMesaji = "Teklif #" + acilacakTeklifId + " silinemedi."
                root.pdfMesajiHata = true
            }
            acilacakTeklifId = -1
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        }
        onRejected: acilacakTeklifId = -1
    }

    // Durum degisikligi onayi. "Reddedildi" disindaki her gecis buradan gecer --
    // islem geri alinabilir olsa da satiri bulundugu sekmeden dusurebildigi icin
    // yanlislikla tiklanmaya karsi kisa bir onay istiyoruz.
    Dialog {
        id: durumOnayDialogu
        property int hedefTeklifId: -1
        property string eskiDurum: ""
        property string yeniDurum: ""
        title: "Durumu Değiştir"
        modal: true
        width: 380
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        contentItem: Label {
            text: "Teklif #" + durumOnayDialogu.hedefTeklifId + " durumu\n\""
                  + durumOnayDialogu.eskiDurum + "\" → \"" + durumOnayDialogu.yeniDurum
                  + "\"\n\nolarak değiştirilecek. Onaylıyor musunuz?"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            wrapMode: Text.WordWrap
            width: durumOnayDialogu.availableWidth
        }

        onAccepted: {
            root.durumUygula(durumOnayDialogu.hedefTeklifId, durumOnayDialogu.yeniDurum, "")
            durumOnayDialogu.hedefTeklifId = -1
        }
        onRejected: durumOnayDialogu.hedefTeklifId = -1
    }

    // Bir teklifin tum durum degisimleri (kim, ne zaman, hangi durumdan hangisine).
    // Durum ileri geri degisebildigi icin teklifler tablosundaki tarih alanlari her
    // seferinde ustune yazilir; degisimin izi burada kalir.
    Dialog {
        id: gecmisDialogu
        property int hedefTeklifId: -1
        property var kayitlar: []
        title: "Teklif #" + gecmisDialogu.hedefTeklifId + " - Durum Geçmişi"
        modal: true
        width: 480
        anchors.centerIn: parent
        standardButtons: Dialog.Close

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label {
                visible: gecmisDialogu.kayitlar.length === 0
                Layout.fillWidth: true
                text: "Bu teklif için kayıtlı durum değişikliği yok."
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }

            ListView {
                visible: gecmisDialogu.kayitlar.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, gecmisDialogu.kayitlar.length * 56)
                clip: true
                spacing: 4
                model: gecmisDialogu.kayitlar

                delegate: Rectangle {
                    id: gecmisSatiri
                    required property var modelData
                    width: ListView.view.width
                    height: 52
                    radius: Theme.radiusKucuk
                    color: Theme.arkaplan
                    border.width: 1
                    border.color: Theme.kenarlik

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            text: (gecmisSatiri.modelData.eskiDurum.length > 0 ? gecmisSatiri.modelData.eskiDurum : "—")
                                  + "  →  " + gecmisSatiri.modelData.yeniDurum
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                        }
                        Text {
                            text: gecmisSatiri.modelData.tarih
                                  + (gecmisSatiri.modelData.personel.length > 0 ? "  •  " + gecmisSatiri.modelData.personel : "")
                                  + (gecmisSatiri.modelData.aciklama.length > 0 ? "  •  " + gecmisSatiri.modelData.aciklama : "")
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }
            }
        }
    }

    // Reddetme sebebi (opsiyonel) girisi. Sadece "Beklemede" satirlarindan degil,
    // durum menusunden "Reddedildi" secildiginde de acilir -- yani kabul edilmis
    // ya da tamamlanmis bir teklif de sebebiyle birlikte reddedilebilir.
    Dialog {
        id: reddetDialogu
        property int hedefTeklifId: -1
        property string eskiDurum: ""
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
            root.durumUygula(reddetDialogu.hedefTeklifId, "Reddedildi", redSebebiGirisi.text)
            reddetDialogu.hedefTeklifId = -1
        }
        onRejected: reddetDialogu.hedefTeklifId = -1

        contentItem: ColumnLayout {
            spacing: 8
            Label {
                // Kabul edilmis/tamamlanmis bir teklif geri cekiliyorsa kullanici
                // hangi durumdan donduguunu gorsun.
                visible: reddetDialogu.eskiDurum.length > 0 && reddetDialogu.eskiDurum !== "Beklemede"
                text: "Bu teklif şu an \"" + reddetDialogu.eskiDurum + "\" durumunda; reddedilmiş olarak işaretlenecek."
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
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
