import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Siparisin acilir pencereleri: ayrinti, patron onayi, teslim alma,
// teslimat (kargo / yola cikis) ve fatura. Hem siparis listelerinde hem talep
// ekraninda kullanilir: Yasin Bey "siparisim ne durumda?" dediginde Yesim Hanim
// talebinden cikmadan kalemin siparisini acar.
//
// Pencereler bu ogeye ortalanir; kullanan sayfa anchors.fill ile yerlestirir.
// Basarili islemden sonra islemYapildi yayilir, kullanan taraf listesini
// tazeler.
Item {
    id: root

    property bool duzenleyebilir: true
    // Ayrintidaki "Talep ›" baglantisi; talep ekranindan acilinca gereksiz.
    property bool talepBaglantisi: true

    property int seciliId: 0
    property var detay: ({})
    property string hata: ""

    signal islemYapildi(string mesaj)
    signal hataOldu(string mesaj)
    signal talepAc(int talepId)

    function detayYukle() {
        root.detay = database.satinalmaGetir(root.seciliId)
        if (root.detay.satinalmaId === undefined)
            root.seciliId = 0
    }

    function sec(satinalmaId) {
        root.seciliId = satinalmaId
        root.hata = ""
        root.detayYukle()
        return root.seciliId > 0
    }

    function islemSonucu(sonuc, basariMesaji) {
        if (!sonuc.basarili) {
            root.hata = sonuc.hata
            root.hataOldu(sonuc.hata)
            return false
        }
        root.hata = ""
        root.detayYukle()
        root.islemYapildi(basariMesaji || "")
        return true
    }

    function ayrintiAc(id) {
        if (root.sec(id))
            detayDialogu.open()
    }
    function onayIsaretle(id) {
        if (!root.sec(id))
            return
        onayDialogu.iste("Patron Onayı",
                         SatinalmaBicim.siparisNo(root.detay.siparisNo) + " için patronun onayını aldığınızı "
                         + "işaretliyorsunuz. Kayda adınız ve tarih yazılır.",
                         "Onay Alındı", false,
                         function() {
                             root.islemSonucu(database.satinalmaOnayiIsaretle(id), "Patron onayı işaretlendi.")
                         })
    }
    function sevkiyatAc(id, yola) {
        if (root.sec(id))
            sevkiyatDialogu.ac(yola)
    }
    function teslimAc(id) {
        if (root.sec(id))
            teslimDialogu.ac()
    }
    function faturaAc(id) {
        if (root.sec(id))
            faturaDialogu.ac()
    }

    OnayDialog { id: onayDialogu }

    // ================================================================ AYRINTI
    // Ust: durum, tutar, baglantilar. Altinda TEK eylem cubugu (siradaki is +
    // diger islemler, iptal en sagda). Sonra kalemler ve uc bilgi karti.
    TemaDialog {
        id: detayDialogu
        baslik: SatinalmaBicim.siparisNo(detayDialogu.d.siparisNo || 0) + "  ·  " + (detayDialogu.d.tedarikciAdi || "")
        onayGorunur: false
        iptalMetni: "Kapat"
        width: Math.min(root.width - 60, 900)

        readonly property var d: root.detay
        readonly property string durum: detayDialogu.d.durum || ""
        readonly property bool kargolu: SatinalmaBicim.kargoluMu(detayDialogu.d.teslimatSekli || "")
        readonly property bool acik: SatinalmaBicim.acikMi(detayDialogu.durum)
        readonly property bool teslimVar: detayDialogu.durum === "Teslim Alındı" || detayDialogu.durum === "Kısmi Teslim"
        readonly property int gecikme: {
            const b = detayDialogu.d.beklenenTeslimTarihi || ""
            if (!detayDialogu.acik || b.length === 0)
                return 0
            const p = b.split("-")
            const beklenen = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
            const bugun = new Date()
            bugun.setHours(0, 0, 0, 0)
            return Math.round((bugun - beklenen) / 86400000)
        }
        readonly property bool faturaVar: (detayDialogu.d.faturaNo || "").length > 0
        readonly property real faturaFarki: (detayDialogu.d.faturaTutariTL || 0) > 0
                                            ? detayDialogu.d.faturaTutariTL - (detayDialogu.d.toplamTutarTL || 0) : 0

        // Kalemlerde urun linki varsa ustteki "Sipariş sayfası" ayni sayfayi
        // acar; gosterilmez.
        readonly property bool kalemLinkiVar: (detayDialogu.d.kalemler || [])
                                              .some(k => (k.urunLinki || "").length > 0)
        readonly property bool duzenlenebilir: root.duzenleyebilir && detayDialogu.durum !== "İptal"
                                               && detayDialogu.durum !== "Reddedildi"

        // Baslikli bilgi karti; duzenleMetni doluysa basligin saginda
        // duzenleme baglantisi cikar.
        component BilgiKarti: Rectangle {
            id: kart
            default property alias icerik: kartGovde.data
            property string baslik: ""
            property string duzenleMetni: ""
            signal duzenle()
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            implicitHeight: kartSutun.implicitHeight + 28
            radius: Theme.radiusNormal
            color: Theme.panelVurgu
            border.width: 1
            border.color: Theme.kenarlik
            ColumnLayout {
                id: kartSutun
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: kart.baslik
                        color: Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        font.bold: true
                    }
                    Baglanti {
                        visible: kart.duzenleMetni.length > 0
                        text: kart.duzenleMetni
                        font.pixelSize: Theme.fontBoyutKucuk
                        onTiklandi: kart.duzenle()
                    }
                }
                ColumnLayout {
                    id: kartGovde
                    Layout.fillWidth: true
                    spacing: 7
                }
            }
        }

        component Bilgi: RowLayout {
            id: bilgiSatiri
            property string etiket: ""
            property string deger: ""
            property color renk: Theme.metinBirincil
            Layout.fillWidth: true
            visible: bilgiSatiri.deger.length > 0
            spacing: 10
            Label {
                Layout.preferredWidth: 104
                Layout.alignment: Qt.AlignTop
                text: bilgiSatiri.etiket
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }
            Label {
                Layout.fillWidth: true
                text: bilgiSatiri.deger
                color: bilgiSatiri.renk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk + 1
                wrapMode: Text.WordWrap
            }
        }

        component Baglanti: Label {
            id: baglanti
            signal tiklandi()
            color: baglantiFare.containsMouse ? Theme.vurguHover : Theme.vurgu
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk + 1
            MouseArea {
                id: baglantiFare
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: baglanti.tiklandi()
            }
        }

        contentItem: ColumnLayout {
            spacing: 14

            // ---- Ozet ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                DurumRozeti {
                    metin: SatinalmaBicim.siparisDurumAdi(detayDialogu.durum, detayDialogu.d.teslimatSekli,
                                                         detayDialogu.d.eksikKapatildi)
                    renk: SatinalmaBicim.siparisDurumRengi(detayDialogu.durum)
                    dolu: true
                }
                DurumRozeti {
                    visible: detayDialogu.gecikme > 0
                    metin: detayDialogu.gecikme + " gün gecikti"
                    renk: Theme.tehlikeAcik
                    dolu: true
                }
                Label {
                    text: SatinalmaBicim.para(detayDialogu.d.toplamTutarTL || 0)
                    color: Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutOrta
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Baglanti {
                    visible: root.talepBaglantisi && (detayDialogu.d.talepNo || 0) > 0
                    text: "Talep " + SatinalmaBicim.talepNo(detayDialogu.d.talepNo || 0) + "  ›"
                    onTiklandi: {
                        detayDialogu.close()
                        root.talepAc(detayDialogu.d.talepId)
                    }
                }
                Baglanti {
                    visible: (detayDialogu.d.siparisLinki || "").length > 0 && !detayDialogu.kalemLinkiVar
                    text: "Sipariş sayfası  ↗"
                    onTiklandi: Qt.openUrlExternally(detayDialogu.d.siparisLinki)
                }
            }

            // ---- Eylem cubugu ----
            Rectangle {
                Layout.fillWidth: true
                visible: root.duzenleyebilir && detayDialogu.durum !== "İptal" && detayDialogu.durum !== "Reddedildi"
                implicitHeight: eylemSatiri.implicitHeight + 20
                radius: Theme.radiusNormal
                color: Theme.arkaplanIkincil
                border.width: 1
                border.color: Theme.kenarlik

                RowLayout {
                    id: eylemSatiri
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    SiparisEylemleri {
                        kayit: detayDialogu.d
                        tumu: true
                        faturaGoster: false
                        onOnayIstendi: (id) => root.onayIsaretle(id)
                        onSevkiyatIstendi: (id) => root.sevkiyatAc(id, true)
                        onTeslimIstendi: (id) => root.teslimAc(id)
                        onFaturaIstendi: (id) => root.faturaAc(id)
                    }
                    // Teslimat ve fatura bilgisi kartlarin "Düzenle" baglantisindan girilir.
                    // Kalan gelmeyecekse siparis eksik kapatilir; iptal mali
                    // gelmis sipariste yapilamaz.
                    TemaButon {
                        visible: detayDialogu.durum === "Kısmi Teslim"
                        tur: "uyari"
                        kucuk: true
                        text: "Eksik Kapat"
                        onClicked: eksikKapatDialogu.ac()
                    }
                    TemaButon {
                        visible: detayDialogu.teslimVar
                        kucuk: true
                        text: "Teslimi Geri Al"
                        onClicked: onayDialogu.iste(
                            "Teslimi Geri Al",
                            "Gelen miktarlar sıfırlanır, sipariş teslimden önceki durumuna döner."
                            + (detayDialogu.d.eksikKapatildi
                               ? " Eksik kapatma kaldırılır; eksik miktar için talepte açılan kalemler silinir." : ""),
                            "Geri Al", true,
                            function() {
                                root.islemSonucu(database.satinalmaDurumGuncelle(root.seciliId, "Sipariş Verildi"),
                                                 "Teslim geri alındı.")
                            })
                    }

                    Item { Layout.fillWidth: true }

                    TemaButon {
                        visible: detayDialogu.acik && detayDialogu.durum !== "Kısmi Teslim"
                        tur: "tehlike"
                        kucuk: true
                        text: "Siparişi İptal Et"
                        onClicked: onayDialogu.iste(
                            "Siparişi İptal Et",
                            SatinalmaBicim.siparisNo(detayDialogu.d.siparisNo) + " iptal edilecek."
                            + (detayDialogu.d.talepNo > 0 ? " Kalemleri talepte yeniden açılır." : ""),
                            "İptal Et", true,
                            function() {
                                root.islemSonucu(database.satinalmaDurumGuncelle(root.seciliId, "İptal"),
                                                 "Sipariş iptal edildi.")
                            })
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: root.hata.length > 0
                text: root.hata
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }

            ScrollView {
                id: detayKaydirma
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(detayIcerik.implicitHeight, root.height - 300)
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: detayIcerik
                    width: detayKaydirma.availableWidth
                    spacing: 14

                    // ---- Kalemler ----
                    Label {
                        text: "KALEMLER"
                        color: Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        font.bold: true
                    }

                    Repeater {
                        model: detayDialogu.d.kalemler || []
                        delegate: Rectangle {
                            id: kalemKarti
                            required property var modelData
                            readonly property var teklifler: kalemKarti.modelData.teklifler || []
                            readonly property real oran: kalemKarti.modelData.adet > 0
                                                         ? Math.min(1, kalemKarti.modelData.gelenAdet / kalemKarti.modelData.adet) : 0

                            Layout.fillWidth: true
                            implicitHeight: kalemSutun.implicitHeight + 24
                            radius: Theme.radiusNormal
                            color: Theme.panelVurgu
                            border.width: 1
                            border.color: Theme.kenarlik

                            ColumnLayout {
                                id: kalemSutun
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        KisalanMetin {
                                            Layout.fillWidth: true
                                            text: kalemKarti.modelData.kalemAdi
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            font.bold: true
                                        }
                                        KisalanMetin {
                                            Layout.fillWidth: true
                                            text: SatinalmaBicim.miktar(kalemKarti.modelData.adet) + " "
                                                  + (kalemKarti.modelData.birim || "") + "  ×  "
                                                  + SatinalmaBicim.dovizli(kalemKarti.modelData.birimFiyat, kalemKarti.modelData.paraBirimi)
                                                  + (kalemKarti.modelData.paraBirimi !== "TL"
                                                     ? "   (kur " + SayiBicimi.bicimle(kalemKarti.modelData.kur, 4) + ")" : "")
                                                  + ((kalemKarti.modelData.neIcin || "").length > 0
                                                     ? "     " + kalemKarti.modelData.neIcin : "")
                                            color: Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.preferredWidth: 160
                                        spacing: 5
                                        Label {
                                            Layout.alignment: Qt.AlignRight
                                            text: "Gelen  " + SatinalmaBicim.miktar(kalemKarti.modelData.gelenAdet)
                                                  + " / " + SatinalmaBicim.miktar(kalemKarti.modelData.adet)
                                            color: kalemKarti.oran >= 1 ? Theme.basariAcik : Theme.metinSoluk
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutKucuk
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 4
                                            radius: 2
                                            color: Theme.kenarlik
                                            Rectangle {
                                                width: parent.width * kalemKarti.oran
                                                height: parent.height
                                                radius: 2
                                                color: kalemKarti.oran >= 1 ? Theme.basari : Theme.uyari
                                            }
                                        }
                                    }
                                    Label {
                                        Layout.preferredWidth: 120
                                        horizontalAlignment: Text.AlignRight
                                        text: SatinalmaBicim.para(kalemKarti.modelData.toplamTutarTL)
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutNormal
                                        font.bold: true
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: (kalemKarti.modelData.urunLinki || "").length > 0 || kalemKarti.teklifler.length > 1
                                    spacing: 16
                                    Baglanti {
                                        visible: (kalemKarti.modelData.urunLinki || "").length > 0
                                        text: "Ürün sayfası  ↗"
                                        font.pixelSize: Theme.fontBoyutKucuk
                                        onTiklandi: Qt.openUrlExternally(kalemKarti.modelData.urunLinki)
                                    }
                                    // Piyasa arastirmasi yapilmissa alinan diger fiyatlar
                                    Label {
                                        Layout.fillWidth: true
                                        visible: kalemKarti.teklifler.length > 1
                                        textFormat: Text.StyledText
                                        text: "Alınan fiyatlar:  " + kalemKarti.teklifler.map(function(t) {
                                            const fiyat = SatinalmaBicim.dovizli(t.birimFiyat, t.paraBirimi)
                                            return t.secildi ? "<b>" + t.firmaAdi + " " + fiyat + " ✓</b>"
                                                             : t.firmaAdi + " " + fiyat
                                        }).join("   ·   ")
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    // ---- Bilgi kartlari ----
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 12

                        BilgiKarti {
                            baslik: "TESLİMAT"
                            duzenleMetni: detayDialogu.duzenlenebilir ? "Düzenle" : ""
                            onDuzenle: sevkiyatDialogu.ac(false)
                            Bilgi { etiket: "Teslimat şekli"; deger: detayDialogu.d.teslimatSekli || "Belirtilmedi" }
                            Bilgi {
                                etiket: "Beklenen teslim"
                                deger: detayDialogu.d.beklenenTeslimTarihi
                                       ? SatinalmaBicim.tarih(detayDialogu.d.beklenenTeslimTarihi) : "Girilmedi"
                                renk: detayDialogu.gecikme > 0 ? Theme.tehlikeAcik
                                    : detayDialogu.d.beklenenTeslimTarihi ? Theme.metinBirincil : Theme.metinSoluk
                            }
                            Bilgi { etiket: "Site sipariş no"; deger: detayDialogu.d.siteSiparisNo || "" }
                            Bilgi { etiket: "Kargo firması"; deger: detayDialogu.kargolu ? (detayDialogu.d.kargoFirmasi || "—") : "" }
                            Bilgi { etiket: "Takip no"; deger: detayDialogu.kargolu ? (detayDialogu.d.kargoTakipNo || "—") : "" }
                            Bilgi { etiket: "Teslim alındı"; deger: SatinalmaBicim.tarih(detayDialogu.d.teslimAlmaTarihi || "") }
                        }

                        BilgiKarti {
                            baslik: "SİPARİŞ"
                            Bilgi { etiket: "Sipariş tarihi"; deger: SatinalmaBicim.tarih(detayDialogu.d.satinalmaTarihi || "") }
                            Bilgi { etiket: "Oluşturan"; deger: detayDialogu.d.olusturan || "" }
                            Bilgi { etiket: "İsteyen"; deger: detayDialogu.d.isteyenKisi || "" }
                            Bilgi { etiket: "Birim"; deger: detayDialogu.d.isteyenBirim || "" }
                            Bilgi { etiket: "Ne zaman lazım"; deger: SatinalmaBicim.tarih(detayDialogu.d.ihtiyacTarihi || "") }
                            Bilgi {
                                etiket: "Tedarikçi"
                                deger: [detayDialogu.d.tedarikciIlgiliKisi || "", detayDialogu.d.tedarikciTelefon || ""]
                                       .filter(p => p.length > 0).join(" · ")
                            }
                            Bilgi {
                                etiket: "Patron onayı"
                                deger: !detayDialogu.d.patronOnayiGerekli ? ""
                                       : detayDialogu.d.patronOnayli
                                         ? "Onaylandı (" + (detayDialogu.d.onayiIsaretleyen || "") + ", "
                                           + (detayDialogu.d.patronOnayTarihi || "") + ")"
                                         : "Bekliyor"
                                renk: detayDialogu.d.patronOnayli ? Theme.basariAcik : Theme.uyariAcik
                            }
                            Bilgi { etiket: "Tek teklif"; deger: detayDialogu.d.tekTeklifGerekcesi || "" }
                            Bilgi { etiket: "Red sebebi"; deger: detayDialogu.d.redSebebi || ""; renk: Theme.tehlikeAcik }
                            Bilgi {
                                etiket: "Eksik kapatıldı"
                                deger: !detayDialogu.d.eksikKapatildi ? ""
                                       : (detayDialogu.d.eksikKapatmaSebebi || "") + " ("
                                         + [detayDialogu.d.eksikKapatan || "", detayDialogu.d.eksikKapatmaTarihi || ""]
                                           .filter(p => p.length > 0).join(", ") + ")"
                                renk: Theme.uyariAcik
                            }
                        }

                        BilgiKarti {
                            baslik: "FATURA"
                            duzenleMetni: !detayDialogu.duzenlenebilir ? ""
                                          : detayDialogu.faturaVar ? "Düzenle" : "Fatura Gir"
                            onDuzenle: faturaDialogu.ac()
                            Bilgi {
                                etiket: "Fatura no"
                                deger: detayDialogu.d.faturaNo || "Girilmedi"
                                renk: detayDialogu.faturaVar ? Theme.metinBirincil : Theme.uyariAcik
                            }
                            Bilgi { etiket: "Tarih"; deger: SatinalmaBicim.tarih(detayDialogu.d.faturaTarihi || "") }
                            Bilgi {
                                etiket: "Tutar"
                                deger: (detayDialogu.d.faturaTutariTL || 0) > 0
                                       ? SatinalmaBicim.para(detayDialogu.d.faturaTutariTL)
                                         + (Math.abs(detayDialogu.faturaFarki) >= 0.01
                                            ? "  (" + (detayDialogu.faturaFarki > 0 ? "+" : "−")
                                              + SatinalmaBicim.para(Math.abs(detayDialogu.faturaFarki)) + ")" : "")
                                       : ""
                                renk: detayDialogu.faturaFarki > 0.009 ? Theme.tehlikeAcik : Theme.metinBirincil
                            }
                            Bilgi {
                                etiket: "Muhasebe"
                                deger: detayDialogu.faturaVar ? (detayDialogu.d.muhasebeyeIletildi ? "İletildi" : "İletilmedi") : ""
                                renk: detayDialogu.d.muhasebeyeIletildi ? Theme.basariAcik : Theme.uyariAcik
                            }
                        }
                    }
                }
            }
        }
    }

    // ================================================================ TESLIM
    // 10 istenip 6 gelmesi sik oldugu icin teslim kalem bazinda alinir; eksik
    // kalirsa siparis "Kısmi Teslim" olarak acik kalir.
    ListModel { id: teslimModel }

    TemaDialog {
        id: teslimDialogu
        baslik: "Teslim Al — " + SatinalmaBicim.siparisNo(root.detay.siparisNo || 0)
        onayMetni: "Teslim Aldım"
        elleKapat: true
        width: 600

        function ac() {
            teslimModel.clear()
            for (const k of (root.detay.kalemler || [])) {
                // Varsayilan: siparis edilen miktarin tamami. Eksik gelen
                // varsa kullanici yalnizca o satiri duzeltir.
                teslimModel.append({ satinalmaKalemId: k.satinalmaKalemId, kalemAdi: k.kalemAdi,
                                     birim: k.birim || "", adet: k.adet, oncekiGelen: k.gelenAdet,
                                     gelenAdet: k.adet })
            }
            teslimHatasi.text = ""
            teslimDialogu.open()
        }

        onOnaylandi: {
            var liste = []
            for (var i = 0; i < teslimModel.count; ++i)
                liste.push({ satinalmaKalemId: teslimModel.get(i).satinalmaKalemId,
                             gelenAdet: teslimModel.get(i).gelenAdet })
            const sonuc = database.satinalmaTeslimAl(root.seciliId, liste)
            if (!sonuc.basarili) {
                teslimHatasi.text = sonuc.hata
                return
            }
            teslimDialogu.close()
            root.islemSonucu(sonuc, sonuc.durum === "Teslim Alındı"
                                    ? SatinalmaBicim.siparisNo(root.detay.siparisNo) + " teslim alındı."
                                    : "Kısmi teslim kaydedildi; eksikler bekleniyor.")
        }

        contentItem: ColumnLayout {
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label { text: "KALEM"; Layout.fillWidth: true; color: Theme.metinCokSoluk; font.pixelSize: 10; font.bold: true; font.family: Theme.fontAilesi }
                Label { text: "SİPARİŞ"; Layout.preferredWidth: 90; color: Theme.metinCokSoluk; font.pixelSize: 10; font.bold: true; font.family: Theme.fontAilesi }
                Label { text: "GELEN (TOPLAM)"; Layout.preferredWidth: 120; color: Theme.metinCokSoluk; font.pixelSize: 10; font.bold: true; font.family: Theme.fontAilesi }
            }

            Repeater {
                model: teslimModel
                delegate: RowLayout {
                    id: teslimSatiri
                    required property int index
                    required property string kalemAdi
                    required property string birim
                    required property real adet
                    required property real oncekiGelen
                    required property real gelenAdet

                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        KisalanMetin {
                            Layout.fillWidth: true
                            text: teslimSatiri.kalemAdi
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                        }
                        Label {
                            visible: teslimSatiri.oncekiGelen > 0
                            text: "daha önce gelen: " + SatinalmaBicim.miktar(teslimSatiri.oncekiGelen)
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                        }
                    }
                    Label {
                        Layout.preferredWidth: 90
                        text: SatinalmaBicim.miktar(teslimSatiri.adet) + " " + teslimSatiri.birim
                        color: Theme.metinIkincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                    }
                    SayiKutusu {
                        Layout.preferredWidth: 120
                        ondalik: 3
                        deger: teslimSatiri.gelenAdet
                        vurgulu: teslimSatiri.gelenAdet < teslimSatiri.adet
                        onDegisti: (yeni) => teslimModel.setProperty(teslimSatiri.index, "gelenAdet",
                                                                     Math.min(yeni, teslimSatiri.adet))
                    }
                }
            }

            Label {
                id: teslimHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }

    // ================================================================ EKSIK KAPAT
    // 10 istenip 6 gelmis ve kalan 4 gelmeyecekse: siparis kapanir, eksik
    // miktar istenirse talepte yeni kalem olarak acilir (baska yerden alinir).
    TemaDialog {
        id: eksikKapatDialogu
        baslik: "Eksik Kapat — " + SatinalmaBicim.siparisNo(root.detay.siparisNo || 0)
        onayMetni: "Siparişi Kapat"
        onayEtkin: eksikSebep.text.trim().length > 0
        elleKapat: true
        width: 520

        readonly property var eksikler: (root.detay.kalemler || []).filter(k => (k.adet || 0) - (k.gelenAdet || 0) > 0.0005)

        function ac() {
            eksikSebep.text = ""
            eksikTalebeAc.checked = true
            eksikHatasi.text = ""
            eksikKapatDialogu.open()
        }

        onOnaylandi: {
            const talepli = (root.detay.talepNo || 0) > 0
            const sonuc = database.satinalmaEksikKapat(root.seciliId, eksikSebep.text,
                                                       talepli && eksikTalebeAc.checked)
            if (!sonuc.basarili) {
                eksikHatasi.text = sonuc.hata
                return
            }
            eksikKapatDialogu.close()
            root.islemSonucu(sonuc, SatinalmaBicim.siparisNo(root.detay.siparisNo) + " eksik kapatıldı."
                                    + (sonuc.acilanKalemSayisi > 0
                                       ? " " + sonuc.acilanKalemSayisi + " kalem talepte yeniden açıldı." : ""))
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                text: "GELMEYECEK MİKTAR"
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            Repeater {
                model: eksikKapatDialogu.eksikler
                delegate: RowLayout {
                    id: eksikSatiri
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    KisalanMetin {
                        Layout.fillWidth: true
                        text: eksikSatiri.modelData.kalemAdi
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                    }
                    Label {
                        text: SatinalmaBicim.miktar(eksikSatiri.modelData.adet - eksikSatiri.modelData.gelenAdet)
                              + " " + (eksikSatiri.modelData.birim || "")
                        color: Theme.uyariAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                    }
                }
            }

            EtiketliAlan {
                id: eksikSebep
                etiket: "KALAN NEDEN GELMEYECEK? *"
                placeholderText: "Örn: Tedarikçide stok bitti"
            }

            TemaOnayKutusu {
                id: eksikTalebeAc
                visible: (root.detay.talepNo || 0) > 0
                text: "Eksik miktarı talepte yeniden aç"
            }

            Label {
                id: eksikHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }

    // ================================================================ TESLIMAT
    TemaDialog {
        id: sevkiyatDialogu
        baslik: (sevkiyatDialogu.yolaCikis ? (sevkiyatDialogu.kargolu ? "Kargoya Verildi" : "Yola Çıktı")
                                           : "Teslimat Bilgisi")
                + " — " + SatinalmaBicim.siparisNo(root.detay.siparisNo || 0)
        onayMetni: "Kaydet"
        elleKapat: true
        width: 520

        property bool yolaCikis: false
        property string sekil: ""
        readonly property bool kargolu: SatinalmaBicim.kargoluMu(sevkiyatDialogu.sekil)

        function ac(yola) {
            sevkiyatDialogu.yolaCikis = yola
            sevkiyatDialogu.sekil = root.detay.teslimatSekli || "Kargo"
            sevkFirma.text = root.detay.kargoFirmasi || ""
            sevkTakip.text = root.detay.kargoTakipNo || ""
            sevkSiteNo.text = root.detay.siteSiparisNo || ""
            sevkTarih.deger = root.detay.beklenenTeslimTarihi || ""
            sevkHatasi.text = ""
            sevkiyatDialogu.open()
        }

        onOnaylandi: {
            const sonuc = database.satinalmaSevkiyatGuncelle(root.seciliId, {
                teslimatSekli: sevkiyatDialogu.sekil, kargoFirmasi: sevkFirma.text,
                kargoTakipNo: sevkTakip.text, siteSiparisNo: sevkSiteNo.text,
                beklenenTeslimTarihi: sevkTarih.deger,
                yolaCikti: sevkiyatDialogu.yolaCikis })
            if (!sonuc.basarili) {
                sevkHatasi.text = sonuc.hata
                return
            }
            sevkiyatDialogu.close()
            root.islemSonucu(sonuc, sevkiyatDialogu.yolaCikis ? "Sipariş yolda olarak işaretlendi."
                                                              : "Teslimat bilgisi kaydedildi.")
        }

        contentItem: ColumnLayout {
            spacing: 12

            // Internet siparisinde sitenin verdigi numara: "kargom nerede"
            // sorusunda sitede aramak icin.
            EtiketliAlan {
                id: sevkSiteNo
                visible: root.detay.siparisKaynagi === "İnternet" || (root.detay.siteSiparisNo || "").length > 0
                etiket: "SİTE SİPARİŞ NO"
                placeholderText: "Hepsiburada / direnc.net sipariş numarası"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    text: "TESLİMAT ŞEKLİ"
                    color: Theme.metinSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi
                    radius: Theme.radiusKucuk
                    color: Theme.arkaplan
                    border.width: 1
                    border.color: Theme.kenarlik
                    TemaComboBox {
                        anchors.fill: parent
                        model: SatinalmaBicim.teslimatSekilleri
                        currentIndex: Math.max(0, model.indexOf(sevkiyatDialogu.sekil))
                        onActivated: sevkiyatDialogu.sekil = currentText
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: sevkiyatDialogu.kargolu
                spacing: 10
                EtiketliAlan {
                    id: sevkFirma
                    etiket: sevkiyatDialogu.sekil === "Kargo" ? "KARGO FİRMASI" : "AMBAR / NAKLİYE FİRMASI"
                    placeholderText: "Aras, Yurtiçi, MNG…"
                }
                EtiketliAlan {
                    id: sevkTakip
                    etiket: "TAKİP NO"
                }
            }

            TarihSecici {
                id: sevkTarih
                Layout.fillWidth: true
                etiket: "BEKLENEN TESLİM TARİHİ"
                gecmisKapali: true
                onSecildi: (tarih) => sevkTarih.deger = tarih
            }

            Label {
                id: sevkHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }

    // ================================================================ FATURA
    TemaDialog {
        id: faturaDialogu
        baslik: "Fatura — " + SatinalmaBicim.siparisNo(root.detay.siparisNo || 0)
        onayMetni: "Kaydet"
        elleKapat: true
        width: 520

        readonly property real fark: faturaTutari.girilenDeger > 0
                                     ? faturaTutari.girilenDeger - (root.detay.toplamTutarTL || 0) : 0

        function ac() {
            faturaNo.text = root.detay.faturaNo || ""
            faturaTarihi.deger = root.detay.faturaTarihi || SatinalmaBicim.bugun()
            faturaTutari.deger = root.detay.faturaTutariTL || 0
            faturaTutari.yaz()
            muhasebeKutusu.checked = root.detay.muhasebeyeIletildi === true
            faturaHatasi.text = ""
            faturaDialogu.open()
        }

        onOnaylandi: {
            const sonuc = database.satinalmaFaturaGuncelle(root.seciliId, {
                faturaNo: faturaNo.text, faturaTarihi: faturaTarihi.deger,
                faturaTutariTL: faturaTutari.girilenDeger,
                muhasebeyeIletildi: muhasebeKutusu.checked })
            if (!sonuc.basarili) {
                faturaHatasi.text = sonuc.hata
                return
            }
            faturaDialogu.close()
            root.islemSonucu(sonuc, "Fatura bilgisi kaydedildi.")
        }

        contentItem: ColumnLayout {
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan {
                    id: faturaNo
                    etiket: "FATURA NO"
                }
                TarihSecici {
                    id: faturaTarihi
                    Layout.preferredWidth: 170
                    etiket: "FATURA TARİHİ"
                    onSecildi: (tarih) => faturaTarihi.deger = tarih
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    text: "TUTAR (TL, KDV HARİÇ)  ·  SİPARİŞ: " + SatinalmaBicim.para(root.detay.toplamTutarTL || 0)
                    color: Theme.metinSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
                SayiKutusu {
                    id: faturaTutari
                    Layout.fillWidth: true
                    sifirdaBos: true
                    onDegisti: (yeni) => faturaTutari.deger = yeni
                }
            }

            Label {
                Layout.fillWidth: true
                visible: Math.abs(faturaDialogu.fark) >= 0.01
                text: "Sipariş tutarından " + SatinalmaBicim.para(Math.abs(faturaDialogu.fark))
                      + (faturaDialogu.fark > 0 ? " fazla." : " az.")
                color: faturaDialogu.fark > 0 ? Theme.tehlikeAcik : Theme.uyariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }

            TemaOnayKutusu {
                id: muhasebeKutusu
                text: "Muhasebeye iletildi"
            }

            Label {
                id: faturaHatasi
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
            }
        }
    }
}
