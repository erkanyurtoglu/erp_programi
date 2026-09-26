#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <memory>

class QQuickImageProvider;
struct PdfBelgeDeposu;

// PdfOnizleyici: onizleme penceresindeki PDF'i sayfa sayfa RESIM olarak cizer.
// Cizimi Qt PDF (QPdfDocument, pdfium) yapar; tamamen islemcide calisir.
// (Once QtWebEngine'in Chromium PDF goruntuleyicisi denendi: acilisi saniyeler
// suruyor, kaydirmasi takiliyordu. Sonra Windows.Data.Pdf kullanildi: arka
// planda Direct3D'ye bagli oldugu icin ekran karti/DXGI hatalarinda program
// cokuyordu.)
//
// Akis: QML ac(yol) ile belgeyi acar ve sayfa olculerini alir; her sayfa
// "image://pdfsayfa/<anahtar>/<sayfaNo>" kaynagiyla, istenen genislikte,
// arka plan is parcaciginda cizilir. Pencere kapaninca kapat(anahtar) --
// boylece dosya serbest kalir ve silinebilir.
class PdfOnizleyici : public QObject
{
    Q_OBJECT

public:
    explicit PdfOnizleyici(QObject *parent = nullptr);
    ~PdfOnizleyici() override;

    // Donen: {basarili (bool), anahtar (int), sayfalar (list<{genislik, yukseklik}>,
    // PDF birimiyle -- sadece en/boy orani icin), hata (string)}.
    Q_INVOKABLE QVariantMap ac(const QString &yol);

    // Acik belgeyi birakir.
    Q_INVOKABLE void kapat(int anahtar);

    // QML motoruna "pdfsayfa" adiyla eklenecek resim saglayici (sahipligi
    // motor alir).
    QQuickImageProvider *resimSaglayici() const;

private:
    std::shared_ptr<PdfBelgeDeposu> m_depo;
};
