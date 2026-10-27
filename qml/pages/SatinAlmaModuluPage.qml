import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Satinalma modulunun kabuk (shell) ekrani: solda sabit yan menu, sagda secili
// sekmenin icerigi (SatisModuluPage ile ayni yapi). Menu maddeleri is akisinin
// asamalaridir; kullanici bir kaydin nerede oldugunu menuden bilir:
//
//   Talep Oluştur        -> kaydedilince Talepler'e duser.
//   Talepler             -> siparise donusmemis kalemi olan ya da siparisleri
//                           henuz gelmemis talepler. Kalemin siparisi talepten
//                           cikmadan acilir (bkz. SiparisPencereleri).
//   Siparişler           -> talepten bagimsiz arama ve toplu takip (gelen koli,
//                           gecikenler, patron onayi, fatura bekleyenler).
//   Cihaz Maliyetleri    -> recete kalemlerinin fiyatlari (kar orani / satis
//                           fiyati yalnizca Yonetim'i gorene acik).
//
// Talep ekrani (TalepDuzenlePage) menude kendi maddesi olmayan bir ALT
// SAYFADIR: yeni talepte "Talep Oluştur", mevcut talepte "Talepler" secili
// kalir.
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0
    signal anaMenuyeDon()

    // Rol yetkileri (bkz. Database::girisYap -> "moduller"). Duzenleme yetkisi
    // yoksa ekrandaki degistirme butonlari gizlenir; asil denetim sunucu
    // tarafindadir (Database::modulDuzenleyebilirMi).
    function modulYetkisi(kod) {
        const liste = root.oturum && root.oturum.moduller ? root.oturum.moduller : []
        return liste.find(m => m.modulKodu === kod) || null
    }
    readonly property bool satinalmaDuzenleyebilir: {
        const m = root.modulYetkisi("SATINALMA")
        return m !== null && m.duzenleyebilir === true
    }

    // Yan menu rozetleri.
    property var ozet: ({})
    function ozetiYenile() {
        root.ozet = database.satinalmaOzetiGetir()
    }

    // Sayfa indeksleri (StackLayout sirasi).
    readonly property int sayfaTalepler: 0
    readonly property int sayfaTalep: 1
    readonly property int sayfaSiparisler: 2
    readonly property int sayfaTedarikciler: 3
    readonly property int sayfaCihazlar: 4

    readonly property bool yeniTalepAcik: icerik.currentIndex === root.sayfaTalep && talepPage.talepId === 0

    function talepleraGit() {
        icerik.currentIndex = root.sayfaTalepler
        taleplerPage.yukle()
        root.ozetiYenile()
    }
    function talepAc(talepId) {
        talepPage.ac(talepId)
        icerik.currentIndex = root.sayfaTalep
    }
    function yeniTalep() {
        talepPage.yeniTalep()
        icerik.currentIndex = root.sayfaTalep
    }
    function siparisleraGit() {
        icerik.currentIndex = root.sayfaSiparisler
        siparislerPage.yukle()
        root.ozetiYenile()
    }
    // Talep ekraninda kaydedilmemis degisiklik varken menuden ayrilmak
    // calismayi kaybettirmesin.
    function menudenGit(islem) {
        if (icerik.currentIndex === root.sayfaTalep && talepPage.degisti && talepPage.duzenlenebilir) {
            cikisOnayi.iste("Kaydedilmemiş Değişiklikler",
                            "Açık talepte kaydedilmemiş değişiklikler var. Kaydetmeden çıkılsın mı?",
                            "Kaydetmeden Çık", true,
                            function() { talepPage.degisti = false; islem() })
            return
        }
        if (icerik.currentIndex === root.sayfaCihazlar && cihazlarPage.degisti) {
            cihazlarPage.gecisYap(function() { cihazlarPage.formuKapat(); islem() })
            return
        }
        islem()
    }

    Component.onCompleted: {
        root.ozetiYenile()
        taleplerPage.yukle()
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
            Layout.preferredWidth: 228
            Layout.fillHeight: true
            color: Theme.arkaplanIkincil

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
                    text: "SATINALMA"
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
                    property int rozet: 0
                    property color rozetRengi: Theme.vurgu
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

                    Rectangle {
                        visible: buton.rozet > 0
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(22, rozetYazi.implicitWidth + 12)
                        height: 20
                        radius: 10
                        color: Qt.rgba(buton.rozetRengi.r, buton.rozetRengi.g, buton.rozetRengi.b, 0.18)
                        Text {
                            id: rozetYazi
                            anchors.centerIn: parent
                            text: buton.rozet
                            color: buton.rozetRengi
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                            font.bold: true
                        }
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
                    onTiklandi: root.menudenGit(function() { root.anaMenuyeDon() })
                }

                YanMenuButonu {
                    metin: "Talep Oluştur"
                    visible: root.satinalmaDuzenleyebilir
                    secili: root.yeniTalepAcik
                    onTiklandi: root.menudenGit(root.yeniTalep)
                }

                YanMenuButonu {
                    metin: "Talepler"
                    secili: icerik.currentIndex === root.sayfaTalepler
                            || (icerik.currentIndex === root.sayfaTalep && !root.yeniTalepAcik)
                    rozet: root.ozet.acikTalep || 0
                    onTiklandi: root.menudenGit(root.talepleraGit)
                }

                YanMenuButonu {
                    metin: "Siparişler"
                    secili: icerik.currentIndex === root.sayfaSiparisler
                    // Bekleyen siparis sayisi; gecikme varsa kirmizi rozetle
                    // gecikenlerin sayisi.
                    rozet: (root.ozet.geciken || 0) > 0 ? root.ozet.geciken : (root.ozet.acikSiparis || 0)
                    rozetRengi: (root.ozet.geciken || 0) > 0 ? Theme.tehlikeAcik : Theme.vurgu
                    onTiklandi: root.menudenGit(root.siparisleraGit)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: Theme.kenarlik
                }

                YanMenuButonu {
                    metin: "Tedarikçilerim"
                    secili: icerik.currentIndex === root.sayfaTedarikciler
                    onTiklandi: root.menudenGit(function() {
                        icerik.currentIndex = root.sayfaTedarikciler
                        tedarikcilerimPage.sayfayiYukle(1)
                    })
                }

                YanMenuButonu {
                    metin: "Cihaz Maliyetleri"
                    secili: icerik.currentIndex === root.sayfaCihazlar
                    onTiklandi: root.menudenGit(function() {
                        icerik.currentIndex = root.sayfaCihazlar
                        cihazlarPage.sayfayiYukle()
                    })
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ---- Sag icerik ----
        StackLayout {
            id: icerik
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.sayfaTalepler

            SatinalmaTaleplerPage {
                id: taleplerPage
                duzenleyebilir: root.satinalmaDuzenleyebilir
                onTalepAc: (talepId) => root.talepAc(talepId)
                onYeniTalep: root.yeniTalep()
            }

            TalepDuzenlePage {
                id: talepPage
                duzenleyebilir: root.satinalmaDuzenleyebilir
                onGeri: root.talepleraGit()
                onKaydedildi: root.ozetiYenile()
            }

            SatinalmaSiparislerPage {
                id: siparislerPage
                duzenleyebilir: root.satinalmaDuzenleyebilir
                ozet: root.ozet
                onTalepAc: (talepId) => root.menudenGit(function() { root.talepAc(talepId) })
                onDegisiklikOldu: root.ozetiYenile()
            }

            TedarikcilerimPage {
                id: tedarikcilerimPage
                otomatikYukle: false
                duzenleyebilir: root.satinalmaDuzenleyebilir
            }

            CihazMaliyetleriPage {
                id: cihazlarPage
                otomatikYukle: false
            }
        }
    }

    OnayDialog { id: cikisOnayi }
}
