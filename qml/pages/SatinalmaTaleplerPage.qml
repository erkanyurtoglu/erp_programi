import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Talepler -- satinalma mudurunun "ne lazim" listesi. Her satir talebin bir
// sonraki adimini tek rozetle soyler: siparise hazir / fiyat bekleniyor /
// tedarikci belirlenecek. Acik talepler ihtiyac tarihine gore siralanir;
// tarihi gecmis ya da yaklasan talep kirmizi/sari gorunur.
Item {
    id: root

    property bool duzenleyebilir: true
    property string filtre: "acik"
    property var talepler: []

    signal talepAc(int talepId)
    signal yeniTalep()

    function yukle() {
        root.talepler = database.talepListesiGetir(root.filtre, aramaKutusu.text)
    }

    // Talep acik mi: siparise donusmemis kalemi var ya da siparisleri yolda.
    function acikMi(t) {
        return t.durum === "Teklif Toplanıyor" || t.durum === "Kısmen Siparişte"
               || (t.durum === "Siparişe Dönüştü" && t.acikSiparisSayisi > 0)
    }

    // Acik talebin bir sonraki adimi.
    function sonrakiAdim(t) {
        if (t.durum === "Siparişe Dönüştü" && t.acikSiparisSayisi > 0)
            return { metin: "Teslimat bekleniyor", renk: SatinalmaBicim.siparisDurumRengi("Kargoda") }
        if (t.durum !== "Teklif Toplanıyor" && t.durum !== "Kısmen Siparişte")
            return { metin: t.durum === "Siparişe Dönüştü" ? "Tamamlandı" : t.durum,
                     renk: SatinalmaBicim.talepDurumRengi(t.durum) }
        if (t.hazirKalem > 0)
            return { metin: "Siparişe hazır", renk: Theme.basariAcik }
        if (t.fiyatBekleyenKalem > 0)
            return { metin: "Fiyat bekleniyor", renk: Theme.uyariAcik }
        return { metin: "Tedarikçi belirlenecek", renk: Theme.vurgu }
    }

    function adimAyrintisi(t) {
        var p = []
        if (t.hazirKalem > 0) p.push(t.hazirKalem + " hazır")
        if (t.fiyatBekleyenKalem > 0) p.push(t.fiyatBekleyenKalem + " fiyat bekliyor")
        if (t.kaynakBekleyenKalem > 0) p.push(t.kaynakBekleyenKalem + " tedarikçisiz")
        if (t.siparisliKalemSayisi > 0) p.push(t.siparisliKalemSayisi + " siparişte")
        if (t.acikSiparisSayisi > 0) p.push(t.acikSiparisSayisi + " sipariş bekleniyor")
        return p.join(" · ")
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        ColumnLayout {
            spacing: 2
            Label {
                text: "Talepler"
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutBaslik
                font.bold: true
                color: Theme.metinBirincil
            }
            Label {
                text: root.talepler.length + " talep"
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                color: Theme.metinSoluk
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TemaMetinKutusu {
                id: aramaKutusu
                Layout.fillWidth: true
                placeholderText: "Talep no, kişi, malzeme, cihaz, tedarikçi ara..."
                onTextEdited: aramaZamanlayici.restart()
                Timer {
                    id: aramaZamanlayici
                    interval: 350
                    onTriggered: root.yukle()
                }
            }

            Repeater {
                model: [ { kod: "acik", ad: "Açık" }, { kod: "tamam", ad: "Tamamlanan" },
                         { kod: "iptal", ad: "İptal" }, { kod: "tumu", ad: "Tümü" } ]
                delegate: SuzgecHapi {
                    required property var modelData
                    metin: modelData.ad
                    secili: root.filtre === modelData.kod
                    onTiklandi: {
                        root.filtre = modelData.kod
                        root.yukle()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

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
                        Baslik { text: "TALEP"; Layout.preferredWidth: 100 }
                        Baslik { text: "İSTEYEN"; Layout.preferredWidth: 160 }
                        Baslik { text: "KALEMLER"; Layout.fillWidth: true }
                        Baslik { text: "İHTİYAÇ"; Layout.preferredWidth: 110 }
                        Baslik { text: "DURUM"; Layout.preferredWidth: 230 }
                        Item { Layout.preferredWidth: 12 }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.talepler
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }

                    delegate: Rectangle {
                        id: satir
                        required property var modelData

                        readonly property bool acik: root.acikMi(satir.modelData)
                        readonly property var kalan: satir.modelData.ihtiyacGunuKaldi
                        readonly property bool tarihVar: satir.kalan !== undefined && satir.kalan !== null
                        readonly property bool gecmis: satir.acik && satir.tarihVar && satir.kalan < 0
                        readonly property bool yakin: satir.acik && satir.tarihVar && satir.kalan >= 0 && satir.kalan <= 3
                        readonly property var adim: root.sonrakiAdim(satir.modelData)

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

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14

                            ColumnLayout {
                                Layout.preferredWidth: 100
                                spacing: 2
                                Label {
                                    text: SatinalmaBicim.talepNo(satir.modelData.talepNo)
                                    color: Theme.vurgu
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    font.bold: true
                                }
                                Label {
                                    text: SatinalmaBicim.tarih(satir.modelData.talepTarihi)
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                }
                            }

                            ColumnLayout {
                                // Icindeki fillWidth metin, sutunu esnetmesin
                                // (baslik satiriyla hizali kalsin).
                                Layout.preferredWidth: 160
                                Layout.fillWidth: false
                                spacing: 2
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: satir.modelData.isteyenKisi || "—"
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk + 1
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: satir.modelData.isteyenBirim || ""
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
                                    text: satir.modelData.kalemOzeti
                                          + (satir.modelData.kalemSayisi > 4 ? " …" : "")
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk + 1
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: satir.modelData.kalemSayisi + " kalem"
                                          + (satir.modelData.neIcinOzeti ? "  ·  " + satir.modelData.neIcinOzeti : "")
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 110
                                spacing: 2
                                Label {
                                    text: SatinalmaBicim.tarih(satir.modelData.ihtiyacTarihi) || "—"
                                    color: satir.gecmis ? Theme.tehlikeAcik : satir.yakin ? Theme.uyariAcik : Theme.metinIkincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk + 1
                                    font.bold: satir.gecmis || satir.yakin
                                }
                                Label {
                                    visible: satir.gecmis || satir.yakin
                                    text: satir.gecmis ? (-satir.kalan) + " gün geçti"
                                         : satir.kalan === 0 ? "bugün" : satir.kalan + " gün kaldı"
                                    color: satir.gecmis ? Theme.tehlikeAcik : Theme.uyariAcik
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 230
                                Layout.fillWidth: false
                                spacing: 3
                                DurumRozeti {
                                    metin: satir.adim.metin
                                    renk: satir.adim.renk
                                    dolu: satir.acik
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    visible: satir.acik && text.length > 0
                                    text: root.adimAyrintisi(satir.modelData)
                                    color: Theme.metinSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                }
                            }

                            Label {
                                Layout.preferredWidth: 12
                                text: "›"
                                color: satirFare.containsMouse ? Theme.metinBirincil : Theme.metinCokSoluk
                                font.pixelSize: 18
                            }
                        }

                        MouseArea {
                            id: satirFare
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.talepAc(satir.modelData.talepId)
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                anchors.topMargin: 38
                kayitSayisi: root.talepler.length
                aramaVar: aramaKutusu.text.length > 0
                bosMetin: root.filtre === "acik" ? "Açık talep yok." : "Bu grupta talep yok."
            }
        }
    }
}
