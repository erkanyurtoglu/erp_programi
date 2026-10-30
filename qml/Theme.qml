pragma Singleton
import QtQuick
import QtCore

// Uygulama genelinde kullanilan ortak tasarim dili (renkler, tipografi, olcu birimleri).
// Iki renk paleti vardir: acik (varsayilan) ve koyu. Koyu palet "Sliper" referans
// projesinden alinmistir. Her renk "koyuMod ? koyu : acik" seklinde tanimlidir;
// ekranlar yalnizca Theme.xxx kullandigi icin tema degisince hepsi kendiliginden
// guncellenir. Her yeni ekran bu dosyadaki degerleri kullanmali, dogrudan hex renk
// yazmamali.
QtObject {
    id: theme

    // --- Tema secimi ---
    // Kullanicinin secimi bilgisayarda kalici tutulur (QSettings). Tema anahtari
    // (TemaDegistirici) dogrudan koyuModuAyarla cagirmaz, degistirmeIstendi'yi
    // yayar: Main.qml once ekranin anlik goruntusunu alir, sonra temayi degistirip
    // goruntuyu soldurur (yumusak gecis).
    readonly property bool koyuMod: ayarlar.koyuMod
    signal degistirmeIstendi()
    function koyuModuAyarla(koyu) {
        ayarlar.koyuMod = koyu
    }

    readonly property Settings ayarlar: Settings {
        category: "Gorunum"
        property bool koyuMod: false
    }

    // --- Zeminler ---
    // Acik temada zemin hafif mavi-gridir; beyaz kartlar onun uzerinde one cikar.
    readonly property color arkaplan: koyuMod ? "#0a0a0d" : "#e9eff8"          // Ana pencere zemini
    readonly property color arkaplanIkincil: koyuMod ? "#0d0d12" : "#f8fafe"   // Kenar cubugu / ust bar gibi ikincil alanlar
    readonly property color panel: koyuMod ? "#12121a" : "#ffffff"             // Kart / panel / input zemini
    readonly property color panelHover: koyuMod ? "#191921" : "#eef3fc"        // Kart / satir uzerine gelince
    readonly property color panelVurgu: koyuMod ? "#16161e" : "#dfe9fc"        // Hafif vurgulu panel (secili satir vb.)

    // --- Kenarlıklar ---
    readonly property color kenarlik: koyuMod ? "#1e2a3f" : "#d3ddec"
    readonly property color kenarlikVurgu: koyuMod ? "#3b82f6" : "#2563eb"     // Odaklanmis/aktif input, secili sekme

    // --- Marka / vurgu rengi (mavi) ---
    readonly property color vurgu: koyuMod ? "#3b82f6" : "#2563eb"
    readonly property color vurguHover: koyuMod ? "#4f8cf7" : "#1d4ed8"
    readonly property color vurguAcik: koyuMod ? "#dce8f5" : "#2563eb"         // Vurgulu metin (Detay butonu, one cikan tutarlar)

    // --- Metin ---
    readonly property color metinBirincil: koyuMod ? "#dce8f5" : "#0f172a"     // Baslik / onemli metin
    readonly property color metinIkincil: koyuMod ? "#9ca3af" : "#475569"      // Normal aciklama metni
    readonly property color metinSoluk: koyuMod ? "#6b7280" : "#64748b"        // Daha az onemli / placeholder
    readonly property color metinCokSoluk: koyuMod ? "#4b5563" : "#8592a8"     // En dusuk vurgulu (tablo basligi vb.)

    // --- Yukseltilmis / vurgulu yuzeyler (ozet kartlari, one cikan tutarlar icin) ---
    readonly property color panelYukseltilmis: koyuMod ? "#161c2c" : "#ebf2fe"     // Vurgu rengine yakin, panel'den bir tık ayrisan zemin
    readonly property color vurguZeminSoluk: koyuMod ? "#182338" : "#dde8fd"       // Vurgu renginin çok soluk, dolgu olarak kullanilabilecek versiyonu
    readonly property color kenarlikVurguSoluk: koyuMod ? "#26436b" : "#a9c2ef"    // Vurgu renginin soluk kenarlik versiyonu (aktif olmayan ama one cikan kartlar icin)

    // --- Tablo baslik satiri (TEKLİF NO, FİRMA ADI ...) ---
    // Acik temada mavi tonlu bir serit; koyu temada sade panel.
    readonly property color tabloBaslikZemin: koyuMod ? "#12121a" : "#dde8fb"
    readonly property color tabloBaslikKenarlik: koyuMod ? "#1e2a3f" : "#c3d5f4"
    readonly property color tabloBaslikMetin: koyuMod ? "#4b5563" : "#3d5a8c"

    // --- Durum renkleri ---
    // "...Acik" renkler metin/simge rengidir: koyu temada parlak, acik temada
    // beyaz zeminde okunabilsin diye koyu tonlu.
    readonly property color basari: "#16a34a"
    readonly property color basariHover: koyuMod ? "#1bbd57" : "#15803d"
    readonly property color basariAcik: koyuMod ? "#4ade80" : "#15803d"
    readonly property color tehlike: "#dc2626"
    readonly property color tehlikeHover: koyuMod ? "#ef4444" : "#b91c1c"
    readonly property color tehlikeAcik: koyuMod ? "#f87171" : "#dc2626"
    readonly property color uyari: koyuMod ? "#f59e0b" : "#d97706"
    readonly property color uyariAcik: koyuMod ? "#fbbf24" : "#b45309"
    readonly property color bilgi: koyuMod ? "#38bdf8" : "#0284c7"             // Kargoda / yolda gibi notr bilgi durumlari

    // Durum rozetleri ve hover dolgulari icin soluk zeminler
    readonly property color basariZemin: koyuMod ? "#0f2417" : "#e7f7ec"
    readonly property color tehlikeZemin: koyuMod ? "#3f1620" : "#fdecec"
    readonly property color tehlikeZeminHover: koyuMod ? "#3f1d24" : "#fbdcdc"
    readonly property color uyariZemin: koyuMod ? "#2e2310" : "#fdf3e1"
    readonly property color uyariZeminHover: koyuMod ? "#3a2a10" : "#fbe7c2"

    // Kose bildirimlerinin (PDF kaydedildi, islem sonucu vb.) yari saydam zeminleri
    readonly property color bildirimBasariZemin: koyuMod ? "#f712241a" : "#f7ecf8f0"
    readonly property color bildirimHataZemin: koyuMod ? "#f7241417" : "#f7fdf0f0"

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
