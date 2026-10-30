import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

ApplicationWindow {
    id: pencere
    width: 1400
    height: 900
    visible: true
    visibility: Window.Maximized
    title: "Liya ERP"
    color: Theme.arkaplan

    property var oturum: null

    Component {
        id: ipucuArkaplani
        Rectangle {
            color: Theme.panelYukseltilmis
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.kenarlik
        }
    }
    Component {
        id: ipucuMetni
        Text {
            text: ToolTip.toolTip.text
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            wrapMode: Text.Wrap
        }
    }
    Component.onCompleted: {
        const ipucu = ToolTip.toolTip
        ipucu.background = ipucuArkaplani.createObject(ipucu)
        ipucu.contentItem = ipucuMetni.createObject(ipucu)
    }

    // Baglanti kurulamadiysa kullaniciyi bilgilendir; ekranin geri kalani
    // yine de yuklenir ama listeler bos gelir (Database ic loglarina bakilabilir).
    Rectangle {
        visible: !database.baglantiHazir
        z: 10
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        color: Theme.tehlike

        Label {
            anchors.centerIn: parent
            color: "white"
            font.family: Theme.fontAilesi
            font.bold: true
            text: "Veritabanına bağlanılamadı. " + database.sunucuAdi + " sunucusunun ve ODBC sürücüsünün çalıştığından emin olun."
        }
    }

    StackView {
        id: yiginGorunumu
        anchors.fill: parent
        initialItem: girisBileseni
    }

    // Tum sayfalarin ortak PDF onizleme penceresi (bkz. PdfOnizleme.qml).
    PdfOnizlemeDialog {
        id: pdfOnizlemeDialogu
    }
    Connections {
        target: PdfOnizleme
        function onAcIstendi(tur, teklifId, baslik) {
            pdfOnizlemeDialogu.ac(tur, teklifId, baslik)
        }
        function onIndirIstendi(tur, teklifId, baslik, acilsin) {
            pdfIndirici.bekleyenler.push({ tur: tur, teklifId: teklifId, baslik: baslik, acilsin: acilsin })
            pdfIndirici.mesaj = baslik + " PDF hazırlanıyor…"
            pdfIndirici.hata = false
            pdfIndirici.dosyaYolu = ""
            gizlemeZamanlayici.stop()
            pdfIndirici.visible = true
            indirmeZamanlayici.restart()
        }
    }

    // PdfOnizleme.indir: onizleme acmadan PDF'i uretip klasore kaydeder ve
    // sonucu sag altta gecici bir bildirimle gosterir. Uretim arayuzu birkac
    // saniye mesgul ettigi icin once bildirimin cizilmesine firsat verilir.
    Timer {
        id: indirmeZamanlayici
        interval: 60
        onTriggered: {
            const istek = pdfIndirici.bekleyenler.shift()
            if (!istek)
                return
            const pdf = istek.tur === "uretim"
                ? database.uretimPdfOlustur(istek.teklifId)
                : database.teklifPdfOlustur(istek.teklifId)
            if (!pdf.basarili) {
                pdfIndirici.hata = true
                pdfIndirici.mesaj = istek.baslik + " PDF oluşturulamadı: " + pdf.hata
            } else {
                const kayit = database.pdfKaydet(pdf)
                database.pdfOnizlemesiniSil(pdf.dosyaYolu)
                if (kayit.basarili) {
                    pdfIndirici.hata = false
                    pdfIndirici.dosyaYolu = kayit.dosyaYolu
                    pdfIndirici.mesaj = istek.baslik + " PDF kaydedildi: " + kayit.dosyaYolu
                    PdfOnizleme.kaydedildi(pdf, kayit.dosyaYolu)
                    if (istek.acilsin)
                        Qt.openUrlExternally("file:///" + kayit.dosyaYolu)
                } else {
                    pdfIndirici.hata = true
                    pdfIndirici.mesaj = istek.baslik + " PDF kaydedilemedi: " + kayit.hata
                }
            }
            if (pdfIndirici.bekleyenler.length > 0)
                indirmeZamanlayici.restart()
            else
                gizlemeZamanlayici.restart()
        }
    }
    Timer {
        id: gizlemeZamanlayici
        interval: 8000
        onTriggered: pdfIndirici.visible = false
    }

    Rectangle {
        id: pdfIndirici
        property var bekleyenler: []
        property string mesaj: ""
        property string dosyaYolu: ""
        property bool hata: false

        visible: false
        z: 1000
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        width: Math.min(pdfMesajMetni.implicitWidth + 24, pencere.width - 48)
        height: pdfMesajMetni.height + 16
        radius: Theme.radiusNormal
        color: pdfIndirici.hata ? Theme.bildirimHataZemin : Theme.bildirimBasariZemin
        border.width: 1
        border.color: pdfIndirici.hata ? Theme.tehlikeAcik : Theme.basariAcik

        Text {
            id: pdfMesajMetni
            anchors.centerIn: parent
            width: Math.min(implicitWidth, pencere.width - 72)
            text: pdfIndirici.mesaj
            color: pdfIndirici.hata ? Theme.tehlikeAcik : Theme.basariAcik
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            wrapMode: Text.Wrap
        }

        // Kaydedilen dosyayi acmak icin bildirime tiklanir.
        MouseArea {
            anchors.fill: parent
            enabled: pdfIndirici.dosyaYolu.length > 0
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                Qt.openUrlExternally("file:///" + pdfIndirici.dosyaYolu)
                pdfIndirici.visible = false
            }
        }
    }

    // Tema degisimi: once ekranin anlik goruntusu alinip ustte birakilir, renkler
    // altta tek karede degisir ve goruntu soldurulur -- boylece tum ekran iki tema
    // arasinda yumusakca gecer. Goruntu alinamazsa tema dogrudan degistirilir.
    // Giris yapilmissa yeni tema personelin kaydina da yazilir (bir sonraki
    // giriste o uygulanir; bkz. Database::temaTercihiKaydet).
    function temayiCevir() {
        Theme.koyuModuAyarla(!Theme.koyuMod)
        database.temaTercihiKaydet(Theme.koyuMod)
    }
    Connections {
        target: Theme
        function onDegistirmeIstendi() {
            const icerik = pencere.contentItem
            const alindi = icerik.grabToImage(function (sonuc) {
                temaGecisi.goruntu = sonuc
                temaGecisi.source = sonuc.url
                temaGecisi.opacity = 1
                pencere.temayiCevir()
                temaGecisAnimasyonu.restart()
            }, Qt.size(icerik.width * Screen.devicePixelRatio, icerik.height * Screen.devicePixelRatio))
            if (!alindi)
                pencere.temayiCevir()
        }
    }

    Image {
        id: temaGecisi
        property var goruntu: null   // grabToImage sonucu; yasadigi surece url gecerli
        anchors.fill: parent
        z: 2000
        opacity: 0
        visible: opacity > 0

        NumberAnimation {
            id: temaGecisAnimasyonu
            target: temaGecisi
            property: "opacity"
            to: 0
            duration: 320
            easing.type: Easing.OutCubic
            onFinished: {
                temaGecisi.source = ""
                temaGecisi.goruntu = null
            }
        }
    }

    Component {
        id: girisBileseni
        GirisPage {
            onGirisBasarili: (sonuc) => {
                pencere.oturum = sonuc;
                // Personelin kendi temasi (db/34 yoksa alan gelmez, tema degismez).
                if (sonuc.koyuTema !== undefined)
                    Theme.koyuModuAyarla(sonuc.koyuTema);
                yiginGorunumu.replace(anaMenuBileseni);
            }
        }
    }

    Component {
        id: anaMenuBileseni
        AnaMenuPage {
            adSoyad: pencere.oturum ? pencere.oturum.adSoyad : ""
            moduller: pencere.oturum ? pencere.oturum.moduller : []

            onModulSecildi: (modulKodu) => {
                if (modulKodu === "SATIS")
                    yiginGorunumu.push(satisModuluBileseni, { baslangicSekmesi: 0 });
                else if (modulKodu === "SATINALMA")
                    yiginGorunumu.push(satinalmaModuluBileseni, { baslangicSekmesi: 0 });
                else if (modulKodu === "YONETIM")
                    yiginGorunumu.push(yonetimModuluBileseni, { baslangicSekmesi: 0 });
                else if (modulKodu === "MUHASEBE")
                    yiginGorunumu.push(muhasebeModuluBileseni, { baslangicSekmesi: 0 });
            }

            onTeklifVerSecildi: {
                yiginGorunumu.push(satisModuluBileseni, { baslangicSekmesi: 0 });
            }

            onCikisYapildi: {
                pencere.oturum = null;
                // Sunucu tarafindaki aktif oturum bilgisi de temizlenir: aksi
                // halde cikis yapildiktan sonra bile "kendi hesabini pasife
                // alma" korumasi eski kullaniciya gore calisirdi
                // (bkz. Database::aktifKullaniciId).
                database.oturumuKapat();
                yiginGorunumu.replace(girisBileseni);
            }
        }
    }

    Component {
        id: satisModuluBileseni
        SatisModuluPage {
            oturum: pencere.oturum
            onAnaMenuyeDon: yiginGorunumu.pop()
        }
    }

    Component {
        id: satinalmaModuluBileseni
        SatinAlmaModuluPage {
            oturum: pencere.oturum
            onAnaMenuyeDon: yiginGorunumu.pop()
        }
    }

    Component {
        id: yonetimModuluBileseni
        YonetimModuluPage {
            oturum: pencere.oturum
            onAnaMenuyeDon: yiginGorunumu.pop()
        }
    }

    Component {
        id: muhasebeModuluBileseni
        MuhasebeModuluPage {
            oturum: pencere.oturum
            onAnaMenuyeDon: yiginGorunumu.pop()
        }
    }
}
