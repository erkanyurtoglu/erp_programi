import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// "Alınan/Biten Tekliflerim" listesindeki "İrsaliye" butonunun actigi pencere
// (WPF'teki SevkBilgileriWindow'un Qt/QML karsiligi).
//
// AMAC: Siparis kesinlestikten sonra netlesen sevk bilgileri -- faturanin ve
// irsaliyenin hangi baslik/adres/vergi bilgileriyle kesilecegi, siparis sartlari
// (KDV, garanti, teslimat, odeme, nakliye...) ve sevkiyat aciklamasi -- satis
// personeli ile buro personeli arasinda TEK bir yerde doldurulup sonradan yine
// buradan okunsun. Veri teklif basina tek kayittir (dbo.sevk_bilgileri).
//
// Pencere KENDISI KAYDETMEZ: "Kaydet"e basilinca alanlari tek bir harita halinde
// kaydedildi() sinyaliyle disari verir; veritabanina yazma isini acan ekran yapar
// (bkz. GecmisTekliflerPage.qml -> sevkBilgileriniKaydet).
Dialog {
    id: kok

    property int teklifId: 0
    property string firmaAdi: ""

    // Tamamlanmis teklifte sevk bilgileri kilitlidir (bkz.
    // Database::sevkBilgileriKaydet'teki kilit kurali): alanlar okunur ama
    // degistirilemez, "Kaydet" gizlenir.
    property bool saltOkunur: false

    // Database::sevkBilgileriGetir()'in dondugu harita; acan ekran her acilistan
    // once doldurur, onOpened bunu alanlara dagitir.
    property var veri: ({})

    // Kullanici "Kaydet"e bastiginda, alanlarin O ANKI degerleriyle yayinlanir.
    // Harita anahtarlari Database::sevkBilgileriGetir/Kaydet ile birebir aynidir.
    signal kaydedildi(var sevk)

    // --- Alan kaydi ---------------------------------------------------------
    // Pencerede 27 alan var; hepsini tek tek id ile doldurup toplamak yerine her
    // satir olusurken kendini "anahtar -> satir" olarak buraya yaziyor. Boylece
    // yukleme ve toplama tek dongude yapilir, yeni bir alan eklemek icin sadece
    // asagiya bir satir eklemek yeterli olur.
    property var alanlar: ({})

    // Bir alanin gosterilecek degeri. Hem satirlar ilk olustugunda (asagidaki
    // Component.onCompleted) hem de pencere yeniden acildiginda buradan okunur.
    function alanDegeri(anahtar) {
        return (kok.veri && kok.veri[anahtar] !== undefined) ? String(kok.veri[anahtar]) : ""
    }

    function degerleriYukle() {
        for (const anahtar in kok.alanlar)
            kok.alanlar[anahtar].deger = kok.alanDegeri(anahtar)
    }

    function degerleriTopla() {
        var sevk = ({})
        for (const anahtar in kok.alanlar)
            sevk[anahtar] = kok.alanlar[anahtar].deger
        return sevk
    }

    // "yyyy-MM-dd" (veritabani/takvim bicimi) -> "gg.aa.yyyy" (ekranda okunan bicim).
    function tarihiGoster(yyyyAaGg) {
        if (!yyyyAaGg || yyyyAaGg.length === 0)
            return ""
        const parcalar = yyyyAaGg.split("-")
        return parcalar.length === 3 ? parcalar[2] + "." + parcalar[1] + "." + parcalar[0] : yyyyAaGg
    }

    // --- Ortak satir bilesenleri --------------------------------------------
    // Etiket solda sabit genislikte, girdi sagda kalan alani kaplar -- boylece
    // uc bolumun butun satirlari ayni hizada baslar.
    component AlanSatiri: RowLayout {
        id: alanSatiri
        property string etiket: ""
        property string anahtar: ""
        // Sutun genisligi (bkz. db/01_yeni_veritabani_ve_sema.sql): fazlasi SQL
        // tarafinda hataya donusecegi icin girdi burada sinirlanir.
        property int maksUzunluk: 200
        property alias deger: girdi.text

        Layout.fillWidth: true
        spacing: 12
        // Satirlar Popup icerigi olduklari icin ILK acilista onOpened'dan SONRA
        // olusurlar; bu yuzden her satir kendi degerini olusurken de bir kez
        // ceker (sonraki acilislarda degerleriYukle() zaten hepsini tazeler).
        Component.onCompleted: {
            kok.alanlar[alanSatiri.anahtar] = alanSatiri
            alanSatiri.deger = kok.alanDegeri(alanSatiri.anahtar)
        }

        Label {
            text: alanSatiri.etiket
            color: Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.girdiYuksekligi
            radius: Theme.radiusKucuk
            color: kok.saltOkunur ? Theme.arkaplan : Theme.panelVurgu
            border.width: 1
            border.color: girdi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

            TextField {
                id: girdi
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                background: null
                readOnly: kok.saltOkunur
                maximumLength: alanSatiri.maksUzunluk
                color: Theme.metinBirincil
                placeholderTextColor: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
            }
        }
    }

    // Siparis tarihi: elle "yyyy-aa-gg" yazdirmak yerine listedeki tarih
    // filtreleriyle ayni takvimden secilir (TarihTakvimi).
    component TarihSatiri: RowLayout {
        id: tarihSatiri
        property string etiket: ""
        property string anahtar: ""
        // Her zaman "yyyy-MM-dd" (veya bos) tutulur; ekranda gg.aa.yyyy gorunur.
        property string deger: ""

        Layout.fillWidth: true
        spacing: 12
        Component.onCompleted: {
            kok.alanlar[tarihSatiri.anahtar] = tarihSatiri
            tarihSatiri.deger = kok.alanDegeri(tarihSatiri.anahtar)
        }

        Label {
            text: tarihSatiri.etiket
            color: Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.girdiYuksekligi
            radius: Theme.radiusKucuk
            color: kok.saltOkunur ? Theme.arkaplan : Theme.panelVurgu
            border.width: 1
            border.color: takvim.visible ? Theme.kenarlikVurgu : Theme.kenarlik

            Text {
                anchors.left: parent.left
                // Temizle isareti gizliyken metin sagdaki bosluga kadar uzanir;
                // isaretin genisligini "gorunurse implicitWidth" diye baglamak
                // Text'te binding dongusune yol aciyordu.
                anchors.right: temizleButonu.visible ? temizleButonu.left : parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                text: tarihSatiri.deger.length > 0 ? kok.tarihiGoster(tarihSatiri.deger) : "Tarih seçin"
                color: tarihSatiri.deger.length > 0 ? Theme.metinBirincil : Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                enabled: !kok.saltOkunur
                cursorShape: Qt.PointingHandCursor
                onClicked: takvim.open()
            }

            // Yanlis secilen tarihi geri almanin tek yolu: alani bosaltmak.
            Text {
                id: temizleButonu
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: tarihSatiri.deger.length > 0 && !kok.saltOkunur
                text: "✕"
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tarihSatiri.deger = ""
                }
            }

            TarihTakvimi {
                id: takvim
                y: parent.height + 4
                onTarihSecildi: (tarih) => tarihSatiri.deger = tarih
            }
        }
    }

    // Cok satirli serbest metin (AÇIKLAMALAR). Uzunluk siniri yoktur
    // (sutun NVARCHAR(MAX)).
    component MetinAlaniSatiri: Rectangle {
        id: metinSatiri
        property string anahtar: ""
        property alias deger: metinAlani.text

        Layout.fillWidth: true
        Layout.preferredHeight: 120
        radius: Theme.radiusKucuk
        color: kok.saltOkunur ? Theme.arkaplan : Theme.panelVurgu
        border.width: 1
        border.color: metinAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
        Component.onCompleted: {
            kok.alanlar[metinSatiri.anahtar] = metinSatiri
            metinSatiri.deger = kok.alanDegeri(metinSatiri.anahtar)
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 8
            clip: true

            TextArea {
                id: metinAlani
                background: null
                readOnly: kok.saltOkunur
                color: Theme.metinBirincil
                placeholderTextColor: Theme.metinCokSoluk
                placeholderText: kok.saltOkunur ? "" : "Sevkiyatla ilgili notlar; teklif listesindeki AÇIKLAMALAR sütununda görünür."
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                wrapMode: TextArea.Wrap
                selectByMouse: true
            }
        }
    }

    // Bolum kartı (FATURA / İRSALİYE / SİPARİŞ BİLGİLERİ). Yuksekligi icerikten
    // turetilir; ic layout kasitli olarak parent'a fill EDILMEZ, aksi halde
    // "yukseklik icerige, icerik yukseklige" baglanir ve binding dongusu olusur.
    component Bolum: Rectangle {
        id: bolum
        property string baslik: ""
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

            Label {
                text: bolum.baslik
                color: Theme.vurguAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                font.bold: true
                font.letterSpacing: 1
                Layout.bottomMargin: 4
            }
        }
    }

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 80 : 980, 980)
    height: Math.min(parent ? parent.height - 60 : 760, 760)
    padding: 20

    background: Rectangle {
        color: Theme.arkaplan
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    // Her acilista alanlar, acan ekranin verdigi veriyle bastan doldurulur --
    // onceki teklifin degerleri kesinlikle tasinmasin.
    onOpened: {
        kok.degerleriYukle()
        // Onceki teklifte asagi kaydirilmis olabilir; form hep en ustten baslasin.
        if (icerikGorunumu.contentItem)
            icerikGorunumu.contentItem.contentY = 0
    }

    header: ColumnLayout {
        spacing: 2

        Label {
            text: "🚚  Sevk ve İrsaliye Bilgileri"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
            Layout.leftMargin: 20
            Layout.topMargin: 20
        }

        Label {
            text: "Teklif #" + kok.teklifId
                  + (kok.firmaAdi.length > 0 ? "  •  " + kok.firmaAdi : "")
                  + (kok.saltOkunur ? "  •  tamamlanmış teklif, yalnızca görüntüleniyor" : "")
            color: kok.saltOkunur ? Theme.uyariAcik : Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
        }
    }

    contentItem: ColumnLayout {
        spacing: 12

        ScrollView {
            id: icerikGorunumu
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: icerikGorunumu.availableWidth
                spacing: 12

                Bolum {
                    baslik: "FATURA BİLGİLERİ"

                    AlanSatiri { etiket: "Fatura Başlığı";  anahtar: "faturaBasligi";      maksUzunluk: 200 }
                    AlanSatiri { etiket: "Fatura Adresi";   anahtar: "faturaAdresi";       maksUzunluk: 500 }
                    AlanSatiri { etiket: "Vergi Dairesi";   anahtar: "faturaVergiDairesi"; maksUzunluk: 150 }
                    AlanSatiri { etiket: "Vergi No";        anahtar: "faturaVergiNo";      maksUzunluk: 50 }
                    AlanSatiri { etiket: "Yetkili";         anahtar: "faturaYetkili";      maksUzunluk: 150 }
                    AlanSatiri { etiket: "Telefon";         anahtar: "faturaTelefon";      maksUzunluk: 50 }
                    AlanSatiri { etiket: "Fax";             anahtar: "faturaFax";          maksUzunluk: 50 }
                    AlanSatiri { etiket: "E-Posta";         anahtar: "faturaEposta";       maksUzunluk: 150 }
                }

                Bolum {
                    baslik: "İRSALİYE BİLGİLERİ"

                    AlanSatiri { etiket: "İrsaliye Başlığı"; anahtar: "irsaliyeBasligi";      maksUzunluk: 200 }
                    AlanSatiri { etiket: "İrsaliye Adresi";  anahtar: "irsaliyeAdresi";       maksUzunluk: 500 }
                    AlanSatiri { etiket: "Vergi Dairesi";    anahtar: "irsaliyeVergiDairesi"; maksUzunluk: 150 }
                    AlanSatiri { etiket: "Vergi No";         anahtar: "irsaliyeVergiNo";      maksUzunluk: 50 }
                    AlanSatiri { etiket: "Yetkili";          anahtar: "irsaliyeYetkili";      maksUzunluk: 150 }
                    AlanSatiri { etiket: "Telefon";          anahtar: "irsaliyeTelefon";      maksUzunluk: 50 }
                    AlanSatiri { etiket: "E-Posta";          anahtar: "irsaliyeEposta";       maksUzunluk: 150 }
                }

                Bolum {
                    baslik: "SİPARİŞ BİLGİLERİ"

                    AlanSatiri { etiket: "KDV";              anahtar: "siparisKdv";       maksUzunluk: 50 }
                    AlanSatiri { etiket: "Fatura Şekli";     anahtar: "faturaSekli";      maksUzunluk: 150 }
                    AlanSatiri { etiket: "Garanti";          anahtar: "garanti";          maksUzunluk: 200 }
                    AlanSatiri { etiket: "Teslimat";         anahtar: "teslimat";         maksUzunluk: 200 }
                    AlanSatiri { etiket: "Ödeme";            anahtar: "odeme";            maksUzunluk: 200 }
                    AlanSatiri { etiket: "Nakliye";          anahtar: "nakliye";          maksUzunluk: 200 }
                    AlanSatiri { etiket: "Kalibrasyon";      anahtar: "kalibrasyon";      maksUzunluk: 200 }
                    AlanSatiri { etiket: "Eğitim";           anahtar: "egitim";           maksUzunluk: 200 }
                    AlanSatiri { etiket: "Referans Numarası"; anahtar: "referansNumarasi"; maksUzunluk: 200 }
                    AlanSatiri { etiket: "Ek Fatura Notu";   anahtar: "ekFaturaNotu";     maksUzunluk: 500 }
                    TarihSatiri { etiket: "Sipariş Tarihi";  anahtar: "siparisTarihi" }
                }

                Bolum {
                    baslik: "AÇIKLAMALAR"

                    MetinAlaniSatiri { anahtar: "aciklamalar" }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                id: iptalButonu
                Layout.preferredWidth: 110
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: kok.saltOkunur ? "Kapat" : "İptal"
                onClicked: kok.close()
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: iptalButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: iptalButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    text: iptalButonu.text
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                id: kaydetButonu
                visible: !kok.saltOkunur
                Layout.preferredWidth: 150
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Kaydet"
                onClicked: {
                    kok.kaydedildi(kok.degerleriTopla())
                    kok.close()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: kaydetButonu.hovered ? "#1bbd57" : Theme.basari
                }
                contentItem: Text {
                    text: kaydetButonu.text
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
