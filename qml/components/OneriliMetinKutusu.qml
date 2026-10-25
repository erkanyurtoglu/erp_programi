import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yazarken oneri listesi acan metin kutusu (kalem adi, "ne icin", firma adi).
//
// Serbest metnin bedeli yazim dagilmasidir ("pres", "Pres cihazı",
// "pres cih."); daha once yazilanlar oneri olarak dusunce ayni ad tekrar
// kullanilir. Klavye: asagi/yukari ile gezilir, Enter ile secilir, Esc
// kapatir.
//
//   oneriKaynagi(metin)  -> dizi        (veritabani ya da yerel liste)
//   oneriMetni(oge)      -> ana satir    (varsayilan: ogenin kendisi)
//   oneriAltMetni(oge)   -> ikinci satir (bos ise tek satir)
//   oneriSecildi(oge)    -> secim yapildi; metin oneriMetni ile doldurulur
TemaMetinKutusu {
    id: kok

    property var oneriKaynagi: function(metin) { return [] }
    property var oneriMetni: function(oge) { return String(oge) }
    property var oneriAltMetni: function(oge) { return "" }
    // Veritabanina gidiliyorsa her tusa sorgu atmamak icin gecikme.
    property int gecikme: 300
    property int enAzHarf: 1
    // Odaga girince liste hemen acilsin (sabit secenekli kutular: birim).
    property bool odaktaAc: false
    // Sagda acilir liste oku (TemaComboBox'taki gibi); tiklaninca liste
    // acilir / kapanir.
    property bool okGoster: false

    rightPadding: kok.okGoster ? 28 : 10

    signal oneriSecildi(var oge)

    function listeyiDoldur() {
        const metin = kok.text.trim()
        const liste = metin.length >= kok.enAzHarf ? kok.oneriKaynagi(metin) : []
        oneriListesi.model = liste
        oneriListesi.currentIndex = -1
        if (liste.length > 0 && kok.activeFocus)
            oneriPaneli.open()
        else
            oneriPaneli.close()
    }

    function sec(oge) {
        kok.text = kok.oneriMetni(oge)
        oneriPaneli.close()
        kok.oneriSecildi(oge)
    }

    onTextEdited: zamanlayici.restart()
    onActiveFocusChanged: {
        if (!kok.activeFocus)
            kapatmaZamanlayici.restart()
        else if (kok.odaktaAc)
            kok.listeyiDoldur()
    }

    Keys.onPressed: (olay) => {
        if (!oneriPaneli.opened)
            return
        if (olay.key === Qt.Key_Down) {
            oneriListesi.currentIndex = Math.min(oneriListesi.count - 1, oneriListesi.currentIndex + 1)
            olay.accepted = true
        } else if (olay.key === Qt.Key_Up) {
            oneriListesi.currentIndex = Math.max(0, oneriListesi.currentIndex - 1)
            olay.accepted = true
        } else if ((olay.key === Qt.Key_Return || olay.key === Qt.Key_Enter)
                   && oneriListesi.currentIndex >= 0) {
            kok.sec(oneriListesi.model[oneriListesi.currentIndex])
            olay.accepted = true
        } else if (olay.key === Qt.Key_Escape) {
            oneriPaneli.close()
            olay.accepted = true
        }
    }

    Timer {
        id: zamanlayici
        interval: kok.gecikme
        onTriggered: kok.listeyiDoldur()
    }

    // Odak baska kutuya gecerken listedeki tiklama once islensin diye
    // kapatma bir an geciktiriliyor.
    Timer {
        id: kapatmaZamanlayici
        interval: 150
        onTriggered: if (!kok.activeFocus) oneriPaneli.close()
    }

    Text {
        visible: kok.okGoster
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        color: okFare.containsMouse || oneriPaneli.opened ? Theme.metinBirincil : Theme.metinSoluk
        font.pixelSize: 14
        MouseArea {
            id: okFare
            anchors.fill: parent
            anchors.margins: -8
            enabled: kok.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (oneriPaneli.opened) {
                    oneriPaneli.close()
                    return
                }
                kok.forceActiveFocus()
                kok.listeyiDoldur()
            }
        }
    }

    Popup {
        id: oneriPaneli
        y: kok.height + 2
        width: Math.max(kok.width, 260)
        implicitHeight: Math.min(oneriListesi.contentHeight + 4, 240)
        padding: 2
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            radius: Theme.radiusKucuk
            color: Theme.panelYukseltilmis
            border.width: 1
            border.color: Theme.kenarlik
        }

        ListView {
            id: oneriListesi
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: ItemDelegate {
                id: oneriSatiri
                required property var modelData
                required property int index
                readonly property string altMetin: kok.oneriAltMetni(oneriSatiri.modelData)

                width: ListView.view ? ListView.view.width : 0
                height: oneriSatiri.altMetin.length > 0 ? 42 : 30
                hoverEnabled: true

                background: Rectangle {
                    radius: Theme.radiusKucuk - 2
                    color: oneriSatiri.hovered || oneriListesi.currentIndex === oneriSatiri.index
                           ? Theme.panelHover : "transparent"
                }

                contentItem: ColumnLayout {
                    spacing: 0
                    KisalanMetin {
                        Layout.fillWidth: true
                        text: kok.oneriMetni(oneriSatiri.modelData)
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk + 1
                    }
                    KisalanMetin {
                        Layout.fillWidth: true
                        visible: oneriSatiri.altMetin.length > 0
                        text: oneriSatiri.altMetin
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                    }
                }

                onClicked: kok.sec(oneriSatiri.modelData)
            }
        }
    }
}
