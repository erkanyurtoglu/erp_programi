pragma Singleton
import QtQuick

// Uygulama genelinde kullanilan ortak tasarim dili (renkler, tipografi, olcu birimleri).
// Renk paleti "Sliper" referans projesinden alinmistir: koyu, modern, kurumsal bir
// dashboard estetigi (parlak beyaz WPF gorunumunun tam tersi). Her yeni ekran bu
// dosyadaki degerleri kullanmali, dogrudan hex renk yazmamali -- boylece tum
// uygulama tek bir yerden tutarli kalir ve ileride tema degisikligi tek dosyada yapilir.
QtObject {
    id: theme

    // --- Zeminler ---
    readonly property color arkaplan: "#0a0a0d"        // Ana pencere zemini (en koyu)
    readonly property color arkaplanIkincil: "#0d0d12" // Kenar cubugu / ust bar gibi ikincil alanlar
    readonly property color panel: "#12121a"           // Kart / panel / input zemini
    readonly property color panelHover: "#191921"      // Kart / satir uzerine gelince
    readonly property color panelVurgu: "#16161e"      // Hafif vurgulu panel (secili satir vb.)

    // --- Kenarlıklar ---
    readonly property color kenarlik: "#1e2a3f"
    readonly property color kenarlikVurgu: "#3b82f6"   // Odaklanmis/aktif input, secili sekme

    // --- Marka / vurgu rengi (mavi) ---
    readonly property color vurgu: "#3b82f6"
    readonly property color vurguHover: "#4f8cf7"
    readonly property color vurguAcik: "#dce8f5"       // Vurgu renginin acik/metin versiyonu

    // --- Metin ---
    readonly property color metinBirincil: "#dce8f5"   // Baslik / onemli metin (kirik beyaz)
    readonly property color metinIkincil: "#9ca3af"    // Normal aciklama metni
    readonly property color metinSoluk: "#6b7280"      // Daha az onemli / placeholder
    readonly property color metinCokSoluk: "#4b5563"   // En dusuk vurgulu (tablo basligi vb.)

    // --- Yukseltilmis / vurgulu yuzeyler (ozet kartlari, one cikan tutarlar icin) ---
    readonly property color panelYukseltilmis: "#161c2c"       // Vurgu rengine yakin, panel'den bir tık daha aydinlik zemin
    readonly property color vurguZeminSoluk: "#182338"         // Vurgu renginin çok soluk, dolgu olarak kullanilabilecek versiyonu
    readonly property color kenarlikVurguSoluk: "#26436b"      // Vurgu renginin soluk kenarlik versiyonu (aktif olmayan ama one cikan kartlar icin)

    // --- Durum renkleri ---
    readonly property color basari: "#16a34a"
    readonly property color basariAcik: "#4ade80"
    readonly property color tehlike: "#dc2626"
    readonly property color tehlikeHover: "#ef4444"
    readonly property color tehlikeAcik: "#f87171"
    readonly property color uyari: "#f59e0b"

    // --- Tipografi ---
    readonly property string fontAilesi: "Segoe UI"
    readonly property int fontBoyutKucuk: 11
    readonly property int fontBoyutNormal: 13
    readonly property int fontBoyutOrta: 15
    readonly property int fontBoyutBaslik: 22
    readonly property int fontBoyutBuyukBaslik: 28

    // --- Olculer ---
    readonly property int radiusKucuk: 6
    readonly property int radiusNormal: 8
    readonly property int radiusBuyuk: 12
    readonly property int bosluk: 12
    readonly property int girdiYuksekligi: 40
}
