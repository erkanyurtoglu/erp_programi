import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Uygulama temasina uygun modal pencere: baslik (vurgu cubuguyla), icerik ve
// sagda Iptal + onay butonlari. Basic stilin acik renkli standardButtons'u
// yerine kullanilir.
//
// elleKapat true ise onay butonu pencereyi kapatmaz, sadece onaylandi()
// yayinlar; dogrulama/kayit basariliysa cagiran taraf close() eder.
Dialog {
    id: kok

    property string baslik: ""
    property string onayMetni: "Tamam"
    property string iptalMetni: "İptal"
    property bool onayGorunur: true
    property bool onayEtkin: true
    property bool tehlikeli: false
    property bool elleKapat: false
    property color vurguRengi: tehlikeli ? Theme.tehlike : Theme.vurgu

    signal onaylandi()

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    padding: 20
    topPadding: 12

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    header: Item {
        implicitHeight: baslikSatiri.implicitHeight + 20

        RowLayout {
            id: baslikSatiri
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 4
                Layout.preferredHeight: 16
                radius: 2
                color: kok.vurguRengi
            }
            Label {
                Layout.fillWidth: true
                text: kok.baslik
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.bold: true
                font.pixelSize: Theme.fontBoyutOrta
                elide: Text.ElideRight
            }
        }
    }

    footer: Item {
        implicitHeight: Theme.girdiYuksekligi + 20

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 10

            Item { Layout.fillWidth: true }

            Button {
                id: iptalButonu
                Layout.preferredWidth: Math.max(100, iptalYazi.implicitWidth + 32)
                Layout.preferredHeight: Theme.girdiYuksekligi
                onClicked: kok.reject()
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: iptalButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: iptalButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    id: iptalYazi
                    text: kok.iptalMetni
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                id: onayButonu
                visible: kok.onayGorunur
                enabled: kok.onayEtkin
                Layout.preferredWidth: Math.max(110, onayYazi.implicitWidth + 32)
                Layout.preferredHeight: Theme.girdiYuksekligi
                onClicked: {
                    if (kok.elleKapat)
                        kok.onaylandi()
                    else
                        kok.accept()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    opacity: onayButonu.enabled ? 1 : 0.4
                    color: kok.tehlikeli
                           ? (onayButonu.hovered ? Theme.tehlikeHover : Theme.tehlike)
                           : (onayButonu.hovered ? Theme.vurguHover : Theme.vurgu)
                }
                contentItem: Text {
                    id: onayYazi
                    text: kok.onayMetni
                    color: "#ffffff"
                    font.family: Theme.fontAilesi
                    font.bold: true
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
