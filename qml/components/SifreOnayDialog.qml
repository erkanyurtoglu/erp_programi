import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Silme ve kayit duzenleme gibi korunan islemler icin yonetici sifresi ister
// (bkz. Database::yoneticiSifresiDogrula). Kullanim:
//     sifreDialogu.iste("Müşteriyi Sil", "\"X\" kalıcı olarak silinsin mi?", "Sil", true,
//                       function() { ...islem... })
TemaDialog {
    id: kok

    property string mesaj: ""
    property var islem: null

    width: 400
    elleKapat: true

    function iste(yeniBaslik, yeniMesaj, yeniOnayMetni, tehlikeliMi, yapilacak) {
        kok.baslik = yeniBaslik
        kok.mesaj = yeniMesaj
        kok.onayMetni = yeniOnayMetni
        kok.tehlikeli = tehlikeliMi === true
        kok.islem = yapilacak
        kok.open()
    }

    onOpened: {
        sifreAlani.text = ""
        hataMesaji.text = ""
        sifreAlani.alan.forceActiveFocus()
    }
    onClosed: kok.islem = null

    onOnaylandi: {
        if (!database.yoneticiSifresiDogrula(sifreAlani.text)) {
            hataMesaji.text = "Şifre yanlış."
            sifreAlani.alan.selectAll()
            sifreAlani.alan.forceActiveFocus()
            return
        }
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

        EtiketliAlan {
            id: sifreAlani
            etiket: "YÖNETİCİ ŞİFRESİ"
            echoMode: TextInput.Password
            onKabulEdildi: kok.onaylandi()
        }

        Label {
            id: hataMesaji
            visible: text.length > 0
            Layout.fillWidth: true
            color: Theme.tehlikeAcik
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
        }
    }
}
