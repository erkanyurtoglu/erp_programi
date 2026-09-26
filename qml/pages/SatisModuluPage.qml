import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Satis / Teklif modulunun kabuk (shell) ekrani: solda WPF'teki gibi sabit bir
// yan menu (Teklif Ver / Giden Tekliflerim / Alınan Tekliflerim / Biten
// Tekliflerim), sagda secili sekmenin icerigi. Kullanicinin anlattigi is akisi
// tam olarak bu dort sekmeye karsilik gelir:
//   Teklif Ver -> kaydedince "Beklemede" durumuyla Giden Tekliflerim'e duser.
//   Giden Tekliflerim -> TUM teklifler (durumdan bagimsiz, bir gecmis/log gibi);
//                        buradan Kabul Et / Reddet yapilabilir.
//   Alınan Tekliflerim -> sadece "Kabul Edildi" durumundakiler; siparis
//                         hazirlanip gonderilince "Tamamlandı" olarak isaretlenir.
//   Biten Tekliflerim -> sadece "Tamamlandı" durumundakiler (arsiv).
//
// Bu sekmeler arasindaki gecis TEK YONLU DEGILDIR: musteri kabul ettikten sonra
// vazgecebilir, kararsiz kalip bekletebilir, tamamlanmis bir teklif yanlislikla
// tamamlanmis olabilir. Her uc listede de satirin DURUM rozetine tiklanarak teklif
// herhangi bir duruma alinabilir (bkz. GecmisTekliflerPage.qml) -- yani bir teklif
// Alınan Tekliflerim'den Giden Tekliflerim'e geri donebilir. Her degisim, kimin ne
// zaman yaptigiyla birlikte "Durum Geçmişi"ne loglanir.
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0   // varsayilan: Teklif Ver

    signal anaMenuyeDon()

    readonly property int kullaniciId: root.oturum ? (root.oturum.kullaniciId || 0) : 0

    // ---- "Detay" (revizyon) alt sayfasi ----
    // Revizyon ekrani sol menude KENDI maddesi olmayan, sadece listedeki "Detay"
    // butonuyla acilan bir ALT SAYFA'dir (StackLayout'un son indeksi). Acikken sol
    // menude gelinen liste sekmesi secili KALIR ve ust soldaki geri butonu tam
    // kalinan yere dondurur -- boylece "Teklif Ver sekmesini gasp etme" hissi olmaz
    // ve Teklif Ver'de hazirlanan yarim taslak hic etkilenmez (ayri bir ornek).
    readonly property int revizyonSekmesi: 7
    property int revizyonKaynakSekme: 1

    function revizyonKaynakSayfasi() {
        if (root.revizyonKaynakSekme === 2) return alinanTekliflerPage
        if (root.revizyonKaynakSekme === 3) return bitenTekliflerPage
        return gidenTekliflerPage
    }

    function revizyonuAc(kaynakSekme, teklifId) {
        root.revizyonKaynakSekme = kaynakSekme
        icerikYiginlar.currentIndex = root.revizyonSekmesi
        revizyonPage.duzenlemeyeBasla(teklifId)
    }

    // "Kopya" butonu: AYNI alt sayfayi kullanir, ama teklifin icerigi BAGIMSIZ bir
    // yeni teklif olarak acilir (kaynak teklife dokunulmaz, revizyon olusmaz --
    // bkz. TeklifVerPage.kopyalamayaBasla). Ayni ekranda oldugumuz icin geri butonu
    // ve sol menudeki secili sekme aynen calisir.
    //
    // Kopya YALNIZCA Giden Tekliflerim'den acilir (bkz. GecmisTekliflerPage.
    // kopyaButonuGoster); Alınan/Biten Tekliflerim'de buton yok, cunku o
    // asamadaki bir teklifi yeni teklif hazirlamak icin kullanmak anlamsiz.
    // Bu yuzden geri donus sekmesi hep Giden Tekliflerim'dir.
    function kopyayiAc(teklifId) {
        root.revizyonKaynakSekme = 1
        icerikYiginlar.currentIndex = root.revizyonSekmesi
        revizyonPage.kopyalamayaBasla(teklifId)
    }

    // listeyiYenile: Detay ekraninda teklif uzerinde yerinde degisiklik yapilmis
    // olabilir (planlanan teslim tarihi, teklif/uretim notu, sozlesme metni); listeye
    // donulurken kaldigi sayfa yeniden yuklenir ki guncel degerler hemen gorunsun.
    // Revizyon kaydinda cagiran taraf zaten 1. sayfayi yukledigi icin false gecer.
    function revizyondanDon(listeyiYenile) {
        icerikYiginlar.currentIndex = root.revizyonKaynakSekme
        if (listeyiYenile === false)
            return
        const sayfa = root.revizyonKaynakSayfasi()
        sayfa.sayfayiYukle(sayfa.sayfaSonucu.mevcutSayfa)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Sol yan menu ----
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.arkaplanIkincil
            border.width: 0

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.kenarlik
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4

                Label {
                    text: "SATIŞ / TEKLİF"
                    color: Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.bold: true
                    Layout.bottomMargin: 8
                }

                component YanMenuButonu: Rectangle {
                    id: buton
                    property string metin: ""
                    property bool secili: false
                    signal tiklandi()

                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: Theme.radiusKucuk
                    color: secili ? Theme.panelVurgu : (alan.containsMouse ? Theme.panelHover : "transparent")
                    border.width: secili ? 1 : 0
                    border.color: Theme.kenarlikVurgu

                    Rectangle {
                        visible: buton.secili
                        width: 3
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        radius: 2
                        color: Theme.vurgu
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: buton.secili ? 20 : 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: buton.metin
                        color: buton.secili ? Theme.metinBirincil : Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        font.bold: buton.secili
                    }

                    MouseArea {
                        id: alan
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: buton.tiklandi()
                    }
                }

                YanMenuButonu {
                    metin: "◀ Ana Menü"
                    Layout.bottomMargin: 8
                    onTiklandi: root.anaMenuyeDon()
                }

                YanMenuButonu {
                    metin: "Teklif Ver"
                    secili: icerikYiginlar.currentIndex === 0
                    onTiklandi: icerikYiginlar.currentIndex = 0
                }
                // NOT: "Detay" ile acilan revizyon alt sayfasindayken de, gelinen
                // liste sekmesi secili gorunmeye devam eder -- kullanici hangi
                // baglamda oldugunu kaybetmesin diye.
                YanMenuButonu {
                    metin: "Giden Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 1
                            || (icerikYiginlar.currentIndex === root.revizyonSekmesi && root.revizyonKaynakSekme === 1)
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 1
                        gidenTekliflerPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Alınan Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 2
                            || (icerikYiginlar.currentIndex === root.revizyonSekmesi && root.revizyonKaynakSekme === 2)
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 2
                        alinanTekliflerPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Biten Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 3
                            || (icerikYiginlar.currentIndex === root.revizyonSekmesi && root.revizyonKaynakSekme === 3)
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 3
                        bitenTekliflerPage.sayfayiYukle(1)
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 8; height: 1; color: Theme.kenarlik }

                YanMenuButonu {
                    metin: "Müşterilerim"
                    secili: icerikYiginlar.currentIndex === 4
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 4
                        musterilerimPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Ürünlerim"
                    secili: icerikYiginlar.currentIndex === 5
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 5
                        urunlerimPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Personellerim"
                    secili: icerikYiginlar.currentIndex === 6
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 6
                        personellerimPage.sayfayiYukle(1)
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ---- Sag icerik ----
        StackLayout {
            id: icerikYiginlar
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.baslangicSekmesi

            TeklifVerPage {
                kullaniciId: root.kullaniciId
            }

            // otomatikYukle: false -- StackLayout, gorunur olmayan sekmeleri de
            // ANINDA olusturur; her biri kendi Component.onCompleted'inda
            // senkron bir SQL sorgusu atsaydi (eskiden oldugu gibi), modul
            // acilir acilmaz 6 sorgu ust uste UI thread'ini bloke ederdi.
            // Bunun yerine yukleme, kullanici sekmeye GERCEKTEN tikladiginda
            // (asagidaki sayfayiYukle cagrilariyla) yapilir.
            //
            // detayIstendi: her uc sekmedeki "Detay" butonu ayni akisi kullanir --
            // revizyon ALT SAYFASINI acar (bkz. root.revizyonuAc). Teklif Ver
            // sekmesine dokunulmaz. Giden Tekliflerim'den acildiginda kaydedilince
            // orijinal teklife dokunulmadan yeni bir revizyon eklenir ve otomatik
            // olarak bu listeye donulur. Alınan/Biten Tekliflerim'den acildiginda
            // kabul edilmis/tamamlanmis teklif kilitlidir -- detay salt goruntulemedir.
            GecmisTekliflerPage {
                id: gidenTekliflerPage
                durumFiltresi: ""
                baslikMetni: "Giden Tekliflerim"
                otomatikYukle: false
                kullaniciId: root.kullaniciId
                onDetayIstendi: (teklifId) => root.revizyonuAc(1, teklifId)
                // Kopya butonu yalnizca bu sekmede var (bkz. kopyayiAc).
                onKopyaIstendi: (teklifId) => root.kopyayiAc(teklifId)
            }

            GecmisTekliflerPage {
                id: alinanTekliflerPage
                durumFiltresi: "Kabul Edildi"
                baslikMetni: "Alınan Tekliflerim"
                otomatikYukle: false
                kullaniciId: root.kullaniciId
                onDetayIstendi: (teklifId) => root.revizyonuAc(2, teklifId)
            }

            GecmisTekliflerPage {
                id: bitenTekliflerPage
                durumFiltresi: "Tamamlandı"
                baslikMetni: "Biten Tekliflerim"
                otomatikYukle: false
                kullaniciId: root.kullaniciId
                onDetayIstendi: (teklifId) => root.revizyonuAc(3, teklifId)
            }

            MusterilerimPage {
                id: musterilerimPage
                otomatikYukle: false
            }

            UrunlerimPage {
                id: urunlerimPage
                otomatikYukle: false
            }

            PersonellerimPage {
                id: personellerimPage
                otomatikYukle: false
            }

            // ---- Index 7: "Detay" (revizyon) alt sayfasi ----
            // Teklif Ver ile AYNI bilesen (yani birebir ayni ekran), ama AYRI bir
            // ornek: Teklif Ver sekmesinde yarim kalmis bir teklif varsa bu akistan
            // hic etkilenmez. Sol menude kendi maddesi yok; sadece listelerdeki
            // "Detay" butonuyla acilir, geri butonuyla gelinen listeye donulur.
            TeklifVerPage {
                id: revizyonPage
                kullaniciId: root.kullaniciId
                geriDonusEtiketi: root.revizyonKaynakSekme === 2 ? "Alınan Tekliflerim"
                                : root.revizyonKaynakSekme === 3 ? "Biten Tekliflerim"
                                : "Giden Tekliflerim"

                // Kabul edilmis / tamamlanmis teklifin kendisi hic degismez. Giden
                // Tekliflerim'den (1) acilan KABUL EDILMIS teklif yine de revize
                // edilebilir (yeni revizyon olusur); tamamlanmis teklif hicbir yerden
                // revize edilemez. Alınan (2) / Biten (3) listelerinden acilan
                // detay salt goruntulemedir (bkz. TeklifVerPage.revizyonAcik).
                revizyonIzinli: root.revizyonKaynakSekme === 1

                onGeriDonuldu: root.revizyondanDon()

                onRevizyonKaydedildi: (yeniTeklifId, kaynakTeklifId, revizeEdilenIdler) => {
                    root.revizyondanDon(false)
                    // Yeni revizyon en yeni kayit oldugu icin listenin ILK sayfasinda
                    // gorunur; kullanici sonucu ("R1" rozetli yeni satir) hemen gorsun
                    // diye kaldigi sayfa yerine 1. sayfaya donuyoruz.
                    const sayfa = root.revizyonKaynakSayfasi()
                    sayfa.sayfayiYukle(1)
                    // Yeni revizyon "Beklemede" durumunda olusur; Alınan/Biten
                    // listelerinde gorunmedigi icin nerede oldugu belirtilir.
                    sayfa.durumMesajiGoster("Revizyon kaydedildi: Teklif " + database.teklifNoGetir(yeniTeklifId)
                                            + (root.revizyonKaynakSekme === 1 ? "" : " (Giden Tekliflerim)"))
                }

                // Duzeltme ayni teklifi yerinde gunceller: yeni satir olusmaz,
                // teklif listede kaldigi yerdedir -- o sayfa tazelenir.
                onDuzeltmeKaydedildi: (teklifId) => {
                    root.revizyondanDon()
                    root.revizyonKaynakSayfasi().durumMesajiGoster("Teklif " + database.teklifNoGetir(teklifId) + " düzeltildi.")
                }

                onKopyaKaydedildi: (yeniTeklifId, kaynakTeklifId) => {
                    root.revizyondanDon(false)
                    // Kopya da "Beklemede" durumunda, en yeni kayit olarak olusur --
                    // listenin ilk sayfasinda gorunur.
                    const sayfa = root.revizyonKaynakSayfasi()
                    sayfa.sayfayiYukle(1)
                    sayfa.durumMesajiGoster("Kopya kaydedildi: Teklif " + database.teklifNoGetir(yeniTeklifId))
                }
            }
        }
    }
}
