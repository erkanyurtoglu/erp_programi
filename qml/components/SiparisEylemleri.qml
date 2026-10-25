import QtQuick
import QtQuick.Layouts
import erp_programi

// Siparisin SIRADAKI isinin butonlari: Onay alındı / Kargoya verildi /
// Teslim al / Fatura gir. Siparis listesinde, siparis ayrintisinda ayni
// kurallarla gosterilir; eylemler sinyalle verilir (bkz. SiparisPencereleri).
RowLayout {
    id: ey
    property var kayit: ({})
    // Satirda kismi teslimde fatura butonu gosterilmez (once teslim).
    property bool tumu: false
    // Siparis ayrintisinda fatura, Fatura kartindan girilir; buton cikmaz.
    property bool faturaGoster: true
    readonly property string durum: ey.kayit.durum || ""
    readonly property int kayitId: ey.kayit.satinalmaId || 0
    readonly property bool kargolu: SatinalmaBicim.kargoluMu(ey.kayit.teslimatSekli || "")
    readonly property bool faturasiYok: (ey.kayit.faturaNo || "").length === 0

    signal onayIstendi(int satinalmaId)
    signal sevkiyatIstendi(int satinalmaId)
    signal teslimIstendi(int satinalmaId)
    signal faturaIstendi(int satinalmaId)

    spacing: 6

    TemaButon {
        visible: ey.durum === "Patron Onayı Bekliyor"
        tur: "uyari"
        kucuk: true
        text: "Onay Alındı"
        onClicked: ey.onayIstendi(ey.kayitId)
    }
    TemaButon {
        visible: ey.durum === "Sipariş Verildi" && ey.kayit.teslimatSekli !== "Biz alacağız"
        kucuk: true
        text: ey.kargolu ? "Kargoya Verildi" : "Yola Çıktı"
        onClicked: ey.sevkiyatIstendi(ey.kayitId)
    }
    TemaButon {
        visible: ey.durum === "Sipariş Verildi" || ey.durum === "Kargoda" || ey.durum === "Kısmi Teslim"
        tur: "basari"
        kucuk: true
        text: ey.durum === "Kısmi Teslim" ? "Kalanı Teslim Al" : "Teslim Al"
        onClicked: ey.teslimIstendi(ey.kayitId)
    }
    TemaButon {
        visible: ey.faturaGoster && ey.faturasiYok && (ey.durum === "Teslim Alındı" || (ey.tumu && ey.durum === "Kısmi Teslim"))
        tur: "uyari"
        kucuk: true
        text: "Fatura Gir"
        onClicked: ey.faturaIstendi(ey.kayitId)
    }
}
