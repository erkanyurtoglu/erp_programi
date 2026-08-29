import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Giris yapan kullanicinin yetkili oldugu modulleri gosteren ana menu.
// modulKodu degerleri Database::kullaniciModulleriniGetir()'den (dolayisiyla
// dbo.moduller.ModulKodu'dan) geliyor: SATIS, SATINALMA, STOK, MUHASEBE, YONETIM.
Rectangle {
    id: kok
    color: Theme.arkaplan

    // AnaMenuPage.qml disaridan set edilir (Main.qml, girisYap() sonucundan).
    property string adSoyad: ""
    property var moduller: []

    signal modulSecildi(string modulKodu)
    signal teklifVerSecildi()
    signal cikisYapildi()

    // Her modul icin baslik/aciklama/ikon/vurgu rengi. Renkler Sliper referansindaki
    // gibi her modulu kendi kimligiyle ayirt etmek icin farklilastirildi; marka
    // vurgusu (Theme.vurgu) yine de en sik kullanilan modul olan Satis'ta.
    readonly property var modulGorunumleri: ({
        "SATIS":      { baslik: "Satış / Teklif", aciklama: "Teklif oluştur, ürün ekle, PDF indir", ikon: "belge",  renk: Theme.vurgu,  aktif: true },
        "STOK":       { baslik: "Stok",           aciklama: "Envanter ve stok hareketleri",         ikon: "kutu",   renk: "#f59e0b",    aktif: false },
        "SATINALMA":  { baslik: "Satınalma",      aciklama: "Tedarikçi ve sipariş yönetimi",        ikon: "sepet",  renk: "#14b8a6",    aktif: false },
        "MUHASEBE":   { baslik: "Muhasebe",       aciklama: "Fatura ve muhasebe kayıtları",         ikon: "cuzdan", renk: "#22c55e",    aktif: false },
        "YONETIM":    { baslik: "Yönetim",        aciklama: "Kullanıcı ve sistem ayarları",         ikon: "disli",  renk: "#8b5cf6",    aktif: false }
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

            Button {
                id: cikisButonu
                text: "Çıkış Yap"
                onClicked: kok.cikisYapildi()
                Layout.preferredWidth: 120
                Layout.preferredHeight: 38
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: cikisButonu.hovered ? "#3a1414" : "transparent"
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

        // Hizli eylem: yeni teklif olusturma. Ayri, vurgulu bir sekilde en usttte
        // cunku is akisinin en sik kullanilan eylemi bu.
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
            columns: 5
            rowSpacing: 18
            columnSpacing: 18
            Layout.fillWidth: true

            Repeater {
                model: kok.moduller

                delegate: Rectangle {
                    id: kart
                    Layout.fillWidth: true
                    Layout.preferredHeight: 210
                    radius: Theme.radiusBuyuk
                    color: kart.gorunum.aktif && kartAlani.containsMouse ? Theme.panelHover : Theme.panel
                    border.width: kart.gorunum.aktif && kartAlani.containsMouse ? 1.5 : 1
                    border.color: kart.gorunum.aktif && kartAlani.containsMouse ? Theme.kenarlikVurgu : Theme.kenarlik

                    readonly property var gorunum: kok.modulGorunumleri[modelData.modulKodu]
                        ?? { baslik: modelData.modulAdi, aciklama: "", ikon: "disli", renk: Theme.metinSoluk, aktif: false }

                    // Secili/aktif durumda kart cevresine hafif bir mavi parlama halkasi.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.kenarlikVurgu
                        opacity: kart.gorunum.aktif && kartAlani.containsMouse ? 0.35 : 0
                        z: -1

                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Behavior on border.color { ColorAnimation { duration: 120 } }

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
                        anchors.margins: 20
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            Layout.alignment: Qt.AlignHCenter
                            radius: 28
                            color: kart.gorunum.renk
                            opacity: kart.gorunum.aktif ? 0.14 : 0.07

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
                                width: 26
                                height: 26
                                tur: kart.gorunum.ikon
                                renk: kart.gorunum.aktif ? kart.gorunum.renk : Theme.metinSoluk
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 3

                            Label {
                                text: kart.gorunum.baslik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutOrta
                                font.bold: true
                                color: kart.gorunum.aktif ? Theme.metinBirincil : Theme.metinSoluk
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Label {
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

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: durumEtiketi.implicitWidth + 20
                            radius: 12
                            color: kart.gorunum.aktif ? "#14532d" : Theme.panelVurgu
                            border.width: 1
                            border.color: kart.gorunum.aktif ? Theme.basari : Theme.kenarlik

                            Label {
                                id: durumEtiketi
                                anchors.centerIn: parent
                                text: kart.gorunum.aktif ? "✓ Aktif" : "Yakında"
                                font.family: Theme.fontAilesi
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.3
                                color: kart.gorunum.aktif ? Theme.basariAcik : Theme.metinCokSoluk
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
