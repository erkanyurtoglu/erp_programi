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
Item {
    id: root

    property var oturum: null
    property int baslangicSekmesi: 0   // varsayilan: Teklif Ver

    signal anaMenuyeDon()

    readonly property int kullaniciId: root.oturum ? (root.oturum.kullaniciId || 0) : 0

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
                YanMenuButonu {
                    metin: "Giden Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 1
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 1
                        gidenTekliflerPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Alınan Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 2
                    onTiklandi: {
                        icerikYiginlar.currentIndex = 2
                        alinanTekliflerPage.sayfayiYukle(1)
                    }
                }
                YanMenuButonu {
                    metin: "Biten Tekliflerim"
                    secili: icerikYiginlar.currentIndex === 3
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
            GecmisTekliflerPage {
                id: gidenTekliflerPage
                durumFiltresi: ""
                baslikMetni: "Giden Tekliflerim"
                otomatikYukle: false
            }

            GecmisTekliflerPage {
                id: alinanTekliflerPage
                durumFiltresi: "Kabul Edildi"
                baslikMetni: "Alınan Tekliflerim"
                otomatikYukle: false
            }

            GecmisTekliflerPage {
                id: bitenTekliflerPage
                durumFiltresi: "Tamamlandı"
                baslikMetni: "Biten Tekliflerim"
                otomatikYukle: false
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
        }
    }
}
