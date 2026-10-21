#pragma once

#include <QString>
#include <atomic>

// ----------------------------------------------------------------------
// DONMA TANILAMA
//
// "Program donuyor" sikayetinin kaynagini tahmin etmek yerine OLCEBILMEK
// icin iki parca:
//
//   1) Gunluk dosyasi: qDebug/qInfo/qWarning ciktilari artik ekrana degil
//      (GUI uygulamasinda gorunmuyorlar) bir dosyaya da yazilir.
//      Yol: %LOCALAPPDATA%\Liya\erp_gunluk.txt
//
//   2) UI thread izleyicisi: ayri bir thread, arayuz thread'inin hala
//      "nefes alip almadigini" surekli yoklar. Arayuz 800 ms'den uzun
//      sure cevap veremezse (Windows tam bu durumda pencere basligina
//      "Yanıt Vermiyor" yazar) gunluge uyari dusulur -- ustelik O SIRADA
//      calisan senkron islemin adiyla birlikte. Boylece hangi cagrinin
//      dondurdugu dogrudan gorulur.
// ----------------------------------------------------------------------

// Gunluk dosyasini acar ve mesaj yakalayiciyi kurar. main()'de, QGuiApplication
// olusturulduktan hemen sonra bir kez cagrilir. Gunluk dosyasinin tam yolunu doner.
QString gunlugeYazmayaBasla();

// UI thread izleyicisini baslatir (uygulama kapanirken kendiliginden durur).
// "beklemeEsigiMs": bu sureden uzun suren takilmalar gunluge yazilir.
void uiIzleyicisiniBaslat(int beklemeEsigiMs = 800);

// O an UI thread'inde calisan senkron islemin adi. ErpIslemIzi tarafindan
// set edilir; izleyici takilma aninda bunu rapor eder. Hicbir islem yoksa
// nullptr'dir (yani takilma veritabani disinda bir seyden kaynaklanmistir).
extern std::atomic<const char *> g_aktifUiIslem;

// Senkron (UI thread'ini bloke eden) bir Database cagrisinin omru boyunca
// adini kaydeden RAII yardimcisi. Cagri 300 ms'den uzun surerse, bitince
// suresiyle birlikte gunluge yazilir.
class ErpIslemIzi
{
public:
    explicit ErpIslemIzi(const char *ad);
    ~ErpIslemIzi();

private:
    const char *m_ad;
    const char *m_onceki;
    bool m_uiThreadi;
    qint64 m_baslangicNs;
};

// Database'in senkron metodlarinin basina konur.
#define ERP_IZ(ad) ErpIslemIzi _erpIslemIzi(ad)
