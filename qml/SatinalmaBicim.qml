pragma Singleton
import QtQuick
import erp_programi

// Satinalma ekranlarinin ortak gosterim kurallari: belge numaralari, durum
// adlari/renkleri, para ve tarih bicimi. Her sayfa kendi kopyasini yazarsa
// ayni durum bir ekranda sari, otekinde mavi gorunur.
QtObject {
    id: bicim

    // Teslimat sekilleri (Database.cpp: gecerliTeslimatSekliMi ile ayni kume).
    readonly property var teslimatSekilleri: ["Kargo", "Ambar / Nakliye",
                                              "Tedarikçi getirecek", "Biz alacağız"]
    readonly property var birimler: ["Montaj", "Elektrik", "Üretim", "Yazılım", "Diğer"]
    readonly property var paraBirimleri: ["TL", "USD", "EUR"]
    readonly property var olcuBirimleri: ["adet", "metre", "kg", "gram", "litre", "m²", "m³",
                                          "paket", "kutu", "rulo", "takım", "set", "çift",
                                          "saat", "hizmet"]

    // Birim kutusunun onerileri: yazilan harfle baslayanlar; kutuda zaten
    // bilinen bir birim varsa (odaga girildiginde) hepsi.
    function birimOnerileri(metin) {
        const m = (metin || "").trim().toLocaleLowerCase("tr")
        if (m.length === 0 || olcuBirimleri.indexOf(m) >= 0)
            return olcuBirimleri
        return olcuBirimleri.filter(b => b.indexOf(m) === 0)
    }

    function kargoluMu(sekil) {
        return sekil === "Kargo" || sekil === "Ambar / Nakliye"
    }

    function sifirla(no, uzunluk) {
        var s = String(no)
        while (s.length < uzunluk)
            s = "0" + s
        return s
    }

    function siparisNo(no) { return no > 0 ? "SA-" + sifirla(no, 4) : "—" }
    function talepNo(no) { return no > 0 ? "TLP-" + sifirla(no, 4) : "Yeni" }

    function para(tutar) { return SayiBicimi.bicimle(tutar || 0, 2) + " ₺" }
    function dovizli(tutar, pb) {
        const simge = pb === "USD" ? " $" : pb === "EUR" ? " €" : " ₺"
        return SayiBicimi.bicimle(tutar || 0, 2) + simge
    }
    function miktar(m) {
        // 10,000 yerine 10; 2,5 kg gibi kusurat varsa gosterilir.
        const yuvarlak = Math.round((m || 0) * 1000) / 1000
        const ondalik = yuvarlak === Math.floor(yuvarlak) ? 0
                      : (Math.round(yuvarlak * 100) === yuvarlak * 100 ? 2 : 3)
        return SayiBicimi.bicimle(yuvarlak, ondalik)
    }

    // QDate (JS Date) ya da "yyyy-MM-dd" -> "gg.aa.yyyy"
    function tarih(t) {
        if (!t)
            return ""
        if (typeof t === "string") {
            const p = t.split("-")
            return p.length === 3 ? p[2] + "." + p[1] + "." + p[0] : t
        }
        if (isNaN(t.getTime()))
            return ""
        return Qt.formatDate(t, "dd.MM.yyyy")
    }

    function bugun() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    function gunEkle(gun) {
        const t = new Date()
        t.setDate(t.getDate() + gun)
        return Qt.formatDate(t, "yyyy-MM-dd")
    }

    // ---- Siparis durumu ----
    // "Kargoda" veritabani degeridir; kargo ile gelmeyen sipariste "Yolda" yazilir.
    // Kalani beklenmeden kapatilan siparis 'Teslim Alındı'dir; "Eksik Kapatıldı" yazilir.
    function siparisDurumAdi(durum, teslimatSekli, eksikKapatildi) {
        if (durum === "Teslim Alındı" && eksikKapatildi === true)
            return "Eksik Kapatıldı"
        if (durum === "Kargoda")
            return kargoluMu(teslimatSekli) || !teslimatSekli ? "Kargoda" : "Yolda"
        if (durum === "Patron Onayı Bekliyor")
            return "Onay Bekliyor"
        return durum
    }

    function siparisDurumRengi(durum) {
        switch (durum) {
        case "Patron Onayı Bekliyor": return Theme.uyariAcik
        case "Sipariş Verildi":       return Theme.vurgu
        case "Kargoda":               return Theme.bilgi
        case "Kısmi Teslim":          return Theme.uyariAcik
        case "Teslim Alındı":         return Theme.basariAcik
        case "Reddedildi":            return Theme.tehlikeAcik
        default:                      return Theme.metinSoluk   // İptal
        }
    }

    function talepDurumRengi(durum) {
        switch (durum) {
        case "Teklif Toplanıyor": return Theme.vurgu
        case "Kısmen Siparişte":  return Theme.uyariAcik
        case "Siparişe Dönüştü":  return Theme.basariAcik
        default:                  return Theme.metinSoluk
        }
    }

    function acikMi(durum) {
        return durum !== "Teslim Alındı" && durum !== "İptal" && durum !== "Reddedildi"
    }
}
