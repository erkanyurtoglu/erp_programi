import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

ApplicationWindow {
    id: pencere
    width: 1400
    height: 900
    visible: true
    visibility: Window.Maximized
    title: "Liya ERP"
    color: Theme.arkaplan

    // Giris yapan kullanicinin bilgileri (basarili girisYap() sonrasi doldurulur).
    property var oturum: null

    // Baglanti kurulamadiysa kullaniciyi bilgilendir; ekranin geri kalani
    // yine de yuklenir ama listeler bos gelir (Database ic loglarina bakilabilir).
    Rectangle {
        visible: !database.baglantiHazir
        z: 10
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        color: Theme.tehlike

        Label {
            anchors.centerIn: parent
            color: "white"
            font.family: Theme.fontAilesi
            font.bold: true
            text: "Veritabanına bağlanılamadı. EXCALIBUR\\SQLEXPRESS sunucusunun ve ODBC sürücüsünün çalıştığından emin olun."
        }
    }

    StackView {
        id: yiginGorunumu
        anchors.fill: parent
        initialItem: girisBileseni
    }

    Component {
        id: girisBileseni
        GirisPage {
            onGirisBasarili: (sonuc) => {
                pencere.oturum = sonuc;
                yiginGorunumu.replace(anaMenuBileseni);
            }
        }
    }

    Component {
        id: anaMenuBileseni
        AnaMenuPage {
            adSoyad: pencere.oturum ? pencere.oturum.adSoyad : ""
            moduller: pencere.oturum ? pencere.oturum.moduller : []

            onModulSecildi: (modulKodu) => {
                if (modulKodu === "SATIS")
                    yiginGorunumu.push(gecmisTekliflerBileseni);
            }

            onTeklifVerSecildi: {
                // TODO: Teklif Ver ekrani hazir olunca buraya baglanacak.
            }

            onCikisYapildi: {
                pencere.oturum = null;
                yiginGorunumu.replace(girisBileseni);
            }
        }
    }

    Component {
        id: gecmisTekliflerBileseni
        Item {
            GecmisTekliflerPage {
                anchors.fill: parent
                anchors.topMargin: 60
            }

            // Geri donus icin basit bir ust bar (Ana Menu'ye donmek icin).
            Button {
                id: geriButonu
                text: "◀ Ana Menü"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 16
                z: 5
                height: 34
                onClicked: yiginGorunumu.pop()
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik
                }
                contentItem: Text {
                    text: geriButonu.text
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
