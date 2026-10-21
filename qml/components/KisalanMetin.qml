import QtQuick
import QtQuick.Controls

// Dar bir sutuna sigmadigi icin "…" ile kirpilan metin.
//
// Tablolarda sutun genisligi sabittir; uzun firma adlari, urun aciklamalari veya
// kullanici adlari kacinilmaz olarak kirpilir. Bu bilesen, metin GERCEKTEN
// kirpildiginda (Text.truncated) uzerine gelindiginde tam halini bir ipucunda
// gosterir -- sigan metinlerde ipucu hic acilmaz, boylece her hucrede gereksiz
// bir kutu belirmez.
//
// Fareyi MouseArea yerine HoverHandler ile dinliyoruz: MouseArea hover olaylarini
// yutup altindaki satirin vurgusunu (satir hover rengini) bozuyordu; HoverHandler
// pasiftir, satirin kendi fare alani calismaya devam eder.
Text {
    id: kok

    // Ipucunda gosterilecek metin. Bos birakilirsa metnin kendisi gosterilir;
    // hucrede kisaltilmis bir deger varsa (orn. "EÖ") buraya tam karsiligi
    // ("Emre Özkan") verilebilir.
    property string ipucuMetni: ""

    // Ipucu, metin sigsa bile acilsin mi? (ipucuMetni metinden farkli ek bilgi
    // tasidiginda ise yarar.)
    property bool ipucuHepGoster: false

    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter

    HoverHandler { id: fareIzleyici }

    ToolTip.visible: fareIzleyici.hovered
                     && (kok.ipucuHepGoster || kok.truncated)
                     && ToolTip.text.length > 0
    ToolTip.delay: 400
    ToolTip.text: kok.ipucuMetni.length > 0 ? kok.ipucuMetni : kok.text
}
