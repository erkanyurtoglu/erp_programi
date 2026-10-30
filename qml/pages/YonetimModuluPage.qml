import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim modulunun kabuk (shell) ekrani: solda sabit yan menu, sagda secili
// sekmenin icerigi (SatisModuluPage / SatinAlmaModuluPage ile ayni yapi).
//
// Sekmeler (StackLayout sirasiyla):
//    0 Ozet               -- donemin teklif sayilari, personel, satinalma  (HAZIR)
//    1 Personellerim      -- personel ekle / duzenle / rol ata / pasife al   (HAZIR)
//    2 Roller ve Yetkiler -- rol ekle / sil, modul bazinda yetki             (HAZIR)
//    3 Sistem Ayarlari    -- dbo.ayarlar (KDV, patron onay esigi, sozlesme)  (HAZIR)
//    4 Islem Gecmisi      -- tum tekliflerin olusturma / durum / duzeltme izi (HAZIR)
//    5 Cihaz Maliyetleri  -- recete, kar orani, satis fiyati (Satinalma'da da var) (HAZIR)
//
// Personellerim eskiden Satis modulunun yan menusundeydi, ama gorunurlugu
// zaten YONETIM modulunun duzenleme yetkisine bagliydi: Satis yetkisi olmayan
// bir yoneticinin personel listesine ulasmak icin Satis moduline girmesi
// gerekiyordu. Yeri burasi.
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0
    signal anaMenuyeDon()

    readonly property int kullaniciId: root.oturum ? (root.oturum.kullaniciId || 0) : 0

    // Rol yetkileri (bkz. Database::girisYap -> "moduller"). Asil denetim
    // sunucu tarafindadir (Database::modulDuzenleyebilirMi).
    function modulYetkisi(kod) {
        const liste = root.oturum && root.oturum.moduller ? root.oturum.moduller : []
        return liste.find(m => m.modulKodu === kod) || null
    }
    readonly property bool yonetimDuzenleyebilir: {
        const m = root.modulYetkisi("YONETIM")
        return m !== null && m.duzenleyebilir === true
    }

    // Acik sekmede kaydedilmemis degisiklik (rol, ayarlar, cihaz karti) varsa
    // once onay ister. Sekmeye donuste sayfa yeniden yuklendigi ve Ana Menu
    // sayfayi kapattigi icin aksi halde degisiklik sessizce kaybolurdu.
    function sekmedenAyril(islem) {
        const sira = icerikYiginlar.currentIndex
        if (sira === 2 && root.rollerYetkilerPage && root.rollerYetkilerPage.degisti) {
            root.rollerYetkilerPage.gecisYap(islem)
            return
        }
        if (sira === 3 && root.sistemAyarlariPage && root.sistemAyarlariPage.degisti) {
            cikisOnayi.iste("Kaydedilmemiş Değişiklikler",
                            "Sistem ayarlarındaki değişiklikler kaydedilmedi. Vazgeçilsin mi?",
                            "Vazgeç", true, islem)
            return
        }
        if (sira === 5 && root.cihazMaliyetleriPage && root.cihazMaliyetleriPage.degisti) {
            root.cihazMaliyetleriPage.gecisYap(function() { root.cihazMaliyetleriPage.formuKapat(); islem() })
            return
        }
        islem()
    }

    function sekmeyiAc(sira) {
        root.sekmedenAyril(function() { root.sekmeyiYukle(sira) })
    }

    // Sekmeye gecer ve icerigini (yeniden) yukler. Sayfalar kendiliginden
    // yuklenmez (otomatikYukle: false): modul acilirken yalnizca gorunen
    // sekme sorgu atsin.
    function sekmeyiYukle(sira) {
        icerikYiginlar.currentIndex = sira
        if (sira === 0)
            root.yonetimOzetPage.sayfayiYukle()
        else if (sira === 1)
            root.personellerimPage.sayfayiYukle(1)
        else if (sira === 2)
            root.rollerYetkilerPage.sayfayiYukle()
        else if (sira === 3)
            root.sistemAyarlariPage.sayfayiYukle()
        else if (sira === 4)
            root.islemGecmisiPage.sayfayiYukle(1)
        else if (sira === 5)
            root.cihazMaliyetleriPage.sayfayiYukle()
    }

    // StackLayout'taki bir sekmeyi ilk secildiginde olusturur ve sonra hep tutar
    // (bkz. SatisModuluPage.SekmeYukleyici). Eskiden alti sayfanin hepsi modul
    // acilirken olusturuluyor, karta basinca ekran bir sure donuyordu.
    component SekmeYukleyici: Loader {
        property int sekme: -1
        property bool yuklendi: false
        active: yuklendi || icerikYiginlar.currentIndex === sekme
        onLoaded: yuklendi = true
    }

    // Sekme sayfalari; sekme henuz acilmadiysa null.
    readonly property var yonetimOzetPage: ozetYukleyici.item
    readonly property var personellerimPage: personellerimYukleyici.item
    readonly property var rollerYetkilerPage: rollerYukleyici.item
    readonly property var sistemAyarlariPage: ayarlarYukleyici.item
    readonly property var islemGecmisiPage: gecmisYukleyici.item
    readonly property var cihazMaliyetleriPage: cihazlarYukleyici.item

    // Ilk sekmenin sorgusu modul ekrana cizildikten sonra atilir; karta basinca
    // ekran sorgu bitene kadar ana menude takili kalmasin.
    Component.onCompleted: ilkYukleme.start()
    Timer {
        id: ilkYukleme
        interval: 50
        onTriggered: root.sekmeyiAc(icerikYiginlar.currentIndex)
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

                Image {
                    source: "qrc:/qt/qml/erp_programi/logo.png"
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    Layout.preferredHeight: 48
                    Layout.bottomMargin: 12
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: "YÖNETİM"
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
                    onTiklandi: root.sekmedenAyril(function() { root.anaMenuyeDon() })
                }

                YanMenuButonu {
                    metin: "Özet"
                    secili: icerikYiginlar.currentIndex === 0
                    onTiklandi: root.sekmeyiAc(0)
                }

                YanMenuButonu {
                    metin: "Personellerim"
                    secili: icerikYiginlar.currentIndex === 1
                    onTiklandi: root.sekmeyiAc(1)
                }

                YanMenuButonu {
                    metin: "Roller ve Yetkiler"
                    secili: icerikYiginlar.currentIndex === 2
                    onTiklandi: root.sekmeyiAc(2)
                }

                YanMenuButonu {
                    metin: "Sistem Ayarları"
                    secili: icerikYiginlar.currentIndex === 3
                    onTiklandi: root.sekmeyiAc(3)
                }

                YanMenuButonu {
                    metin: "İşlem Geçmişi"
                    secili: icerikYiginlar.currentIndex === 4
                    onTiklandi: root.sekmeyiAc(4)
                }

                YanMenuButonu {
                    metin: "Cihaz Maliyetleri"
                    secili: icerikYiginlar.currentIndex === 5
                    onTiklandi: root.sekmeyiAc(5)
                }

                Item { Layout.fillHeight: true }

                TemaDegistirici {
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // ---- Sag icerik ----
        StackLayout {
            id: icerikYiginlar
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.baslangicSekmesi

            SekmeYukleyici {
                id: ozetYukleyici
                sekme: 0
                sourceComponent: YonetimOzetPage {
                    otomatikYukle: false
                }
            }

            SekmeYukleyici {
                id: personellerimYukleyici
                sekme: 1
                sourceComponent: PersonellerimPage {
                    otomatikYukle: false
                    // Kendi satirini ayirt edip kendi hesabini pasife alma
                    // butonunu kapatmak icin (sunucu da reddeder, bkz.
                    // Database::personelAktifDurumDegistir).
                    aktifKullaniciId: root.kullaniciId
                    duzenleyebilir: root.yonetimDuzenleyebilir
                }
            }

            SekmeYukleyici {
                id: rollerYukleyici
                sekme: 2
                sourceComponent: RollerYetkilerPage {
                    otomatikYukle: false
                    duzenleyebilir: root.yonetimDuzenleyebilir
                }
            }

            SekmeYukleyici {
                id: ayarlarYukleyici
                sekme: 3
                sourceComponent: SistemAyarlariPage {
                    otomatikYukle: false
                    duzenleyebilir: root.yonetimDuzenleyebilir
                }
            }

            SekmeYukleyici {
                id: gecmisYukleyici
                sekme: 4
                sourceComponent: IslemGecmisiPage {
                    otomatikYukle: false
                }
            }

            SekmeYukleyici {
                id: cihazlarYukleyici
                sekme: 5
                sourceComponent: CihazMaliyetleriPage {
                    otomatikYukle: false
                }
            }
        }
    }

    OnayDialog { id: cikisOnayi }
}
