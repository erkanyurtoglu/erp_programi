import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Satinalma modulunun kabuk (shell) ekrani: solda sabit yan menu, sagda secili
// sekmenin icerigi (SatisModuluPage ile ayni yapi).
//
// Sekmeler (adim adim eklenir):
//    Tedarikcilerim  -- tedarikci ekle / duzenle / arsivle   (HAZIR)
//    Satinalma Gir   -- tedarikciden alinan urunlerin kaydi   (siradaki adim)
//    Satinalma Gecmisi                                        (siradaki adim)
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0
    signal anaMenuyeDon()

    // Rol yetkileri (bkz. Database::girisYap -> "moduller"). Duzenleme yetkisi
    // yoksa ekrandaki degistirme butonlari gizlenir; asil denetim sunucu
    // tarafindadir (Database::modulDuzenleyebilirMi).
    function modulYetkisi(kod) {
        const liste = root.oturum && root.oturum.moduller ? root.oturum.moduller : []
        return liste.find(m => m.modulKodu === kod) || null
    }
    readonly property bool satinalmaDuzenleyebilir: {
        const m = root.modulYetkisi("SATINALMA")
        return m !== null && m.duzenleyebilir === true
    }

    Component.onCompleted: tedarikcilerimPage.sayfayiYukle(1)

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Sol yan menu ----
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.arkaplanIkincil

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.kenarlik
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4

                Label {
                    text: "SATINALMA"
                    color: Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.bold: true
                    Layout.bottomMargin: 8
                }

                component YanMenuButonu: Rectangle {
                    id: buton
                    property string metin: ""
                    property bool secili: false
                    signal tiklandi()

                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: Theme.radiusKucuk
                    color: secili ? Theme.panelVurgu : (alan.containsMouse ? Theme.panelHover : "transparent")
                    border.width: secili ? 1 : 0
                    border.color: Theme.kenarlikVurgu

                    Rectangle {
                        visible: buton.secili
                        width: 3
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        radius: 2
                        color: Theme.vurgu
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: buton.secili ? 20 : 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: buton.metin
                        color: buton.secili ? Theme.metinBirincil : Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        font.bold: buton.secili
                    }

                    MouseArea {
                        id: alan
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: buton.tiklandi()
                    }
                }

                YanMenuButonu {
                    metin: " Ana Menü"
                    Layout.bottomMargin: 8
                    onTiklandi: root.anaMenuyeDon()
                }

                YanMenuButonu {
                    metin: "Tedarikçilerim"
                    secili: icerikYiginlar.currentIndex === 0
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 0
                        tedarikcilerimPage.sayfayiYukle(1)
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ---- Sag icerik ----
        StackLayout {
            id: icerikYiginlar
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.baslangicSekmesi

            TedarikcilerimPage {
                id: tedarikcilerimPage
                otomatikYukle: false
                duzenleyebilir: root.satinalmaDuzenleyebilir
            }
        }
    }
}
