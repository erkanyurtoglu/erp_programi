import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Sayfali listelerin (Musterilerim / Urunlerim / Personellerim) ortak BOS
// DURUM gostergesi. ListView'in uzerine serilir ve yalnizca gosterecek bir sey
// oldugunda gorunur:
//
//   * yukleniyor  -> "Yükleniyor…" (sorgu artik arka plan thread'inde
//                    calistigi icin liste bu sure boyunca bos gorunur;
//                    kullanici neyi bekledigini bilmeli)
//   * hata        -> sorgu calistirilamadi (baglanti yok)
//   * kayit yok   -> arama sonuc vermedi ya da liste gercekten bos
//
// Eskiden bu durumlarin UCU de kullaniciya bombos beyaz bir alan olarak
// gorunuyordu; "program dondu mu, kayit mi yok, baglanti mi gitti?" ayirt
// edilemiyordu.
Item {
    id: kok

    // Liste su an yukleniyor mu?
    property bool yukleniyor: false
    // Dolu ise hata mesaji olarak gosterilir (yukleniyor'dan onceliklidir).
    property string hata: ""
    // Listede kac kayit var? 0 ise "bulunamadi" metni gosterilir.
    property int kayitSayisi: 0
    // Arama kutusu dolu mu? Bos listenin metni buna gore degisir.
    property bool aramaVar: false
    // "Kayıt yok" durumunda gosterilecek metin (sayfaya ozel).
    property string bosMetin: "Henüz kayıt yok."
    property string aramaBosMetni: "Aramanıza uygun kayıt bulunamadı."

    // Yalnizca gosterilecek satir YOKKEN (ya da hata varken) gorunur. Sayfa
    // degistirirken listede hala eski satirlar duruyorsa onlarin uzerine
    // "Yükleniyor…" yazmiyoruz -- bu sirada ileri/geri butonlari zaten devre
    // disi kaldigi icin islemin surdugu belli olur.
    visible: kok.hata.length > 0 || kok.kayitSayisi === 0

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        spacing: 8

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutNormal
            color: kok.hata.length > 0 ? Theme.tehlikeAcik : Theme.metinSoluk
            text: kok.hata.length > 0 ? kok.hata
                : kok.yukleniyor ? "Yükleniyor…"
                : kok.aramaVar ? kok.aramaBosMetni
                : kok.bosMetin
        }

        // Hata durumunda ne yapilacagini da soyle: kullanici "yenile" icin
        // nereye bakacagini bilsin.
        Label {
            visible: kok.hata.length > 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            color: Theme.metinCokSoluk
            text: "Bağlantı düzeldiğinde aramayı tekrarlayın veya sayfayı değiştirin."
        }
    }
}
