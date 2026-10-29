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
        color: pdfIndirici.hata ? Qt.rgba(0.14, 0.08, 0.09, 0.97) : Qt.rgba(0.07, 0.14, 0.10, 0.97)
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

    Component {
        id: girisBileseni
        GirisPage {
            onGirisBasarili: (sonuc) => {
                pencere.oturum = sonuc;
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
