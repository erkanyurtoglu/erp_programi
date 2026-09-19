import QtQuick
// Templates (stil bagimsiz temel tipler): hedef kutu QtQuick.Controls.Basic,
// Windows, Fusion... hangi stille yazilmis olursa olsun hepsi T.TextField'dan
// turer. Burada QtQuick.Controls.TextField kullanilirsa uygulamanin AKTIF
// stiline gore cozulur ve "parent as TextField" farkli stildeki bir kutuda
// null doner -- bicimlendirici sessizce calismaz.
import QtQuick.Templates as T
import erp_programi

// Bir TextField'i "canli" Turkce sayi girisine cevirir: kullanici yazarken
// binlik ayraclari (15200000 -> 15.200.000) aninda eklenir, ondalik ayraci
// virguldur ve odak kutudan cikinca deger tam basamakla tamamlanir
// (15.200.000 -> 15.200.000,00).
//
// Kullanimi -- bicimlenecek TextField'in ICINE konur, ayrica bir sey
// baglamak gerekmez:
//
//     TextField {
//         id: fiyatAlani
//         SayiBicimlendirici { }              // hedef varsayilan olarak parent
//     }
//     ...  SayiBicimi.ayikla(fiyatAlani.text) // metni sayiya cevirmek icin
//
// NOT: Kutudaki metin artik "15.200.000,50" gibi oldugu icin parseFloat() ile
// okunamaz; deger her zaman SayiBicimi.ayikla() (veya buradaki "deger"
// property'si) uzerinden alinmalidir.
Item {
    id: bicimlendirici

    // Bicimlenecek TextField. Varsayilan: bu nesnenin icine konuldugu kutu.
    property T.TextField hedef: parent as T.TextField
    // Izin verilen ondalik basamak sayisi (0 = tam sayi girisi).
    property int ondalik: 2
    // Odak kutudan ciktiginda deger tam basamakla tamamlansin mi
    // ("1.500" -> "1.500,00"). Bos kutu bos birakilir.
    property bool odakBitinceTamamla: true

    // Kutudaki metnin sayisal karsiligi.
    readonly property real deger: hedef ? SayiBicimi.ayikla(hedef.text) : 0

    visible: false
    width: 0
    height: 0

    // Kutuyu bicimli metin kabul edecek sekilde ayarlar; DoubleValidator
    // gruplu metni ("15.200.000,50") reddettigi icin onun yerine gecer.
    readonly property var dogrulayici: RegularExpressionValidator {
        regularExpression: /[0-9.,]*/
    }

    // Bir sayiyi kutuya bicimli olarak yazar (kutuya elle "text = ..." demek
    // yerine bu kullanilmali -- ic durum da birlikte guncellenir).
    function ayarla(sayi) {
        if (!hedef)
            return
        _calisiyor = true
        hedef.text = SayiBicimi.bicimle(sayi, ondalik)
        hedef.cursorPosition = 0
        _calisiyor = false
        _oncekiHam = hedef.text
        _oncekiTemiz = SayiBicimi.temizle(hedef.text, ondalik)
    }

    // Kutuyu bosaltir.
    function temizle() {
        if (!hedef)
            return
        _calisiyor = true
        hedef.text = ""
        _calisiyor = false
        _oncekiHam = ""
        _oncekiTemiz = ""
    }

    // --- ic durum ---
    property bool _calisiyor: false
    property string _oncekiHam: ""
    property string _oncekiTemiz: ""

    // Her tus basisindan sonra metni yeniden bicimlendirir ve imleci
    // kullanicinin yazdigi karaktere gore dogru yere tasir.
    function _bicimlendir() {
        if (_calisiyor || !hedef)
            return

        var ham = hedef.text
        var imlec = hedef.cursorPosition

        // Numaratordeki nokta tusu: Turkce bicimde nokta binlik ayracidir, ama
        // kullanici ondalik girmek istemistir. Rakamlar degismeden sadece bir
        // nokta eklendiyse onu virgule cevir.
        if (ondalik > 0 && imlec > 0 && ham.charAt(imlec - 1) === SayiBicimi.binlikAyraci
                && ham.length === _oncekiHam.length + 1
                && SayiBicimi.temizle(ham, ondalik) === _oncekiTemiz) {
            ham = ham.substring(0, imlec - 1) + SayiBicimi.ondalikAyraci + ham.substring(imlec)
        }

        var temizMetin = SayiBicimi.temizle(ham, ondalik)
        var anlamli = SayiBicimi.anlamliSay(ham, imlec)

        // Backspace binlik ayracinin uzerine denk geldiyse (rakamlar degismeden
        // metin bir karakter kisaldiysa) kullanicinin silmek istedigi ONCEKI
        // rakami sil -- yoksa ayrac aninda geri geldigi icin tus islemez gorunur.
        if (temizMetin === _oncekiTemiz && ham.length === _oncekiHam.length - 1 && anlamli > 0) {
            temizMetin = temizMetin.substring(0, anlamli - 1) + temizMetin.substring(anlamli)
            anlamli -= 1
        }

        var yeni = SayiBicimi.grupla(temizMetin)

        _calisiyor = true
        if (hedef.text !== yeni)
            hedef.text = yeni
        hedef.cursorPosition = hedef.activeFocus ? SayiBicimi.anlamliKonum(yeni, anlamli) : 0
        _calisiyor = false

        _oncekiHam = yeni
        _oncekiTemiz = temizMetin
    }

    Component.onCompleted: {
        if (!hedef) {
            // Sessizce calismamak yerine sebebini soyle: bicimlendirici bir
            // TextField'in icine konmamis (veya "hedef" yanlis verilmis).
            console.warn("SayiBicimlendirici: hedef TextField bulunamadi --"
                         + " bileseni bicimlenecek TextField'in icine koyun.")
            return
        }
        hedef.validator = dogrulayici
        _bicimlendir()
    }

    Connections {
        target: bicimlendirici.hedef
        function onTextChanged() { bicimlendirici._bicimlendir() }
        function onActiveFocusChanged() {
            if (bicimlendirici.hedef.activeFocus)
                return
            // Odak cikinca: dolu kutuyu tam basamakla tamamla, metnin basina don
            // (dar kutularda sigmayan degerin sonu degil basi gorunsun).
            if (bicimlendirici.odakBitinceTamamla && bicimlendirici.hedef.text.length > 0)
                bicimlendirici.ayarla(bicimlendirici.deger)
            bicimlendirici.hedef.cursorPosition = 0
        }
    }
}
