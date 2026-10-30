import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim / Ozet: yoneticinin modulu actiginda gordugu pano.
//   * Gostergeler -- secilen donemin teklif sayilari ve kabul orani
//   * Teklif hareketi -- verilen / kabul edilen, gun-ay-yil kovalarinda
//   * Kabul edilen tutar -- para birimi bazinda, KDV haric (kura cevrilmez,
//     para birimleri toplanamadigi icin grafik degil liste)
//   * Personel    -- ayni sayilarin personel kirilimi, cubuklarla
//   * Satinalma   -- su anki durum (donemden bagimsiz; satinalmaOzetiGetir)
// Sayim kurallari: bkz. panoOzetiSorgusu (AramaSorgulari.cpp).
// Grafik renkleri: Theme.grafikSeri1 (verilen) / grafikSeri2 (kabul) her
// grafikte ayni olcuyu tasir.
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

    // Yeni veri gelince cubuklar ve halka 0'dan buyur.
    property real grafikIlerleme: 1

    // Personel tablosundaki verilen / kabul cubuk sutunlarinin genisligi;
    // dar pencerede kucusur, tutar sutununa yer kalsin.
    readonly property int cubukSutunu: root.width >= 1500 ? 260 : 180

    readonly property var seri: root.ozet && root.ozet.seri ? root.ozet.seri : []
    readonly property var personeller: root.ozet ? root.ozet.personeller : []
    readonly property int personelEnFazla: {
        let enFazla = 0
        for (const p of root.personeller)
            enFazla = Math.max(enFazla, p.verilen, p.kabul)
        return enFazla
    }

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

    function oranMetni(pay, payda) {
        return payda > 0 ? "%" + SayiBicimi.bicimle(100 * pay / payda, 0) : "—"
    }

    // Eksen icin "yuvarlak" adim: 1, 2, 5, 10, 20, 50 ...
    function eksenAdimi(enFazla) {
        if (enFazla <= 4)
            return 1
        const kaba = enFazla / 4
        const us = Math.pow(10, Math.floor(Math.log10(kaba)))
        const oran = kaba / us
        return (oran <= 1 ? 1 : oran <= 2 ? 2 : oran <= 5 ? 5 : 10) * us
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
            grafikAnimasyonu.restart()
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

    NumberAnimation {
        id: grafikAnimasyonu
        target: root
        property: "grafikIlerleme"
        from: 0
        to: 1
        duration: 650
        easing.type: Easing.OutCubic
    }

    // ---- Ortak parcalar ----
    component BolumBasligi: Label {
        color: Theme.metinSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: 10
        font.letterSpacing: 1
        Layout.topMargin: 6
    }

    component Panel: Rectangle {
        radius: Theme.radiusBuyuk
        color: Theme.panel
        border.width: 1
        border.color: Theme.kenarlik
    }

    component PanelBasligi: ColumnLayout {
        property string baslik: ""
        property string altBaslik: ""
        spacing: 2
        Label {
            text: parent.baslik
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutOrta
            font.bold: true
        }
        Label {
            visible: text.length > 0
            text: parent.altBaslik
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
        }
    }

    // Renk anahtari: seri rengi yazida degil, yanindaki noktada.
    component Anahtar: RowLayout {
        property string metin: ""
        property color renk: Theme.metinSoluk
        spacing: 6
        Rectangle { width: 10; height: 10; radius: 5; color: parent.renk }
        Label {
            text: parent.metin
            color: Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
        }
    }

    // Gosterge karti. "isaretRengi": baslik yanindaki nokta (grafikteki seri
    // rengi ya da bir durum rengi); saydamsa nokta yok. "halkaOrani" (0-100)
    // verilirse sagda halka gosterge cizilir: dolu kisim oran, iz ayni rengin
    // soluk tonu.
    component GostergeKarti: Panel {
        id: kart
        property string baslik: ""
        property string deger: ""
        property string altYazi: ""
        property color isaretRengi: "transparent"
        property real halkaOrani: -1
        property color halkaRengi: Theme.grafikSeri2

        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.preferredHeight: 108
        radius: Theme.radiusNormal

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    spacing: 7
                    Layout.fillWidth: true
                    Rectangle {
                        visible: kart.isaretRengi.a > 0
                        width: 8; height: 8; radius: 4
                        color: kart.isaretRengi
                    }
                    Label {
                        text: kart.baslik
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                Label {
                    text: kart.deger
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: 28
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

            Canvas {
                id: halka
                visible: kart.halkaOrani >= 0
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                Layout.alignment: Qt.AlignVCenter
                readonly property real deger: Math.min(1, Math.max(0, kart.halkaOrani / 100)) * root.grafikIlerleme
                readonly property color renk: kart.halkaRengi
                onDegerChanged: requestPaint()
                onRenkChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const r = width / 2 - 5
                    ctx.lineWidth = 7
                    ctx.lineCap = "round"
                    ctx.strokeStyle = Qt.rgba(renk.r, renk.g, renk.b, 0.18)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
                    ctx.stroke()
                    if (deger > 0) {
                        ctx.strokeStyle = renk
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + deger * Math.PI * 2)
                        ctx.stroke()
                    }
                }
            }
        }
    }

    // Ustu yuvarlak, tabani duz sutun/cubuk: yuvarlak dikdortgenin taban
    // tarafi kirpilarak duzlestirilir.
    component Sutun: Item {
        property color renk: Theme.grafikSeri1
        clip: true
        Rectangle {
            width: parent.width
            height: parent.height + radius
            radius: Math.min(4, parent.width / 2)
            color: parent.renk
        }
    }

    component YatayCubuk: Item {
        property color renk: Theme.grafikSeri1
        clip: true
        Rectangle {
            x: -radius
            width: parent.width + radius
            height: parent.height
            radius: Math.min(4, parent.height / 2)
            color: parent.renk
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
                    spacing: 12

                    // ---- Gostergeler ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        GostergeKarti {
                            baslik: "Verilen teklif"
                            deger: root.ozet ? root.ozet.verilen : ""
                            altYazi: "Revizyonlar hariç"
                            isaretRengi: Theme.grafikSeri1
                        }
                        GostergeKarti {
                            baslik: "Kabul edilen"
                            deger: root.ozet ? root.ozet.kabul : ""
                            altYazi: "Kabul tarihi bu dönemde"
                            isaretRengi: Theme.grafikSeri2
                        }
                        GostergeKarti {
                            baslik: "Reddedilen"
                            deger: root.ozet ? root.ozet.red : ""
                        }
                        GostergeKarti {
                            baslik: "Yanıt bekleyen"
                            deger: root.ozet ? root.ozet.bekleyen : ""
                            altYazi: "Bu dönemde verilmiş"
                        }
                        GostergeKarti {
                            readonly property real oran: root.ozet ? root.ozet.kabulOrani : -1
                            baslik: "Kabul oranı"
                            deger: oran < 0 ? "—" : "%" + SayiBicimi.bicimle(oran, 0)
                            altYazi: "Kabul edilen / verilen"
                            halkaOrani: oran
                        }
                    }

                    // ---- Teklif hareketi + kabul edilen tutar ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Panel {
                            id: trendPaneli
                            Layout.fillWidth: true
                            Layout.preferredHeight: 340

                            property int seciliKova: -1
                            readonly property int enFazla: {
                                let m = 0
                                for (const k of root.seri)
                                    m = Math.max(m, k.verilen, k.kabul)
                                return m
                            }
                            readonly property int adim: root.eksenAdimi(trendPaneli.enFazla)
                            readonly property int eksenUst: Math.max(adim, Math.ceil(trendPaneli.enFazla / adim) * adim)
                            readonly property int cizgiSayisi: Math.round(eksenUst / adim)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    PanelBasligi {
                                        baslik: "Teklif hareketi"
                                        altBaslik: !root.ozet ? ""
                                                   : root.ozet.seriAdimi === "gun" ? "Günlük"
                                                   : root.ozet.seriAdimi === "yil" ? "Yıllık" : "Aylık"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Anahtar { metin: "Verilen"; renk: Theme.grafikSeri1 }
                                    Item { Layout.preferredWidth: 12 }
                                    Anahtar { metin: "Kabul edilen"; renk: Theme.grafikSeri2 }
                                }

                                // Cizim alani: solda eksen degerleri, altta kova etiketleri.
                                Item {
                                    id: cizim
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    readonly property int solBosluk: 36
                                    readonly property int altBosluk: 22
                                    readonly property real alanGenisligi: width - solBosluk
                                    readonly property real alanYuksekligi: height - altBosluk
                                    readonly property real kovaGenisligi: root.seri.length > 0 ? alanGenisligi / root.seri.length : 0
                                    // Iki sutun arasinda 2px bosluk; sutun en fazla 18px.
                                    readonly property real sutunGenisligi: Math.max(2, Math.min(18, (kovaGenisligi - 8) / 2 - 1))
                                    // Etiketler sigmazsa her n'inci kova yazilir.
                                    readonly property int etiketAdimi: Math.max(1, Math.ceil(36 / Math.max(1, kovaGenisligi)))

                                    function yukseklik(deger) {
                                        return trendPaneli.eksenUst > 0 ? alanYuksekligi * deger / trendPaneli.eksenUst : 0
                                    }

                                    // Kilavuz cizgileri + eksen degerleri
                                    Repeater {
                                        model: trendPaneli.cizgiSayisi + 1
                                        delegate: Item {
                                            required property int index
                                            x: 0
                                            y: cizim.alanYuksekligi - cizim.yukseklik(index * trendPaneli.adim)
                                            width: cizim.width
                                            height: 1

                                            Rectangle {
                                                x: cizim.solBosluk
                                                width: cizim.alanGenisligi
                                                height: 1
                                                color: parent.index === 0 ? Theme.grafikEksen : Theme.grafikIzgara
                                            }
                                            Label {
                                                x: cizim.solBosluk - 8 - width
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: SayiBicimi.bicimle(parent.index * trendPaneli.adim, 0)
                                                color: Theme.metinCokSoluk
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                    // Kovalar
                                    Repeater {
                                        model: root.seri
                                        delegate: Item {
                                            id: kova
                                            required property int index
                                            required property var modelData
                                            x: cizim.solBosluk + index * cizim.kovaGenisligi
                                            width: cizim.kovaGenisligi
                                            height: cizim.height

                                            // Uzerine gelinen kovanin hafif zemini
                                            Rectangle {
                                                width: parent.width
                                                height: cizim.alanYuksekligi
                                                radius: Theme.radiusKucuk
                                                color: Theme.panelHover
                                                visible: trendPaneli.seciliKova === kova.index
                                            }

                                            Sutun {
                                                renk: Theme.grafikSeri1
                                                width: cizim.sutunGenisligi
                                                height: cizim.yukseklik(kova.modelData.verilen) * root.grafikIlerleme
                                                x: kova.width / 2 - width - 1
                                                y: cizim.alanYuksekligi - height
                                            }
                                            Sutun {
                                                renk: Theme.grafikSeri2
                                                width: cizim.sutunGenisligi
                                                height: cizim.yukseklik(kova.modelData.kabul) * root.grafikIlerleme
                                                x: kova.width / 2 + 1
                                                y: cizim.alanYuksekligi - height
                                            }

                                            Label {
                                                visible: kova.index % cizim.etiketAdimi === 0
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: cizim.alanYuksekligi + 6
                                                text: kova.modelData.etiket
                                                color: Theme.metinCokSoluk
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: 10
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: trendPaneli.seciliKova = kova.index
                                                onExited: if (trendPaneli.seciliKova === kova.index) trendPaneli.seciliKova = -1
                                            }
                                        }
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        visible: trendPaneli.enFazla === 0
                                        text: "Bu dönemde teklif hareketi yok."
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                    }

                                    // Ipucu: uzerine gelinen kovanin tarihi ve iki degeri
                                    Rectangle {
                                        id: ipucu
                                        readonly property var kayit: trendPaneli.seciliKova >= 0 && trendPaneli.seciliKova < root.seri.length
                                                                     ? root.seri[trendPaneli.seciliKova] : null
                                        visible: kayit !== null
                                        z: 10
                                        width: ipucuIcerik.implicitWidth + 24
                                        height: ipucuIcerik.implicitHeight + 18
                                        radius: Theme.radiusNormal
                                        color: Theme.panelYukseltilmis
                                        border.width: 1
                                        border.color: Theme.kenarlik
                                        readonly property real kovaOrtasi: cizim.solBosluk + (trendPaneli.seciliKova + 0.5) * cizim.kovaGenisligi
                                        // Kovanin sagina; sigmazsa soluna.
                                        x: kovaOrtasi + cizim.kovaGenisligi / 2 + width + 6 <= cizim.width
                                           ? kovaOrtasi + cizim.kovaGenisligi / 2 + 6
                                           : Math.max(0, kovaOrtasi - cizim.kovaGenisligi / 2 - width - 6)
                                        y: 4

                                        ColumnLayout {
                                            id: ipucuIcerik
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Label {
                                                text: ipucu.kayit ? ipucu.kayit.ipucu : ""
                                                color: Theme.metinBirincil
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: Theme.fontBoyutKucuk
                                                font.bold: true
                                            }
                                            Repeater {
                                                model: [
                                                    { ad: "Verilen", alan: "verilen", renk: Theme.grafikSeri1 },
                                                    { ad: "Kabul edilen", alan: "kabul", renk: Theme.grafikSeri2 }
                                                ]
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    spacing: 8
                                                    Rectangle { width: 8; height: 8; radius: 4; color: parent.modelData.renk }
                                                    Label {
                                                        text: parent.modelData.ad
                                                        color: Theme.metinIkincil
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: Theme.fontBoyutKucuk
                                                        Layout.preferredWidth: 84
                                                    }
                                                    Label {
                                                        text: ipucu.kayit ? ipucu.kayit[parent.modelData.alan] : ""
                                                        color: Theme.metinBirincil
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: Theme.fontBoyutKucuk
                                                        font.bold: true
                                                        horizontalAlignment: Text.AlignRight
                                                        Layout.preferredWidth: 28
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Para birimleri toplanamaz (kura cevrilmez): liste.
                        Panel {
                            Layout.preferredWidth: 360
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 6

                                PanelBasligi {
                                    baslik: "Kabul edilen tutar"
                                    altBaslik: "KDV hariç, teklifin kendi para biriminde"
                                    Layout.bottomMargin: 8
                                }

                                Repeater {
                                    model: root.ozet ? root.ozet.kabulTutarlari : []
                                    delegate: ColumnLayout {
                                        id: tutarSatiri
                                        required property int index
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            visible: tutarSatiri.index > 0
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Theme.kenarlik
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            Rectangle {
                                                Layout.preferredWidth: 46
                                                Layout.preferredHeight: 30
                                                radius: Theme.radiusKucuk
                                                color: Theme.vurguZeminSoluk
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: tutarSatiri.modelData.paraBirimi
                                                    color: Theme.vurguAcik
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: Theme.fontBoyutKucuk
                                                    font.bold: true
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                KisalanMetin {
                                                    text: SayiBicimi.bicimle(tutarSatiri.modelData.tutar, 2)
                                                    color: Theme.metinBirincil
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: 22
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Label {
                                                    text: tutarSatiri.modelData.adet + " teklif"
                                                    color: Theme.metinCokSoluk
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                    }
                                }

                                Label {
                                    visible: root.ozet !== null && root.ozet.kabulTutarlari.length === 0
                                    text: "Bu dönemde kabul edilen teklif yok."
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    // ---- Personel performansi ----
                    Panel {
                        Layout.fillWidth: true
                        Layout.preferredHeight: personelSutunu.implicitHeight + 36

                        ColumnLayout {
                            id: personelSutunu
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 18
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 12
                                PanelBasligi { baslik: "Personel performansı"; altBaslik: "Çubuklar aynı ölçektedir" }
                                Item { Layout.fillWidth: true }
                                Anahtar { metin: "Verilen"; renk: Theme.grafikSeri1 }
                                Item { Layout.preferredWidth: 12 }
                                Anahtar { metin: "Kabul edilen"; renk: Theme.grafikSeri2 }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                spacing: 16
                                Label { text: "PERSONEL"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 170 }
                                Label { text: "VERİLEN"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: root.cubukSutunu }
                                Label { text: "KABUL"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: root.cubukSutunu }
                                Label { text: "KABUL ORANI"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight }
                                Label { text: "BEKLEYEN"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                Label { text: "RED"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                Label { text: "KABUL EDİLEN TUTAR"; color: Theme.tabloBaslikMetin; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.fillWidth: true }
                            }

                            Repeater {
                                model: root.personeller
                                delegate: Item {
                                    id: personelSatiri
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 1
                                        color: Theme.kenarlik
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.topMargin: 1
                                        radius: Theme.radiusKucuk
                                        color: Theme.panelHover
                                        visible: personelFare.containsMouse
                                    }
                                    MouseArea { id: personelFare; anchors.fill: parent; hoverEnabled: true }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 16

                                        KisalanMetin {
                                            text: personelSatiri.modelData.adSoyad
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            elide: Text.ElideRight
                                            Layout.preferredWidth: 170
                                        }

                                        Repeater {
                                            model: [
                                                { deger: personelSatiri.modelData.verilen, renk: Theme.grafikSeri1 },
                                                { deger: personelSatiri.modelData.kabul, renk: Theme.grafikSeri2 }
                                            ]
                                            delegate: Item {
                                                id: cubukHucresi
                                                required property var modelData
                                                Layout.preferredWidth: root.cubukSutunu
                                                Layout.preferredHeight: 20
                                                // Deger yazisina yer birakilir.
                                                readonly property real enUzun: width - 40

                                                YatayCubuk {
                                                    id: cubuk
                                                    renk: cubukHucresi.modelData.renk
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 10
                                                    width: root.personelEnFazla > 0
                                                           ? Math.max(cubukHucresi.modelData.deger > 0 ? 3 : 0,
                                                                      cubukHucresi.enUzun * cubukHucresi.modelData.deger / root.personelEnFazla * root.grafikIlerleme)
                                                           : 0
                                                }
                                                Label {
                                                    anchors.left: cubuk.right
                                                    anchors.leftMargin: 8
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: cubukHucresi.modelData.deger
                                                    color: Theme.metinBirincil
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: Theme.fontBoyutNormal
                                                }
                                            }
                                        }

                                        Label {
                                            text: root.oranMetni(personelSatiri.modelData.kabul, personelSatiri.modelData.verilen)
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: true
                                            Layout.preferredWidth: 84
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Label { text: personelSatiri.modelData.bekleyen; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                        Label { text: personelSatiri.modelData.red; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                        KisalanMetin {
                                            text: root.tutarlarMetni(personelSatiri.modelData.tutarlar)
                                            color: Theme.metinIkincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            Label {
                                visible: root.ozet !== null && root.personeller.length === 0
                                Layout.topMargin: 8
                                text: "Bu dönemde teklif hareketi yok."
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                            }
                        }
                    }

                    // ---- Satinalma (donemden bagimsiz) ----
                    // Dikkat isteyen durumlar (gecikme, onay, eksik fatura) durum
                    // rengiyle isaretlenir; renk yalniz degil, alt yazi da soyler.
                    BolumBasligi { text: "SATINALMA (GÜNCEL DURUM)" }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 12
                        spacing: 12

                        GostergeKarti {
                            readonly property int sayi: root.satinalma.onayBekleyen || 0
                            baslik: "Patron onayı bekleyen"
                            deger: sayi
                            isaretRengi: sayi > 0 ? Theme.uyari : "transparent"
                            altYazi: sayi > 0 ? "Onay bekliyor" : ""
                        }
                        // Siparise donusmemis kalemi olan talepler (malini bekleyenler degil).
                        GostergeKarti { baslik: "Sipariş bekleyen talep"; deger: root.satinalma.acikTalep || 0 }
                        GostergeKarti { baslik: "Açık sipariş"; deger: root.satinalma.acikSiparis || 0 }
                        GostergeKarti {
                            readonly property int sayi: root.satinalma.geciken || 0
                            baslik: "Teslimi geciken"
                            deger: sayi
                            isaretRengi: sayi > 0 ? Theme.tehlike : "transparent"
                            altYazi: sayi > 0 ? "Teslim tarihi geçti" : ""
                        }
                        GostergeKarti {
                            readonly property int sayi: root.satinalma.faturasiEksik || 0
                            baslik: "Faturası eksik"
                            deger: sayi
                            isaretRengi: sayi > 0 ? Theme.uyari : "transparent"
                            altYazi: sayi > 0 ? "Fatura bekleniyor" : ""
                        }
                        GostergeKarti {
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
