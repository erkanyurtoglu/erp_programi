import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import erp_programi

// Uygulama temasina uygun buton. Satinalma ekranlarinda her sayfanin kendi
// Button + background + contentItem ucluyusunu tekrar yazmasi yerine
// kullanilir.
//
//   tur: "birincil"  -> dolu mavi (sayfanin ana eylemi: Kaydet, Olustur)
//        "ikincil"   -> cerceveli (Yenile, Satir ekle)
//        "tehlike"   -> cerceveli kirmizi (Iptal et)
//        "basari"    -> cerceveli yesil (Teslim al)
//        "uyari"     -> cerceveli sari (Patron onayladi)
//        "sade"      -> cercevesiz, sadece metin (geri, kucuk eylemler)
Button {
    id: kok

    property string tur: "ikincil"
    property bool kucuk: false

    readonly property color anaRenk: kok.tur === "tehlike" ? Theme.tehlikeAcik
                                   : kok.tur === "basari" ? Theme.basariAcik
                                   : kok.tur === "uyari" ? Theme.uyariAcik
                                   : kok.tur === "sade" ? Theme.metinIkincil
                                   : Theme.metinIkincil

    implicitHeight: kok.kucuk ? 30 : Theme.girdiYuksekligi
    implicitWidth: Math.max(kok.kucuk ? 60 : 88, yazi.implicitWidth + (kok.kucuk ? 24 : 36))
    hoverEnabled: true
    // Tiklaninca odagi alir: yazilmakta olan kutu (fiyat, miktar) boylece
    // editingFinished ile kesinlesir, "Kaydet"e basildiginda yarim deger
    // kaydedilmez.
    focusPolicy: Qt.StrongFocus

    background: Rectangle {
        radius: Theme.radiusKucuk
        opacity: kok.enabled ? 1 : 0.4
        color: kok.tur === "birincil"
               ? (kok.hovered ? Theme.vurguHover : Theme.vurgu)
               : (kok.hovered ? Theme.panelHover : "transparent")
        border.width: kok.tur === "birincil" || kok.tur === "sade" ? 0 : 1
        border.color: kok.tur === "ikincil" ? (kok.hovered ? Theme.metinSoluk : Theme.kenarlik)
                                            : kok.anaRenk
    }

    contentItem: Text {
        id: yazi
        text: kok.text
        opacity: kok.enabled ? 1 : 0.5
        color: kok.tur === "birincil" ? "#ffffff" : kok.anaRenk
        font.family: Theme.fontAilesi
        font.pixelSize: kok.kucuk ? Theme.fontBoyutKucuk : Theme.fontBoyutNormal
        font.bold: kok.tur === "birincil"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
