import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Uygulama temasina uygun ComboBox: koyu acilir liste, tema renginde ok ve
// secenekler. Basic stilin beyaz popup'i ve koyu (gorunmeyen) oku yerine
// kullanilir. Kenarlik/zemin cagiran taraftaki Rectangle'dan gelir, bu yuzden
// background bos birakilir.
ComboBox {
    id: kok

    background: null
    font.family: Theme.fontAilesi
    font.pixelSize: Theme.fontBoyutNormal

    contentItem: Text {
        text: kok.displayText
        color: Theme.metinBirincil
        font: kok.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: 12
        rightPadding: kok.indicator.width + 4
    }

    indicator: Text {
        x: kok.width - width - 12
        y: (kok.height - height) / 2
        text: "▾"
        color: kok.hovered || kok.popup.visible ? Theme.metinBirincil : Theme.metinSoluk
        font.pixelSize: 14
    }

    delegate: ItemDelegate {
        id: secenek
        required property int index
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth
        height: 32
        highlighted: kok.highlightedIndex === index

        contentItem: Text {
            text: secenek.modelData
            color: kok.currentIndex === secenek.index ? Theme.vurguAcik : Theme.metinIkincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            font.bold: kok.currentIndex === secenek.index
            verticalAlignment: Text.AlignVCenter
            leftPadding: 4
        }
        background: Rectangle {
            radius: Theme.radiusKucuk - 2
            color: secenek.highlighted ? Theme.panelHover
                 : (kok.currentIndex === secenek.index ? Theme.vurguZeminSoluk : "transparent")
        }
    }

    popup: Popup {
        y: kok.height + 4
        width: kok.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: kok.popup.visible ? kok.delegateModel : null
            currentIndex: kok.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.kenarlik
        }
    }
}
