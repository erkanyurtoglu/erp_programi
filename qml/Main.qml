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
                    yiginGorunumu.push(satisModuluBileseni, { baslangicSekmesi: 0 });
            }

            onTeklifVerSecildi: {
                yiginGorunumu.push(satisModuluBileseni, { baslangicSekmesi: 0 });
            }

            onCikisYapildi: {
                pencere.oturum = null;
                yiginGorunumu.replace(girisBileseni);
            }
        }
    }

    Component {
        id: satisModuluBileseni
        SatisModuluPage {
            oturum: pencere.oturum
            onAnaMenuyeDon: yiginGorunumu.pop()
        }
    }
}
