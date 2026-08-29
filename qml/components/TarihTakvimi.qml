import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Kucuk bir takvim: "Ozel Tarih" filtresinde kullaniciya elle "yyyy-aa-gg"
// yazdirmak yerine ay/yil gezinmeli bir MonthGrid uzerinden secim yaptirir.
// Secilen tarih "yyyy-MM-dd" formatinda tarihSecildi sinyali ile disari verilir.
Popup {
    id: takvim

    signal tarihSecildi(string tarih)

    property date goruntulenenAy: new Date()

    width: 260
    padding: 12
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.width: 1
        border.color: Theme.kenarlik
    }

    onOpened: goruntulenenAy = new Date()

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: "‹"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                onClicked: {
                    const d = new Date(takvim.goruntulenenAy)
                    d.setMonth(d.getMonth() - 1)
                    takvim.goruntulenenAy = d
                }
                background: Rectangle { color: "transparent" }
                contentItem: Text {
                    text: "‹"
                    color: Theme.metinBirincil
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: takvim.goruntulenenAy.toLocaleString(Qt.locale("tr_TR"), "MMMM yyyy")
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                font.bold: true
            }

            Button {
                text: "›"
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                onClicked: {
                    const d = new Date(takvim.goruntulenenAy)
                    d.setMonth(d.getMonth() + 1)
                    takvim.goruntulenenAy = d
                }
                background: Rectangle { color: "transparent" }
                contentItem: Text {
                    text: "›"
                    color: Theme.metinBirincil
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: Qt.locale("tr_TR")
            delegate: Text {
                text: model.shortName
                color: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }

        MonthGrid {
            id: ayIzgarasi
            Layout.fillWidth: true
            month: takvim.goruntulenenAy.getMonth()
            year: takvim.goruntulenenAy.getFullYear()
            locale: Qt.locale("tr_TR")

            delegate: Text {
                text: model.day
                color: model.month === ayIzgarasi.month ? Theme.metinBirincil : Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: gunAlani.containsMouse ? Theme.panelHover : "transparent"
                    z: -1
                }

                MouseArea {
                    id: gunAlani
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const secilen = model.date
                        const yyyy = secilen.getFullYear()
                        const mm = String(secilen.getMonth() + 1).padStart(2, "0")
                        const dd = String(secilen.getDate()).padStart(2, "0")
                        takvim.tarihSecildi(yyyy + "-" + mm + "-" + dd)
                        takvim.close()
                    }
                }
            }
        }
    }
}
