import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim / Islem Gecmisi: tum tekliflerdeki olaylar (olusturma / revizyon,
// durum degisikligi, duzeltme) yeniden eskiye, sayfali. Kaynaklar ve hangi
// olayin sayildigi: bkz. islemGecmisiSorgusu (AramaSorgulari.cpp).
// Satirdaki "Teklif" butonu teklifin PDF'ini onizlemede acar.
Item {
    id: root

    readonly property int sayfaBoyutu: 50
    property bool otomatikYukle: true

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlar: []
    property var personeller: []

    // Suzgecler
    property string aramaMetni: ""
    property int kullaniciId: 0
    property string tur: ""
    property string baslangic: ""
    property string bitis: ""

    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    readonly property bool suzgecVar: root.aramaMetni.trim().length > 0 || root.kullaniciId > 0
                                      || root.tur.length > 0 || root.baslangic.length > 0
                                      || root.bitis.length > 0

    function sayfayiYukle(sayfaNo) {
        root.listeHatasi = ""
        root.yukleniyor = true
        root.bekleyenIstek = database.islemGecmisiGetirBaslat({
            arama: root.aramaMetni,
            kullaniciId: root.kullaniciId,
            tur: root.tur,
            baslangic: root.baslangic,
            bitis: root.bitis
        }, sayfaNo, root.sayfaBoyutu)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onIslemGecmisiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false
            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "İşlem geçmişi yüklenemedi: veritabanına bağlanılamadı."
                root.kayitlar = []
                return
            }
            root.sayfaSonucu = sonuc
            root.kayitlar = sonuc.kayitlar
            root.personeller = sonuc.personeller
        }
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle(1)

    Timer {
        id: zamanAsimiZamanlayici
        interval: 25000
        onTriggered: {
            if (!root.yukleniyor)
                return
            root.yukleniyor = false
            root.listeHatasi = "İşlem geçmişi sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    Timer {
        id: aramaZamanlayici
        interval: 350
        onTriggered: root.sayfayiYukle(1)
    }

    function turAdi(tur) {
        return tur === "olusturma" ? "Oluşturma" : tur === "durum" ? "Durum" : tur === "duzeltme" ? "Düzeltme" : ""
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Label {
                    text: "İşlem Geçmişi"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.sayfaSonucu.toplamKayit + " kayıt"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            SuzgecHapi { metin: "Tümü"; secili: root.tur === ""; onTiklandi: { root.tur = ""; root.sayfayiYukle(1) } }
            SuzgecHapi { metin: "Oluşturma"; secili: root.tur === "olusturma"; onTiklandi: { root.tur = "olusturma"; root.sayfayiYukle(1) } }
            SuzgecHapi { metin: "Durum"; secili: root.tur === "durum"; onTiklandi: { root.tur = "durum"; root.sayfayiYukle(1) } }
            SuzgecHapi { metin: "Düzeltme"; secili: root.tur === "duzeltme"; onTiklandi: { root.tur = "duzeltme"; root.sayfayiYukle(1) } }
        }

        // ---- Arama, personel, tarih ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            TemaMetinKutusu {
                Layout.fillWidth: true
                placeholderText: "Teklif no veya firma adı ara..."
                onTextChanged: {
                    root.aramaMetni = text
                    aramaZamanlayici.restart()
                }
            }

            Rectangle {
                Layout.preferredWidth: 220
                Layout.preferredHeight: Theme.girdiYuksekligi
                radius: Theme.radiusKucuk
                color: Theme.arkaplan
                border.width: 1
                border.color: Theme.kenarlik

                TemaComboBox {
                    id: personelKutusu
                    anchors.fill: parent
                    model: [{ kullaniciId: 0, adSoyad: "Tüm personel" }].concat(
                               root.personeller.map(p => ({
                                   kullaniciId: p.kullaniciId,
                                   adSoyad: p.adSoyad + (p.aktifMi ? "" : " (pasif)")
                               })))
                    textRole: "adSoyad"
                    valueRole: "kullaniciId"
                    // Liste her yuklemede yeniden kuruldugu icin secim degerden geri bulunur.
                    currentIndex: Math.max(0, indexOfValue(root.kullaniciId))
                    onActivated: {
                        root.kullaniciId = currentValue
                        root.sayfayiYukle(1)
                    }
                }
            }

            TarihSecici {
                kompakt: true
                bosMetin: "Başlangıç"
                deger: root.baslangic
                onSecildi: (tarih) => { root.baslangic = tarih; root.sayfayiYukle(1) }
            }
            TarihSecici {
                kompakt: true
                bosMetin: "Bitiş"
                deger: root.bitis
                onSecildi: (tarih) => { root.bitis = tarih; root.sayfayiYukle(1) }
            }
        }

        // ---- Tablo basligi ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: Theme.panel
            radius: Theme.radiusKucuk
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10
                Label { text: "TARİH"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 120 }
                Label { text: "İŞLEM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true; Layout.preferredWidth: 2 }
                Label { text: "TEKLİF"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 90 }
                Label { text: "FİRMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true; Layout.preferredWidth: 1 }
                Label { text: "PERSONEL"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 150 }
                Item { Layout.preferredWidth: 70 }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                anchors.fill: parent
                clip: true
                spacing: 4
                model: root.kayitlar

                delegate: Rectangle {
                    id: satir
                    required property var modelData

                    width: ListView.view.width
                    height: Math.max(48, islemSutunu.implicitHeight + 16)
                    radius: Theme.radiusKucuk
                    color: satirAlani.containsMouse ? Theme.panelHover : Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik

                    MouseArea {
                        id: satirAlani
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Label {
                            text: satir.modelData.tarih
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk + 1
                            Layout.preferredWidth: 120
                        }

                        ColumnLayout {
                            id: islemSutunu
                            Layout.fillWidth: true
                            Layout.preferredWidth: 2
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    Layout.preferredWidth: turYazisi.implicitWidth + 12
                                    Layout.preferredHeight: 18
                                    radius: 4
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Theme.kenarlik
                                    Text {
                                        id: turYazisi
                                        anchors.centerIn: parent
                                        text: root.turAdi(satir.modelData.tur)
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 10
                                    }
                                }
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: satir.modelData.baslik
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    elide: Text.ElideRight
                                }
                            }
                            Label {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                text: satir.modelData.aciklama
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Label {
                            text: satir.modelData.teklifNo
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            font.bold: true
                            Layout.preferredWidth: 90
                        }
                        KisalanMetin {
                            text: satir.modelData.firmaAdi
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                        }
                        KisalanMetin {
                            text: satir.modelData.personel.length > 0 ? satir.modelData.personel : "—"
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            elide: Text.ElideRight
                            Layout.preferredWidth: 150
                        }
                        TemaButon {
                            kucuk: true
                            text: "Teklif"
                            Layout.preferredWidth: 70
                            onClicked: PdfOnizleme.ac("teklif", satir.modelData.teklifId,
                                                      "Teklif " + satir.modelData.teklifNo)
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.kayitlar.length
                aramaVar: root.suzgecVar
                bosMetin: "Henüz kayıtlı işlem yok."
                aramaBosMetni: "Seçilen süzgeçlere uyan işlem bulunamadı."
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            TemaButon {
                text: "◀ Önceki"
                enabled: root.sayfaSonucu.mevcutSayfa > 1 && !root.yukleniyor
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa - 1)
            }
            Label {
                text: "Sayfa " + root.sayfaSonucu.mevcutSayfa + " / " + root.sayfaSonucu.toplamSayfa
                color: Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
            }
            TemaButon {
                text: "Sonraki ▶"
                enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa && !root.yukleniyor
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa + 1)
            }
        }
    }
}
