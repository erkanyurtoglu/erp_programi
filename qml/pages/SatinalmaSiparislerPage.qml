import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Siparisler -- talepten bagimsiz arama ve toplu takip: kapiya gelen koli
// (firma / kargo takip no ile bulunur), gecikenler, patron onayi ve fatura
// bekleyenler. Gunluk "siparisim ne durumda?" takibi talep ekranindan yapilir.
//
// Suzgec teslim oncesi bir grup (Bekleyen / Geciken / Onay bekleyen) ise
// TESLIMAT sutunu, teslim sonrasi bir grup ise FATURA sutunu gosterilir.
//
// Her satirda yalnizca siparisin SIRADAKI isinin butonu vardir (Onay alındı /
// Kargoya verildi / Teslim al / Fatura gir). Ayrinti, teslim, teslimat ve
// fatura acilir pencerelerde yapilir (SiparisPencereleri, talep ekraninda da
// ayni pencereler kullanilir); satira tiklamak ayrintiyi acar.
//
// Kargo alanlari yalnizca teslimat sekli Kargo / Ambar olan sipariste
// gosterilir; tedarikcinin getirdigi ya da bizim aldigimiz malda anlamsizdir.
Item {
    id: root

    property bool duzenleyebilir: true
    property var ozet: ({})

    property string filtre: "acik"
    readonly property bool bekleyenMi: root.filtre === "acik" || root.filtre === "geciken"
                                       || root.filtre === "onay"
    property var siparisler: []
    property string hata: ""
    property string bilgi: ""

    signal talepAc(int talepId)
    signal degisiklikOldu()

    function yukle() {
        root.siparisler = database.siparisListesiGetir(root.filtre, aramaKutusu.text)
    }

    // Baska ekrandan belirli bir siparise gelmek icin.
    function ac(satinalmaId) {
        aramaKutusu.text = ""
        root.hata = ""
        root.bilgi = ""
        if (!pencereler.sec(satinalmaId))
            return
        const durum = pencereler.detay.durum || ""
        root.filtre = durum === "İptal" || durum === "Reddedildi" ? "iptal"
                    : SatinalmaBicim.acikMi(durum) ? "acik" : "tamam"
        root.yukle()
        pencereler.ayrintiAc(satinalmaId)
    }

    function filtreUygula(yeni) {
        root.filtre = yeni
        root.yukle()
    }

    // Yukleme sekmeye gecildiginde yapilir (bkz. SatinAlmaModuluPage); modul
    // acilirken gorunmeyen iki listenin sorgusu atilmaz.

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    // Siparisin siradaki isinin butonlari (satirda ve ayrintida ayni). Satir
    // ici bilesen sayfanin id'lerini goremez; eylemler sinyalle disari verilir.

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Baslik ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Siparişler"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.siparisler.length + " sipariş"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                Layout.maximumWidth: 420
                visible: text.length > 0
                text: root.hata.length > 0 ? root.hata : root.bilgi
                color: root.hata.length > 0 ? Theme.tehlikeAcik : Theme.basariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
            }
        }

        // ---- Arama + suzgecler ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TemaMetinKutusu {
                id: aramaKutusu
                Layout.fillWidth: true
                placeholderText: "Sipariş no, firma, malzeme, kargo takip / site sipariş no ara..."
                onTextEdited: aramaZamanlayici.restart()
                Timer {
                    id: aramaZamanlayici
                    interval: 350
                    onTriggered: root.yukle()
                }
            }

            Repeater {
                model: [ { kod: "acik", ad: "Bekleyen", sayi: root.ozet.acikSiparis || 0 },
                         { kod: "geciken", ad: "Geciken", sayi: root.ozet.geciken || 0, renk: Theme.tehlikeAcik },
                         { kod: "onay", ad: "Onay bekleyen", sayi: root.ozet.onayBekleyen || 0, renk: Theme.uyariAcik },
                         { kod: "fatura", ad: "Fatura bekleyen", sayi: root.ozet.faturasiEksik || 0, renk: Theme.uyariAcik },
                         { kod: "tamam", ad: "Teslim alınan", sayi: 0 },
                         { kod: "iptal", ad: "İptal", sayi: 0 } ]
                delegate: SuzgecHapi {
                    required property var modelData
                    metin: modelData.ad
                    sayi: modelData.sayi
                    renk: modelData.renk || Theme.vurgu
                    secili: root.filtre === modelData.kod
                    onTiklandi: root.filtreUygula(modelData.kod)
                }
            }
        }

        // ---- Liste ----
        Rectangle {
            id: listePaneli
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            readonly property bool genis: listePaneli.width > 980

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: Theme.arkaplanIkincil
                    radius: Theme.radiusNormal

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        component Baslik: Label {
                            color: Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        Baslik { text: "SİPARİŞ"; Layout.preferredWidth: 96 }
                        Baslik { text: "TEDARİKÇİ / KALEMLER"; Layout.fillWidth: true }
                        Baslik { text: root.bekleyenMi ? "TESLİMAT" : "FATURA"; Layout.preferredWidth: 170; visible: listePaneli.genis }
                        Baslik { text: "DURUM"; Layout.preferredWidth: 120 }
                        Baslik { text: "TUTAR"; Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight }
                        Baslik { text: "İŞLEM"; Layout.preferredWidth: 250 }
                    }
                }

                ListView {
                    id: liste
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.siparisler
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }

                    delegate: Rectangle {
                        id: satir
                        required property var modelData

                        readonly property bool gecikti: SatinalmaBicim.acikMi(satir.modelData.durum)
                                                        && satir.modelData.beklenenTeslimTarihi
                                                        && satir.modelData.gecikmeGunu > 0
                        readonly property bool faturasiYok: (satir.modelData.faturaNo || "").length === 0
                        readonly property bool iptalMi: satir.modelData.durum === "İptal"
                                                        || satir.modelData.durum === "Reddedildi"

                        width: ListView.view ? ListView.view.width : 0
                        height: 64
                        color: satirFare.containsMouse ? Theme.panelHover : "transparent"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.kenarlik
                            opacity: 0.6
                        }

                        // Satirin tamamina tiklamak ayrintiyi acar; butonlar
                        // bunun ustunde kalir.
                        MouseArea {
                            id: satirFare
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pencereler.ayrintiAc(satir.modelData.satinalmaId)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14

                            ColumnLayout {
                                Layout.preferredWidth: 96
                                spacing: 2
                                Label {
                                    text: SatinalmaBicim.siparisNo(satir.modelData.siparisNo)
                                    color: Theme.vurgu
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    font.bold: true
                                }
                                Label {
                                    text: SatinalmaBicim.tarih(satir.modelData.satinalmaTarihi)
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: satir.modelData.tedarikciAdi
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    font.bold: true
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: satir.modelData.kalemSayisi + " kalem: " + satir.modelData.kalemOzeti
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 170
                                Layout.fillWidth: false
                                visible: listePaneli.genis
                                spacing: 2
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: root.bekleyenMi
                                          ? (satir.modelData.teslimatSekli || "—")
                                            + (satir.modelData.kargoTakipNo ? " · " + satir.modelData.kargoTakipNo : "")
                                          : satir.iptalMi ? "—"
                                          : satir.faturasiYok ? "Girilmedi" : satir.modelData.faturaNo
                                    color: !root.bekleyenMi && satir.faturasiYok && !satir.iptalMi
                                           ? Theme.uyariAcik : Theme.metinIkincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                }
                                Label {
                                    visible: root.bekleyenMi && text.length > 0
                                    text: satir.gecikti
                                          ? satir.modelData.gecikmeGunu + " gün gecikti"
                                          : satir.modelData.beklenenTeslimTarihi
                                            ? "beklenen " + SatinalmaBicim.tarih(satir.modelData.beklenenTeslimTarihi)
                                            : ""
                                    color: satir.gecikti ? Theme.tehlikeAcik : Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                    font.bold: satir.gecikti
                                }
                            }

                            Item {
                                Layout.preferredWidth: 120
                                Layout.fillHeight: true
                                DurumRozeti {
                                    anchors.verticalCenter: parent.verticalCenter
                                    metin: SatinalmaBicim.siparisDurumAdi(satir.modelData.durum, satir.modelData.teslimatSekli,
                                                                         satir.modelData.eksikKapatildi)
                                    renk: satir.gecikti ? Theme.tehlikeAcik : SatinalmaBicim.siparisDurumRengi(satir.modelData.durum)
                                    dolu: true
                                }
                            }

                            Label {
                                Layout.preferredWidth: 110
                                horizontalAlignment: Text.AlignRight
                                text: SatinalmaBicim.para(satir.modelData.toplamTutarTL)
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                            }

                            Item {
                                Layout.preferredWidth: 250
                                Layout.fillHeight: true
                                SiparisEylemleri {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.duzenleyebilir
                                    kayit: satir.modelData
                                    onOnayIstendi: (id) => pencereler.onayIsaretle(id)
                                    onSevkiyatIstendi: (id) => pencereler.sevkiyatAc(id, true)
                                    onTeslimIstendi: (id) => pencereler.teslimAc(id)
                                    onFaturaIstendi: (id) => pencereler.faturaAc(id)
                                }
                            }
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                anchors.topMargin: 38
                kayitSayisi: root.siparisler.length
                aramaVar: aramaKutusu.text.length > 0
                bosMetin: root.filtre === "acik" ? "Bekleyen sipariş yok."
                        : root.filtre === "geciken" ? "Geciken sipariş yok."
                        : root.filtre === "onay" ? "Onay bekleyen sipariş yok."
                        : root.filtre === "fatura" ? "Faturası beklenen sipariş yok."
                        : root.filtre === "tamam" ? "Teslim alınmış sipariş yok."
                        : "Bu grupta sipariş yok."
            }
        }
    }

    SiparisPencereleri {
        id: pencereler
        anchors.fill: parent
        duzenleyebilir: root.duzenleyebilir
        onTalepAc: (talepId) => root.talepAc(talepId)
        onHataOldu: (mesaj) => {
            root.hata = mesaj
            root.bilgi = ""
        }
        onIslemYapildi: (mesaj) => {
            root.hata = ""
            root.bilgi = mesaj
            root.yukle()
            root.degisiklikOldu()
        }
    }
}
