import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim / Sistem Ayarlari: dbo.ayarlar'daki ayarlar, gruplara ayrilmis tek
// bir form. Sayi ayarlari satirda duzenlenir; metin ayarlari (varsayilan satis
// sozlesmesi) "Düzenle" ile acilan Satış Sözleşmesi penceresinde. Hangi
// ayarlarin listelenecegi ve sinirlari C++ tarafindaki ayarTanimlari() listesinden gelir (SqlYardimcilari.cpp);
// bu ekran o listeye gore kendini kurar.
//
// Kaydetme yonetici sifresiyle onaylanir; yalnizca degisen ayarlar
// gonderilir ve hepsi tek islemde yazilir (Database::ayarlariKaydet).
Item {
    id: root

    property bool duzenleyebilir: true
    property bool otomatikYukle: true

    property var ayarlar: []
    property bool tabloVar: true
    // anahtar -> ekrandaki deger / yuklenen deger (sayi ayarinda sayi, metin
    // ayarinda metin; bos metin = fabrika metni)
    property var duzenlenen: ({})
    property var yuklenen: ({})
    property bool yukleniyor: false
    property string listeHatasi: ""

    readonly property var gruplar: {
        const sonuc = []
        for (const a of root.ayarlar) {
            let g = sonuc.find(x => x.grup === a.grup)
            if (!g) {
                g = { grup: a.grup, ayarlar: [] }
                sonuc.push(g)
            }
            g.ayarlar.push(a)
        }
        return sonuc
    }

    readonly property var degisenler: {
        const sonuc = {}
        for (const anahtar in root.duzenlenen) {
            const yeni = root.duzenlenen[anahtar]
            const eski = root.yuklenen[anahtar]
            const farkli = typeof yeni === "number" ? Math.abs(yeni - eski) > 1e-9 : yeni !== eski
            if (farkli)
                sonuc[anahtar] = yeni
        }
        return sonuc
    }
    readonly property bool degisti: Object.keys(root.degisenler).length > 0
    readonly property bool saltOkunur: !root.duzenleyebilir || !root.tabloVar

    function sayfayiYukle() {
        formHatasi.text = ""
        basariMesaji.text = ""
        root.listeHatasi = ""
        root.yukleniyor = true
        database.ayarListesiGetirBaslat()
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onAyarListesiHazir(sonuc) {
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            if (!sonuc || sonuc.ayarlar === undefined) {
                root.listeHatasi = "Ayarlar yüklenemedi: veritabanına bağlanılamadı."
                return
            }

            const degerler = {}
            for (const a of sonuc.ayarlar)
                degerler[a.anahtar] = a.tur === "metin" ? a.metin : a.deger
            root.tabloVar = sonuc.tabloVar
            root.yuklenen = degerler
            root.duzenlenen = Object.assign({}, degerler)
            root.ayarlar = sonuc.ayarlar
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
            root.listeHatasi = "Ayarlar sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    function degerDegistir(anahtar, deger) {
        const kopya = Object.assign({}, root.duzenlenen)
        kopya[anahtar] = deger
        root.duzenlenen = kopya
        basariMesaji.text = ""
    }

    function kaydet() {
        const sonuc = database.ayarlariKaydet(root.degisenler)
        if (!sonuc.basarili) {
            formHatasi.text = sonuc.hata
            return
        }
        formHatasi.text = ""
        root.sayfayiYukle()
        basariMesaji.text = "Ayarlar kaydedildi."
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Label {
            text: "Sistem Ayarları"
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutBaslik
            font.bold: true
            color: Theme.metinBirincil
        }

        Rectangle {
            visible: !root.tabloVar && !root.yukleniyor
            Layout.fillWidth: true
            Layout.maximumWidth: 720
            Layout.preferredHeight: uyariYazisi.implicitHeight + 20
            radius: Theme.radiusKucuk
            color: Theme.uyariZemin
            border.width: 1
            border.color: Theme.uyari
            Label {
                id: uyariYazisi
                anchors.fill: parent
                anchors.margins: 10
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
                text: "Ayar tablosu bulunamadı (db/17 betiği çalıştırılmamış). "
                      + "Varsayılan değerler gösteriliyor; kaydedilemez."
                color: Theme.uyariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
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
                contentHeight: grupSutunu.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: grupSutunu
                    width: Math.min(kaydirma.width, 720)
                    spacing: 20

                    Repeater {
                        model: root.gruplar

                        delegate: ColumnLayout {
                            id: grupBlogu
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: grupBlogu.modelData.grup.toLocaleUpperCase(Qt.locale("tr_TR"))
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: ayarSutunu.implicitHeight
                                radius: Theme.radiusNormal
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.kenarlik

                                ColumnLayout {
                                    id: ayarSutunu
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 0

                                    Repeater {
                                        model: grupBlogu.modelData.ayarlar

                                        delegate: Item {
                                            id: ayarSatiri
                                            required property var modelData
                                            required property int index
                                            readonly property bool metinMi: ayarSatiri.modelData.tur === "metin"

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Math.max(64, metinSutunu.implicitHeight + 24)

                                            Rectangle {
                                                visible: ayarSatiri.index > 0
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 16
                                                height: 1
                                                color: Theme.kenarlik
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 16
                                                spacing: 16

                                                ColumnLayout {
                                                    id: metinSutunu
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    Label {
                                                        text: ayarSatiri.modelData.baslik
                                                        color: Theme.metinBirincil
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: Theme.fontBoyutNormal
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.WordWrap
                                                    }
                                                    Label {
                                                        visible: text.length > 0
                                                        text: ayarSatiri.modelData.notMetni
                                                        color: Theme.metinSoluk
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: Theme.fontBoyutKucuk
                                                        Layout.fillWidth: true
                                                        wrapMode: Text.WordWrap
                                                    }
                                                    Label {
                                                        visible: text.length > 0
                                                        text: ayarSatiri.modelData.guncellemeTarihi.length > 0
                                                              ? "Son değişiklik: " + ayarSatiri.modelData.guncellemeTarihi : ""
                                                        color: Theme.metinCokSoluk
                                                        font.family: Theme.fontAilesi
                                                        font.pixelSize: 10
                                                    }
                                                }

                                                // ---- Metin ayari: durum + Düzenle ----
                                                Label {
                                                    visible: ayarSatiri.metinMi
                                                    text: {
                                                        const m = root.duzenlenen[ayarSatiri.modelData.anahtar]
                                                        return (m === undefined || m.length === 0) ? "Standart metin" : "Düzenlenmiş"
                                                    }
                                                    color: Theme.metinSoluk
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: Theme.fontBoyutKucuk
                                                }
                                                TemaButon {
                                                    visible: ayarSatiri.metinMi
                                                    kucuk: true
                                                    text: root.saltOkunur ? "Görüntüle" : "Düzenle"
                                                    onClicked: metinDialogu.ac(ayarSatiri.modelData)
                                                }

                                                // ---- Sayi ayari ----
                                                SayiKutusu {
                                                    visible: !ayarSatiri.metinMi
                                                    Layout.preferredWidth: 160
                                                    enabled: !root.saltOkunur
                                                    ondalik: ayarSatiri.metinMi ? 0 : ayarSatiri.modelData.ondalik
                                                    sadeGoster: true
                                                    deger: !ayarSatiri.metinMi && root.duzenlenen[ayarSatiri.modelData.anahtar] !== undefined
                                                           ? root.duzenlenen[ayarSatiri.modelData.anahtar] : 0
                                                    onDegisti: (yeni) => root.degerDegistir(ayarSatiri.modelData.anahtar, yeni)
                                                }

                                                Label {
                                                    visible: !ayarSatiri.metinMi
                                                    Layout.preferredWidth: 32
                                                    text: ayarSatiri.modelData.birim || ""
                                                    color: Theme.metinSoluk
                                                    font.family: Theme.fontAilesi
                                                    font.pixelSize: Theme.fontBoyutKucuk
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.ayarlar.length
                bosMetin: "Tanımlı ayar yok."
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 720
            visible: !root.saltOkunur
            spacing: 8

            Label {
                id: formHatasi
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }
            Label {
                id: basariMesaji
                visible: text.length > 0 && formHatasi.text.length === 0
                Layout.fillWidth: true
                color: Theme.basariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }
            Item {
                visible: formHatasi.text.length === 0 && basariMesaji.text.length === 0
                Layout.fillWidth: true
            }

            TemaButon {
                text: "Vazgeç"
                visible: root.degisti
                onClicked: {
                    formHatasi.text = ""
                    root.duzenlenen = Object.assign({}, root.yuklenen)
                }
            }
            TemaButon {
                text: "Kaydet"
                tur: "birincil"
                enabled: root.degisti
                onClicked: {
                    formHatasi.text = ""
                    sifreDialogu.iste("Ayarları Kaydet", "", "Kaydet", false,
                                      function() { root.kaydet() })
                }
            }
        }
    }

    SifreOnayDialog { id: sifreDialogu }

    // Varsayilan sozlesme, Teklif Ver'deki "Satış Sözleşmesi" penceresiyle
    // duzenlenir. varsayilanModu'nda hicbir madde gizlenmez; kosullu maddelerin
    // yaninda hangi tekliflerde basilacagi yazar. "Tamam" yalnizca formu
    // gunceller; kalici kayit sayfanin "Kaydet"iyle (yonetici sifresiyle) yapilir.
    SozlesmeDuzenleDialog {
        id: metinDialogu
        property string anahtar: ""
        property string fabrikaMetni: ""

        varsayilanModu: true
        varsayilanButonMetni: "Standart Metne Dön"
        saltOkunur: root.saltOkunur

        function ac(ayar) {
            metinDialogu.anahtar = ayar.anahtar
            metinDialogu.fabrikaMetni = ayar.varsayilanMetin
            metinDialogu.baslik = ayar.baslik
            metinDialogu.varsayilanMetin = ayar.varsayilanMetin
            metinDialogu.teklifVerisi = {
                dil: ayar.anahtar.endsWith("_EN") ? "EN" : "TR",
                varsayilanModu: true,
                // Ornek {{GECERLILIK_TARIHI}} ekrandaki sureyle hesaplansin.
                gecerlilikGunu: root.duzenlenen["TEKLIF_GECERLILIK_GUNU"] || 0
            }
            const m = root.duzenlenen[ayar.anahtar]
            metinDialogu.metin = (m && m.length > 0) ? m : ayar.varsayilanMetin
            metinDialogu.open()
        }

        // Fabrika metniyle ayni metin bos saklanir (= fabrika metni).
        onKaydedildi: function(yeniMetin) {
            const temiz = yeniMetin.trim()
            root.degerDegistir(metinDialogu.anahtar,
                               temiz === metinDialogu.fabrikaMetni.trim() ? "" : temiz)
        }
    }
}
