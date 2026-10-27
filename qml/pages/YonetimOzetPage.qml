import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim / Ozet: yoneticinin modulu actiginda gordugu pano.
//   * Teklifler   -- secilen donemin sayilari ve kabul orani
//   * Kabul edilen tutar -- para birimi bazinda, KDV haric (kura cevrilmez)
//   * Personel    -- ayni sayilarin personel kirilimi
//   * Satinalma   -- su anki durum (donemden bagimsiz; satinalmaOzetiGetir)
// Sayim kurallari: bkz. panoOzetiSorgusu (AramaSorgulari.cpp).
Item {
    id: root

    property bool otomatikYukle: true

    // "buAy" | "gecenAy" | "buYil" | "tumu" | "ozel"
    property string donem: "buAy"
    // "ozel" icin, "yyyy-MM-dd" (iki gun de dahil)
    property string ozelBaslangic: ""
    property string ozelBitis: ""
    readonly property bool ozelTarihEksik: root.donem === "ozel"
        && (root.ozelBaslangic.length === 0 || root.ozelBitis.length === 0)
    readonly property bool ozelTarihTers: root.donem === "ozel" && !root.ozelTarihEksik
        && root.ozelBaslangic > root.ozelBitis
    property var ozet: null
    property var satinalma: ({})
    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string hata: ""

    function sayfayiYukle() {
        root.hata = ""
        root.satinalma = database.satinalmaOzetiGetir()
        // Ozel tarihte iki gun de secilmeden sorgu atilmaz; ekranda onceki
        // sonuc yerine ne beklendigi yazar.
        if (root.ozelTarihEksik || root.ozelTarihTers) {
            root.bekleyenIstek = 0
            root.yukleniyor = false
            zamanAsimiZamanlayici.stop()
            return
        }
        root.yukleniyor = true
        root.bekleyenIstek = database.panoOzetiGetirBaslat(root.donem, root.ozelBaslangic, root.ozelBitis)
        zamanAsimiZamanlayici.restart()
    }

    function donemMetni() {
        if (root.donem === "tumu")
            return "Tüm zamanlar"
        if (!root.ozet || root.ozet.baslangic.length === 0)
            return " "
        return root.ozet.baslangic + " – " + root.ozet.bitis
    }

    function donemSec(yeni) {
        if (root.donem === yeni)
            return
        root.donem = yeni
        root.sayfayiYukle()
    }

    function tutarMetni(tutar, paraBirimi) {
        return SayiBicimi.bicimle(tutar, 2) + " " + paraBirimi
    }

    function tutarlarMetni(tutarlar) {
        if (!tutarlar || tutarlar.length === 0)
            return "—"
        return tutarlar.map(t => root.tutarMetni(t.tutar, t.paraBirimi)).join("  ·  ")
    }

    Connections {
        target: database
        function onPanoOzetiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false
            if (!sonuc || sonuc.verilen === undefined) {
                root.hata = "Özet yüklenemedi: veritabanına bağlanılamadı."
                return
            }
            root.ozet = sonuc
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
            root.hata = "Özet sunucudan yanıt alınamadığı için yüklenemedi. "
                        + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    // ---- Ortak parcalar ----
    component BolumBasligi: Label {
        color: Theme.metinSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.letterSpacing: 1
        Layout.topMargin: 6
    }

    component SayiKarti: Rectangle {
        id: kart
        property string baslik: ""
        property string deger: ""
        property string altYazi: ""

        width: 190
        height: 96
        radius: Theme.radiusNormal
        color: Theme.panel
        border.width: 1
        border.color: Theme.kenarlik

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 2

            Label {
                text: kart.baslik
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: kart.deger
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: 24
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                visible: text.length > 0
                text: kart.altYazi
                color: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Item { Layout.fillHeight: true }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // ---- Baslik + donem ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Özet"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.donemMetni()
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            SuzgecHapi { metin: "Bu Ay"; secili: root.donem === "buAy"; onTiklandi: root.donemSec("buAy") }
            SuzgecHapi { metin: "Geçen Ay"; secili: root.donem === "gecenAy"; onTiklandi: root.donemSec("gecenAy") }
            SuzgecHapi { metin: "Bu Yıl"; secili: root.donem === "buYil"; onTiklandi: root.donemSec("buYil") }
            SuzgecHapi { metin: "Tümü"; secili: root.donem === "tumu"; onTiklandi: root.donemSec("tumu") }
            SuzgecHapi { metin: "Özel Tarih"; secili: root.donem === "ozel"; onTiklandi: root.donemSec("ozel") }

            TarihSecici {
                visible: root.donem === "ozel"
                kompakt: true
                bosMetin: "Başlangıç"
                temizlenebilir: false
                deger: root.ozelBaslangic
                onSecildi: (tarih) => { root.ozelBaslangic = tarih; root.sayfayiYukle() }
            }
            TarihSecici {
                visible: root.donem === "ozel"
                kompakt: true
                bosMetin: "Bitiş"
                temizlenebilir: false
                deger: root.ozelBitis
                onSecildi: (tarih) => { root.ozelBitis = tarih; root.sayfayiYukle() }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: kaydirma
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: icerik.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                visible: root.ozet !== null && root.hata.length === 0
                         && !root.ozelTarihEksik && !root.ozelTarihTers
                opacity: root.yukleniyor ? 0.5 : 1
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: icerik
                    width: kaydirma.width - 12
                    spacing: 10

                    // ---- Teklifler ----
                    BolumBasligi { text: "TEKLİFLER" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        SayiKarti { baslik: "Verilen teklif"; deger: root.ozet ? root.ozet.verilen : ""; altYazi: "Revizyonlar hariç" }
                        SayiKarti { baslik: "Kabul edilen"; deger: root.ozet ? root.ozet.kabul : "" }
                        SayiKarti { baslik: "Reddedilen"; deger: root.ozet ? root.ozet.red : "" }
                        SayiKarti { baslik: "Yanıt bekleyen"; deger: root.ozet ? root.ozet.bekleyen : ""; altYazi: "Bu dönemde verilmiş" }
                        SayiKarti {
                            baslik: "Kabul oranı"
                            deger: !root.ozet || root.ozet.kabulOrani < 0 ? "—"
                                   : "%" + SayiBicimi.bicimle(root.ozet.kabulOrani, 0)
                            altYazi: "Kabul edilen / verilen"
                        }
                    }

                    // ---- Kabul edilen tutar ----
                    BolumBasligi { text: "KABUL EDİLEN TUTAR (KDV HARİÇ)" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.ozet !== null && root.ozet.kabulTutarlari.length > 0
                        Repeater {
                            model: root.ozet ? root.ozet.kabulTutarlari : []
                            delegate: SayiKarti {
                                required property var modelData
                                width: 260
                                baslik: modelData.paraBirimi
                                deger: root.tutarMetni(modelData.tutar, modelData.paraBirimi)
                                altYazi: modelData.adet + " teklif"
                            }
                        }
                    }
                    Label {
                        visible: root.ozet !== null && root.ozet.kabulTutarlari.length === 0
                        text: "Bu dönemde kabul edilen teklif yok."
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                    }

                    // ---- Personel ----
                    BolumBasligi { text: "PERSONEL" }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: personelSutunu.implicitHeight
                        radius: Theme.radiusNormal
                        color: Theme.panel
                        border.width: 1
                        border.color: Theme.kenarlik

                        ColumnLayout {
                            id: personelSutunu
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                Layout.leftMargin: 14
                                Layout.rightMargin: 14
                                spacing: 8
                                Label { text: "PERSONEL"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 180 }
                                Label { text: "VERİLEN"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                Label { text: "KABUL"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                Label { text: "RED"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                Label { text: "BEKLEYEN"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                                Label { text: "KABUL EDİLEN TUTAR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true; Layout.leftMargin: 16 }
                            }

                            Repeater {
                                model: root.ozet ? root.ozet.personeller : []
                                delegate: Item {
                                    id: personelSatiri
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 1
                                        color: Theme.kenarlik
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 8
                                        KisalanMetin { text: personelSatiri.modelData.adSoyad; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; elide: Text.ElideRight; Layout.preferredWidth: 180 }
                                        Label { text: personelSatiri.modelData.verilen; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                        Label { text: personelSatiri.modelData.kabul; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                        Label { text: personelSatiri.modelData.red; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                        Label { text: personelSatiri.modelData.bekleyen; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight }
                                        KisalanMetin { text: root.tutarlarMetni(personelSatiri.modelData.tutarlar); color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; elide: Text.ElideRight; Layout.fillWidth: true; Layout.leftMargin: 16 }
                                    }
                                }
                            }

                            Label {
                                visible: root.ozet !== null && root.ozet.personeller.length === 0
                                Layout.leftMargin: 14
                                Layout.bottomMargin: 12
                                text: "Bu dönemde teklif hareketi yok."
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                            }
                        }
                    }

                    // ---- Satinalma (donemden bagimsiz) ----
                    BolumBasligi { text: "SATINALMA (GÜNCEL DURUM)" }
                    Flow {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 12
                        spacing: 10
                        SayiKarti { baslik: "Patron onayı bekleyen"; deger: root.satinalma.onayBekleyen || 0 }
                        SayiKarti { baslik: "Açık talep"; deger: root.satinalma.acikTalep || 0 }
                        SayiKarti { baslik: "Açık sipariş"; deger: root.satinalma.acikSiparis || 0 }
                        SayiKarti { baslik: "Teslimi geciken"; deger: root.satinalma.geciken || 0 }
                        SayiKarti { baslik: "Faturası eksik"; deger: root.satinalma.faturasiEksik || 0 }
                        SayiKarti {
                            width: 260
                            baslik: "Bu ay alım (TL)"
                            deger: root.tutarMetni(root.satinalma.buAyTutarTL || 0, "TL")
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                visible: root.hata.length > 0 || (root.ozet === null && root.yukleniyor)
                yukleniyor: root.yukleniyor
                hata: root.hata
                kayitSayisi: 0
            }

            Label {
                anchors.centerIn: parent
                visible: root.ozelTarihEksik || root.ozelTarihTers
                text: root.ozelTarihTers ? "Başlangıç tarihi bitiş tarihinden sonra olamaz."
                                         : "Başlangıç ve bitiş tarihini seçin."
                color: root.ozelTarihTers ? Theme.tehlikeAcik : Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
            }
        }
    }
}
