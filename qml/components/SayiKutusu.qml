import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Tek satirlik Turkce sayi girisi (binlik nokta, ondalik virgul).
//
// ONEMLI -- odak kaybi: deger disaridan "deger" ile verilir ama kutunun
// metnine BAGLANMAZ; yalnizca kutu odakta degilken yazilir. Kullanici
// yazarken "degisti" yayilir ve cagiran taraf modelini gunceller; model
// degisikligi kutuyu yeniden olusturmaz, imlec yerinde kalir. (Eski
// formda her tus vurusunda butun satirlar yeniden olusuyor ve odak
// kayboluyordu.)
TextField {
    id: kok

    // Disaridan gelen deger.
    property real deger: 0
    property int ondalik: 2
    // 0 iken kutu bos gosterilsin mi? (teklif hucresi: "fiyat verilmedi")
    property bool sifirdaBos: false
    property bool kompakt: false
    property bool vurgulu: false
    // Miktar gibi alanlarda gereksiz kusurat yazilmaz: 1 -> "1" (1,000 degil),
    // 2,5 -> "2,5". Girilebilecek basamak yine "ondalik" kadardir.
    property bool sadeGoster: false

    // Kullanici yazdikca / kutudan cikinca yeni deger.
    signal degisti(real yeni)

    readonly property real girilenDeger: bicim.deger

    implicitHeight: kok.kompakt ? 32 : Theme.girdiYuksekligi
    leftPadding: 10
    rightPadding: 10
    color: Theme.metinBirincil
    placeholderTextColor: Theme.metinCokSoluk
    font.family: Theme.fontAilesi
    font.pixelSize: kok.kompakt ? Theme.fontBoyutKucuk + 1 : Theme.fontBoyutNormal
    horizontalAlignment: Text.AlignRight
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radiusKucuk
        color: kok.enabled ? Theme.arkaplan : "transparent"
        border.width: kok.enabled ? 1 : 0
        border.color: kok.activeFocus ? Theme.kenarlikVurgu
                    : kok.vurgulu ? Theme.kenarlikVurguSoluk : Theme.kenarlik
    }

    SayiBicimlendirici {
        id: bicim
        ondalik: kok.ondalik
        odakBitinceTamamla: !kok.sadeGoster
    }

    function yaz() {
        if (kok.sifirdaBos && kok.deger <= 0) {
            kok.text = ""
        } else if (kok.sadeGoster) {
            var basamak = 0
            const carpan = function(b) { return Math.pow(10, b) }
            while (basamak < kok.ondalik
                   && Math.abs(Math.round(kok.deger * carpan(basamak)) - kok.deger * carpan(basamak)) > 1e-6)
                basamak += 1
            kok.text = SayiBicimi.bicimle(kok.deger, basamak)
            kok.cursorPosition = 0
        } else {
            bicim.ayarla(kok.deger)
        }
    }

    Component.onCompleted: kok.yaz()
    onDegerChanged: if (!kok.activeFocus) kok.yaz()
    // Deger dogrudan kutudaki metinden okunur. bicim.deger, bicimlendiricinin
    // metni yeniden yazmasindan once okununca BIR ONCEKI tusun degerini
    // veriyordu ("900" yazilinca 90 kaydediliyordu). textChanged, bicimlendirici
    // metni duzelttiginde de tetiklenir.
    onTextChanged: if (kok.activeFocus) kok.degisti(SayiBicimi.ayikla(kok.text))
    onEditingFinished: kok.degisti(SayiBicimi.ayikla(kok.text))
    // Odak gidince, disaridan duzeltilmis olabilecek degeri goster.
    onActiveFocusChanged: if (!kok.activeFocus) kok.yaz()
}
