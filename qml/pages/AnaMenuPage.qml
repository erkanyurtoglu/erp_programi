import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

Rectangle {
    id: kok
    color: Theme.arkaplan

    property string adSoyad: ""
    property var moduller: []

    signal modulSecildi(string modulKodu)
    signal teklifVerSecildi()
    signal cikisYapildi()

    readonly property var modulGorunumleri: ({
        "SATIS":      { baslik: "Satış / Teklif", aciklama: "Teklif oluştur, ürün ekle, PDF indir", ikon: "belge",  renk: Theme.vurgu,  aktif: true },
        "SATINALMA":  { baslik: "Satınalma",      aciklama: "Tedarikçi ve sipariş yönetimi",        ikon: "sepet",  renk: Theme.koyuMod ? "#14b8a6" : "#0d9488", aktif: true },
        "MUHASEBE":   { baslik: "Muhasebe",       aciklama: "Faturalanacak teklifler, fatura ve irsaliye no", ikon: "cuzdan", renk: Theme.uyari, aktif: true },
        "YONETIM":    { baslik: "Yönetim",        aciklama: "Personel, rol ve sistem ayarları",     ikon: "disli",  renk: Theme.koyuMod ? "#8b5cf6" : "#7c3aed", aktif: true }
    })

    ColumnLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 32
        anchors.bottomMargin: 32
        width: Math.min(parent.width - 64, 1200)
        spacing: 24

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Image {
                source: "qrc:/qt/qml/erp_programi/logo.png"
                sourceSize.height: 48
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                Layout.preferredHeight: 48
            }

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Liya ERP"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    font.letterSpacing: 0.3
                    color: Theme.metinBirincil
                }
                Label {
                    text: "Hoş geldiniz, " + kok.adSoyad
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            TemaDegistirici {
                Layout.rightMargin: 4
            }

            Button {
                id: cikisButonu
                text: "Çıkış Yap"
                onClicked: kok.cikisYapildi()
                Layout.preferredWidth: 120
                Layout.preferredHeight: 38
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: cikisButonu.hovered ? Theme.tehlikeZemin : "transparent"
                    border.color: Theme.tehlike
                    border.width: 1
                }
                contentItem: Text {
                    text: "Çıkış Yap"
                    color: Theme.tehlikeAcik
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }


        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            radius: Theme.radiusBuyuk
            visible: kok.moduller.some(m => m.modulKodu === "SATIS")

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.vurgu }
                GradientStop { position: 1.0; color: "#2f6fe0" }
            }

            MouseArea {
                id: yeniTeklifAlani
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: kok.teklifVerSecildi()
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusBuyuk
                color: "#ffffff"
                opacity: yeniTeklifAlani.containsMouse ? 0.07 : 0
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 18

                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    color: "#ffffff"
                    opacity: 0.16

                    Label {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 26
                        font.bold: true
                        color: "#ffffff"
                    }
                }

                ColumnLayout {
                    spacing: 3
                    Label {
                        text: "Yeni Teklif Oluştur"
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutOrta
                        font.bold: true
                        color: "#ffffff"
                    }
                    Label {
                        text: "Müşteri seç, ürün ekle, teklifi hazırla ve PDF olarak indir"
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                        color: "#e6efff"
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: "›"
                    font.pixelSize: 26
                    font.bold: true
                    color: "#ffffff"
                }
            }
        }

        Label {
            text: "MODÜLLER"
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            font.letterSpacing: 1.5
            font.bold: true
            color: Theme.metinCokSoluk
        }

        Label {
            visible: kok.moduller.length === 0
            text: "Henüz size atanmış bir modül yetkisi yok. Lütfen yöneticinizle iletişime geçin."
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
        }

        GridLayout {
            columns: 4
            rowSpacing: 24
            columnSpacing: 24
            Layout.alignment: Qt.AlignHCenter

            Repeater {
                model: kok.moduller

                delegate: Rectangle {
                    id: kart
                    Layout.preferredWidth: 250
                    Layout.preferredHeight: 340
                    radius: Theme.radiusBuyuk
                    color: kart.vurgulu ? Theme.panelHover : Theme.panel
                    border.width: kart.vurgulu ? 1.5 : 1
                    border.color: kart.vurgulu ? kart.gorunum.renk : Theme.kenarlik
                    scale: kart.vurgulu ? 1.04 : 1.0
                    z: kart.vurgulu ? 1 : 0

                    readonly property var gorunum: kok.modulGorunumleri[modelData.modulKodu]
                        ?? { baslik: modelData.modulAdi, aciklama: "", ikon: "disli", renk: Theme.metinSoluk, aktif: false }
                    readonly property bool vurgulu: kart.gorunum.aktif && kartAlani.containsMouse

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: parent.radius + 4
                        color: "transparent"
                        border.width: 2
                        border.color: kart.gorunum.renk
                        opacity: kart.vurgulu ? 0.25 : 0
                        z: -1

                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    MouseArea {
                        id: kartAlani
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: kart.gorunum.aktif ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (kart.gorunum.aktif)
                                kok.modulSecildi(modelData.modulKodu);
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 22

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            Layout.preferredWidth: 96
                            Layout.preferredHeight: 96
                            Layout.alignment: Qt.AlignHCenter
                            radius: 48
                            // Koyu temada daire (ve icindeki ikon) toptan soluklastirilir; acik
                            // temada bu ikonu da silik gosterdigi icin yalnizca dolgu saydamdir.
                            readonly property real dolguOpakligi: kart.vurgulu ? 0.22 : (kart.gorunum.aktif ? 0.14 : 0.07)
                            color: Theme.koyuMod ? kart.gorunum.renk
                                                 : Qt.rgba(kart.gorunum.renk.r, kart.gorunum.renk.g, kart.gorunum.renk.b, dolguOpakligi)
                            opacity: Theme.koyuMod ? dolguOpakligi : 1
                            scale: kart.vurgulu ? 1.08 : 1.0

                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: "transparent"
                                border.width: 1
                                border.color: kart.gorunum.renk
                                opacity: kart.gorunum.aktif ? 0.5 : 0.25
                            }

                            ModulIkonu {
                                anchors.centerIn: parent
                                width: 44
                                height: 44
                                tur: kart.gorunum.ikon
                                renk: kart.gorunum.aktif ? kart.gorunum.renk : Theme.metinSoluk
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: kart.gorunum.baslik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutBaslik
                                font.bold: true
                                color: kart.gorunum.aktif ? Theme.metinBirincil : Theme.metinSoluk
                                Layout.alignment: Qt.AlignHCenter
                            }

                            KisalanMetin {
                                text: kart.gorunum.aciklama
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                color: Theme.metinSoluk
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Item { Layout.fillHeight: true }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
