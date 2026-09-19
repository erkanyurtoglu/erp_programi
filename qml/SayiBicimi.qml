pragma Singleton
import QtQuick

// Tum sayisal giris kutularinin ortak Turkce sayi bicimi: binlik ayraci nokta,
// ondalik ayraci virgul ("15.200.000,50"). Hem kullanici YAZARKEN canli
// bicimlendirmede (bkz. components/SayiBicimlendirici.qml) hem de kaydedilmis
// degerleri kutuya basarken burasi kullanilir -- boylece ekranda gorunen bicim
// ile ozet/toplam satirlarindaki paraFormat cikti tek elden gelir.
QtObject {
    id: sayiBicimi

    readonly property string binlikAyraci: "."
    readonly property string ondalikAyraci: ","

    // Bir karakterin "anlamli" (kullanicinin kendi yazdigi) olup olmadigi:
    // rakamlar ve ondalik virgulu. Binlik ayraclari biz ekledigimiz icin imlec
    // hesabinda sayilmaz.
    function anlamliMi(karakter) {
        return (karakter >= "0" && karakter <= "9") || karakter === ondalikAyraci
    }

    // metin icinde konum'dan onceki anlamli karakter sayisi.
    function anlamliSay(metin, konum) {
        var adet = 0
        for (var i = 0; i < konum && i < metin.length; ++i)
            if (anlamliMi(metin.charAt(i)))
                adet++
        return adet
    }

    // anlamliSay'in tersi: bastan "adet" tane anlamli karakter gecildiginde
    // imlecin gelmesi gereken indeks.
    function anlamliKonum(metin, adet) {
        var sayac = 0
        for (var i = 0; i < metin.length; ++i) {
            if (sayac === adet)
                return i
            if (anlamliMi(metin.charAt(i)))
                sayac++
        }
        return metin.length
    }

    // Kullanicinin yazdigi ham metinden yalnizca rakamlari ve (izin veriliyorsa)
    // TEK bir ondalik virgulu birakir; ondalik basamak sayisini kirpar.
    // Binlik ayraclari (nokta) atilir -- onlari grupla() yeniden uretir.
    function temizle(metin, ondalik) {
        if (ondalik === undefined)
            ondalik = 2
        var sonuc = ""
        var virgulGecildi = false
        var basamak = 0
        for (var i = 0; i < metin.length; ++i) {
            var c = metin.charAt(i)
            if (c >= "0" && c <= "9") {
                if (virgulGecildi) {
                    if (basamak >= ondalik)
                        continue
                    basamak++
                }
                sonuc += c
            } else if (c === ondalikAyraci && ondalik > 0 && !virgulGecildi) {
                virgulGecildi = true
                sonuc += ondalikAyraci
            }
        }
        return sonuc
    }

    // "15200000,5" -> "15.200.000,5"
    function grupla(temizMetin) {
        if (temizMetin.length === 0)
            return ""
        var virgulIndeks = temizMetin.indexOf(ondalikAyraci)
        var tamKisim = virgulIndeks >= 0 ? temizMetin.substring(0, virgulIndeks) : temizMetin
        var kesirKisim = virgulIndeks >= 0 ? temizMetin.substring(virgulIndeks) : ""
        // Bastaki gereksiz sifirlar ("007" -> "7"); tek basina "0" korunur.
        tamKisim = tamKisim.replace(/^0+(?=\d)/, "")
        var gruplu = ""
        for (var i = 0; i < tamKisim.length; ++i) {
            if (i > 0 && (tamKisim.length - i) % 3 === 0)
                gruplu += binlikAyraci
            gruplu += tamKisim.charAt(i)
        }
        return gruplu + kesirKisim
    }

    // Ekrandaki bicimli metinden hesaplanabilir sayiya: "15.200.000,50" -> 15200000.5
    // Bos/gecersiz metin 0 doner (eski parseFloat(...) || 0 davranisi).
    function ayikla(metin) {
        if (metin === undefined || metin === null)
            return 0
        var temizMetin = temizle(String(metin), 9).split(ondalikAyraci).join(".")
        var deger = parseFloat(temizMetin)
        return isNaN(deger) ? 0 : deger
    }

    // Sayidan ekran metnine: 15200000.5 -> "15.200.000,50"
    function bicimle(sayi, ondalik) {
        if (ondalik === undefined)
            ondalik = 2
        var deger = Number(sayi)
        if (isNaN(deger))
            deger = 0
        return deger.toLocaleString(Qt.locale("tr_TR"), "f", ondalik)
    }
}
