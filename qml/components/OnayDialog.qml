import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetici sifresi GEREKTIRMEYEN basit onay penceresi. SifreOnayDialog ile
// ayni kullanim sekline sahiptir, sadece sifre alani yoktur:
//
//     onayDialogu.iste("Maliyet Uyarısı", "Maliyet satış fiyatından yüksek...",
//                      "Yine de Kaydet", false, function() { ...islem... })
//
// Nerede kullanildigi: kullanicinin bir SEYI YANLIS YAPIYOR OLABILECEGI ama
// yasaklanmasinin dogru olmadigi durumlar -- mukerrer firma adi, maliyetin
// satis fiyatindan yuksek olmasi, kalici silme yerine arsivleme onerisi.
TemaDialog {
    id: kok

    property string mesaj: ""
    property var islem: null

    width: 440
    elleKapat: true

    function iste(yeniBaslik, yeniMesaj, yeniOnayMetni, tehlikeliMi, yapilacak) {
        kok.baslik = yeniBaslik
        kok.mesaj = yeniMesaj
        kok.onayMetni = yeniOnayMetni
        kok.tehlikeli = tehlikeliMi === true
        kok.islem = yapilacak
        kok.open()
    }

    onClosed: kok.islem = null

    onOnaylandi: {
        const yapilacak = kok.islem
        kok.close()
        if (yapilacak)
            yapilacak()
    }

    contentItem: ColumnLayout {
        spacing: 12

        Label {
            visible: kok.mesaj.length > 0
            Layout.fillWidth: true
            text: kok.mesaj
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            wrapMode: Text.WordWrap
        }
    }
}
