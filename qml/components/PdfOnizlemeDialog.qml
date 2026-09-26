import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// PDF onizleme penceresi. database.teklifPdfOlustur / uretimPdfOlustur PDF'i
// gecici onizleme klasorune basar; bu pencere sayfalari pdfOnizleyici
// (Windows'un PDF motoru, bkz. src/PdfOnizleyici.h) ile resim olarak cizip
// alt alta gosterir. Dosya kullanicinin klasorune (Belgelerim/Liya ERP
// Teklifler) ANCAK "İndir"e basilinca kopyalanir (database.pdfKaydet);
// pencere kapanirken gecici dosya silinir.
//
// Main.qml'de tek ornek olarak durur, sayfalar PdfOnizleme.ac(...) ile acar.
Dialog {
    id: kok

    // Acik PDF: *PdfOlustur sonucu ({dosyaYolu, dosyaAdi, tur, teklifId}).
    property var pdf: null
    property string baslik: ""

    // pdfOnizleyici.ac sonucu: belge anahtari ve sayfa olculeri.
    property int anahtar: -1
    property var sayfalar: []

    // "İndir" basarili olduysa kaydedilen dosyanin yolu ve klasoru.
    property string kaydedilenYol: ""
    property string kaydedilenKlasor: ""
    property string hataMetni: ""

    // Yakinlik 1 = sayfa, listenin genisligine (en fazla 1000 px) sigar.
    // Sayfalar "cizimYakinligi"nda yeniden cizilir; o da yakinlik degismeyi
    // birakinca guncellenir -- Ctrl+tekerlegin her adiminda tum sayfalar
    // bastan cizilmesin (arada mevcut resim olceklenerek gosterilir).
    property real yakinlik: 1.0
    property real cizimYakinligi: 1.0
    readonly property real temelGenislik: Math.max(200, Math.min(liste.width - 48, 1000))
    onYakinlikChanged: cizimZamanlayici.restart()

    function yakinlastir(carpan) {
        kok.yakinlik = Math.max(0.5, Math.min(3.0, kok.yakinlik * carpan))
    }

    function belgeyiBirak() {
        if (kok.anahtar >= 0)
            pdfOnizleyici.kapat(kok.anahtar)
        if (kok.pdf)
            database.pdfOnizlemesiniSil(kok.pdf.dosyaYolu)
        kok.anahtar = -1
        kok.sayfalar = []
        kok.pdf = null
    }

    // PDF uretilirken true: pencere acik, ortada "hazırlanıyor" gosterilir.
    property bool hazirlaniyor: false
    // Uretilecek PDF ({tur, teklifId}); uretimZamanlayici bunu isler.
    property var bekleyen: null

    // Pencereyi HEMEN acar, PDF'i ardindan uretir. Uretim (Chromium'un PDF'e
    // basmasi) arayuzu birkac saniye mesgul ediyor; once pencerenin ekrana
    // cizilmesine firsat verilir ki kullanici butona basinca bir sey oldugunu
    // gorsun (uretim sirasinda da animasyonlar calismaya devam eder).
    function ac(tur, teklifId, yeniBaslik) {
        // Pencere acikken yeni bir PDF istenirse oncekinin gecici dosyasi birakilmasin.
        kok.belgeyiBirak()
        kok.baslik = yeniBaslik
        kok.kaydedilenYol = ""
        kok.kaydedilenKlasor = ""
        kok.hataMetni = ""
        kok.yakinlik = 1.0
        kok.cizimYakinligi = 1.0
        kok.bekleyen = { tur: tur, teklifId: teklifId }
        kok.hazirlaniyor = true
        kok.open()
        uretimZamanlayici.restart()
    }

    function uret() {
        const istek = kok.bekleyen
        kok.bekleyen = null
        if (!istek)
            return
        const sonuc = istek.tur === "uretim"
            ? database.uretimPdfOlustur(istek.teklifId)
            : database.teklifPdfOlustur(istek.teklifId)
        kok.hazirlaniyor = false

        if (!sonuc.basarili) {
            kok.hataMetni = "PDF oluşturulamadı: " + sonuc.hata
            return
        }
        kok.pdf = sonuc
        const acilis = pdfOnizleyici.ac(sonuc.dosyaYolu)
        if (acilis.basarili) {
            kok.anahtar = acilis.anahtar
            kok.sayfalar = acilis.sayfalar
        } else {
            kok.hataMetni = "Önizleme açılamadı: " + acilis.hata
        }
        liste.positionViewAtBeginning()
    }

    function indir() {
        const sonuc = database.pdfKaydet(kok.pdf)
        if (sonuc.basarili) {
            kok.kaydedilenYol = sonuc.dosyaYolu
            kok.kaydedilenKlasor = sonuc.klasor
            kok.hataMetni = ""
            PdfOnizleme.kaydedildi(kok.pdf, sonuc.dosyaYolu)
        } else {
            kok.hataMetni = sonuc.hata
        }
    }

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: parent ? parent.width - 80 : 1000
    height: parent ? parent.height - 60 : 800
    padding: 16

    onClosed: {
        uretimZamanlayici.stop()
        kok.bekleyen = null
        kok.hazirlaniyor = false
        kok.belgeyiBirak()
    }

    // Pencerenin ilk karesi cizilsin diye uretim bir an sonra baslar.
    Timer {
        id: uretimZamanlayici
        interval: 60
        onTriggered: kok.uret()
    }

    Timer {
        id: cizimZamanlayici
        interval: 250
        onTriggered: kok.cizimYakinligi = kok.yakinlik
    }

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    // Pencerenin alt satirindaki butonlarin ortak gorunumu.
    component PencereButonu: Button {
        id: buton
        property bool birincil: false
        property int enAzGenislik: 110
        Layout.preferredWidth: Math.max(enAzGenislik, Math.ceil(butonMetni.implicitWidth) + 28)
        Layout.preferredHeight: Theme.girdiYuksekligi
        background: Rectangle {
            radius: Theme.radiusKucuk
            color: buton.birincil
                   ? (!buton.enabled ? Theme.panelHover : buton.hovered ? Theme.vurguHover : Theme.vurgu)
                   : (buton.hovered ? Theme.panelHover : "transparent")
            border.width: buton.birincil ? 0 : 1
            border.color: buton.hovered ? Theme.metinSoluk : Theme.kenarlik
        }
        contentItem: Text {
            id: butonMetni
            text: buton.text
            color: buton.birincil ? (buton.enabled ? "#ffffff" : Theme.metinSoluk) : Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.bold: buton.birincil
            font.pixelSize: Theme.fontBoyutKucuk
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    header: RowLayout {
        spacing: 8
        Item { Layout.preferredWidth: 12 }
        Rectangle {
            Layout.topMargin: 16
            Layout.preferredWidth: 4
            Layout.preferredHeight: 16
            radius: 2
            color: Theme.vurgu
        }
        Label {
            Layout.topMargin: 16
            text: kok.baslik.length > 0 ? kok.baslik + " — PDF Önizleme" : "PDF Önizleme"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
        }
        Label {
            Layout.topMargin: 16
            Layout.fillWidth: true
            text: kok.pdf ? kok.pdf.dosyaAdi : ""
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            elide: Text.ElideMiddle
        }
        Item { Layout.preferredWidth: 12 }
    }

    contentItem: ColumnLayout {
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusKucuk
            color: Theme.arkaplan
            border.width: 1
            border.color: Theme.kenarlik
            clip: true

            ListView {
                id: liste
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: kok.sayfalar
                spacing: 16
                topMargin: 16
                bottomMargin: 16
                // Gorunen alanin bir ekran asagisi/yukarisi da onceden cizilir,
                // kaydirirken bos sayfa gorulmesin.
                cacheBuffer: Math.max(0, height * 2)
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.AutoFlickIfNeeded
                contentWidth: Math.max(width, kok.temelGenislik * kok.yakinlik + 48)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                // Ctrl + tekerlek: yakinlastir/uzaklastir (liste kaydirilmaz).
                WheelHandler {
                    acceptedModifiers: Qt.ControlModifier
                    target: null
                    onWheel: (olay) => kok.yakinlastir(olay.angleDelta.y > 0 ? 1.1 : 1 / 1.1)
                }

                delegate: Item {
                    id: sayfaKutusu
                    required property var modelData
                    required property int index
                    readonly property real sayfaGenisligi: kok.temelGenislik * kok.yakinlik
                    width: liste.contentWidth
                    height: sayfaGenisligi * modelData.yukseklik / modelData.genislik

                    Rectangle {
                        x: Math.max(24, (liste.width - width) / 2)
                        width: sayfaKutusu.sayfaGenisligi
                        height: parent.height
                        color: "#ffffff"

                        Image {
                            id: sayfaResmi
                            anchors.fill: parent
                            source: kok.anahtar >= 0 ? "image://pdfsayfa/" + kok.anahtar + "/" + sayfaKutusu.index : ""
                            sourceSize.width: Math.round(kok.temelGenislik * kok.cizimYakinligi * Screen.devicePixelRatio)
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            fillMode: Image.Stretch
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: sayfaResmi.status === Image.Loading
                            visible: running
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: kok.hazirlaniyor

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: kok.hazirlaniyor
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "PDF hazırlanıyor…"
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            PencereButonu {
                enAzGenislik: 40
                text: "−"
                onClicked: kok.yakinlastir(1 / 1.2)
            }
            PencereButonu {
                enAzGenislik: 64
                text: Math.round(kok.yakinlik * 100) + "%"
                onClicked: kok.yakinlik = 1.0
                ToolTip.visible: hovered
                ToolTip.text: "Sayfayı genişliğe sığdır"
            }
            PencereButonu {
                enAzGenislik: 40
                text: "+"
                onClicked: kok.yakinlastir(1.2)
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: kok.hataMetni.length > 0
                      ? kok.hataMetni
                      : kok.kaydedilenYol.length > 0
                      ? "Kaydedildi: " + kok.kaydedilenYol
                      : kok.hazirlaniyor
                      ? ""
                      : kok.sayfalar.length + " sayfa · İndirmediğiniz sürece dosya kaydedilmez."
                color: kok.hataMetni.length > 0 ? Theme.tehlikeAcik
                     : kok.kaydedilenYol.length > 0 ? Theme.basariAcik
                     : Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                elide: Text.ElideMiddle
            }

            // Indirdikten sonra: e-postaya eklemek / yazdirmak icin dosyayi
            // veya klasoru acmak.
            PencereButonu {
                visible: kok.kaydedilenYol.length > 0
                text: "Dosyayı Aç"
                onClicked: Qt.openUrlExternally("file:///" + kok.kaydedilenYol)
            }
            PencereButonu {
                visible: kok.kaydedilenKlasor.length > 0
                text: "Klasörü Aç"
                onClicked: Qt.openUrlExternally("file:///" + kok.kaydedilenKlasor)
            }
            PencereButonu {
                text: "Kapat"
                onClicked: kok.close()
            }
            PencereButonu {
                birincil: true
                enabled: kok.pdf !== null && kok.kaydedilenYol.length === 0
                text: kok.kaydedilenYol.length > 0 ? "İndirildi" : "İndir"
                onClicked: kok.indir()
            }
        }
    }
}
