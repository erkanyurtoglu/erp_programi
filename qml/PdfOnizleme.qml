pragma Singleton
import QtQuick

// PDF onizleme penceresine her sayfadan ulasmak icin kopru. Pencerenin kendisi
// (components/PdfOnizlemeDialog.qml) Main.qml'de TEK ornek olarak durur; boylece
// "Teklifi Kaydet" sonrasi sayfa degisse bile (revizyon/kopya akisi formu
// kapatip listeye doner) onizleme acik kalir.
QtObject {
    // Main.qml dinler ve pencereyi acar.
    signal acIstendi(string tur, int teklifId, string baslik)

    // Kullanici "İndir"e basip PDF klasore kaydedildiginde. Ornegin Giden
    // Tekliflerim, uretim PDF'i indirilince "Üretim PDF" tarihini yenilemek
    // icin dinler. "pdf" database.*PdfOlustur sonucudur ({tur, teklifId, ...}),
    // "dosyaYolu" kaydedilen dosyanin yoludur.
    signal kaydedildi(var pdf, string dosyaYolu)

    // Pencereyi HEMEN acar; PDF pencere icinde "hazırlanıyor" gosterilerek
    // uretilir (hata olursa da pencerede yazar).
    // "tur": "teklif" (database.teklifPdfOlustur) veya "uretim" (uretimPdfOlustur).
    function ac(tur, teklifId, baslik) {
        acIstendi(tur, teklifId, baslik)
    }
}
