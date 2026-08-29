import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Teklif Ver ekrani: WPF'teki TeklifVerViewModel + TeklifVer.xaml ikilisinin
// Qt/QML karsiligi. Musteri secimi, urun sepeti, indirim/KDV/paketleme/tasima
// hesabi ve teklifKaydet() ile kaydetme burada. PDF uretimi ve dinamik doviz
// kuru cekme bu ilk surumde STUB -- kur alanlari elle girilir, PDF butonu
// simdilik sadece "yakinda" mesaji gosterir (WPF'teki KaydetVePdfIndirCommand'in
// PDF kismi bir sonraki adimda eklenecek).
Item {
    id: root

    property int kullaniciId: 0

    signal geriDonuldu()

    // Kucuk yardimci bilesenler: dosya icinde birden fazla yerde kullanildigi
    // icin inline "component" olarak (dosyanin en ustunde, root'un dogrudan
    // cocugu olarak) tanimlaniyor -- QML'de inline component'ler boyle, tek
    // seviyeli olarak tanimlanmalidir.
    component UcretAlani: Rectangle {
        property alias metin: girdi.text
        property string birim: "%"
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.girdiYuksekligi
        radius: Theme.radiusKucuk
        color: Theme.arkaplan
        border.width: 1
        border.color: girdi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            TextField {
                id: girdi
                Layout.fillWidth: true
                background: null
                color: Theme.metinBirincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                validator: DoubleValidator { bottom: 0; decimals: 2 }
                verticalAlignment: TextInput.AlignVCenter
            }
            Label { text: parent.parent.birim; color: Theme.metinSoluk; font.pixelSize: Theme.fontBoyutKucuk }
        }
    }

    component Ozet: ColumnLayout {
        property string baslik: ""
        property string deger: ""
        property color renk: Theme.metinBirincil
        spacing: 2
        Label { text: parent.baslik; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
        Label { text: parent.deger; color: parent.renk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutOrta; font.bold: true }
    }

    // --- Musteri secimi ---
    property int secilenMusteriId: 0
    property string secilenFirmaAdi: ""

    // --- Sepet ---
    property var sepet: []

    // --- Doviz kurlari (elle girilir veya "Kuru Güncelle" ile internetten cekilir) ---
    property real usdKur: 0
    property real eurKur: 0
    property bool kurCekiliyor: false
    property string kurMesaji: ""
    property bool kurMesajiHata: false

    function paraBirimiSembol(pb) {
        return pb === "USD" ? "$" : (pb === "EUR" ? "€" : "₺")
    }

    // open.er-api.com'dan USD bazli kurlari ceker: rates.TRY dogrudan USD->TRY,
    // rates.TRY / rates.EUR ise EUR->TRY olarak hesaplanir. Basarisiz olursa
    // (agsizlik, zaman asimi, beklenmeyen yanit) mevcut elle giris alanlari
    // fallback olarak calismaya devam eder -- kullaniciya hata mesaji gosterilir.
    function guncelKuruCek() {
        root.kurCekiliyor = true
        root.kurMesaji = ""
        root.kurMesajiHata = false

        const istek = new XMLHttpRequest()
        istek.timeout = 8000
        istek.onreadystatechange = function() {
            if (istek.readyState !== XMLHttpRequest.DONE)
                return

            root.kurCekiliyor = false

            if (istek.status !== 200) {
                root.kurMesaji = "Kur alınamadı (sunucu hatası). Lütfen elle girin."
                root.kurMesajiHata = true
                return
            }

            try {
                const veri = JSON.parse(istek.responseText)
                const usdTry = veri && veri.rates ? Number(veri.rates.TRY) : NaN
                const eur = veri && veri.rates ? Number(veri.rates.EUR) : NaN

                if (!isFinite(usdTry) || usdTry <= 0 || !isFinite(eur) || eur <= 0) {
                    root.kurMesaji = "Kur verisi okunamadı. Lütfen elle girin."
                    root.kurMesajiHata = true
                    return
                }

                const eurTry = usdTry / eur

                root.usdKur = usdTry
                root.eurKur = eurTry
                usdKurAlani.text = usdTry.toFixed(4)
                eurKurAlani.text = eurTry.toFixed(4)
                root.kurMesaji = "Kurlar güncellendi (open.er-api.com)."
                root.kurMesajiHata = false
            } catch (e) {
                root.kurMesaji = "Kur verisi okunamadı. Lütfen elle girin."
                root.kurMesajiHata = true
            }
        }

        try {
            istek.open("GET", "https://open.er-api.com/v6/latest/USD")
            istek.send()
        } catch (e) {
            root.kurCekiliyor = false
            root.kurMesaji = "Kur alınamadı (bağlantı hatası). Lütfen elle girin."
            root.kurMesajiHata = true
        }
    }

    // TL tutarini secili teklif para birimine cevirir. Kur girilmemisse (0)
    // TL olarak birakir -- yanlislikla 0'a bolme veya anlamsiz deger olmasin.
    function tlDenCevir(tlTutar) {
        if (paraBirimiCombo.currentText === "USD" && root.usdKur > 0)
            return tlTutar / root.usdKur
        if (paraBirimiCombo.currentText === "EUR" && root.eurKur > 0)
            return tlTutar / root.eurKur
        return tlTutar
    }

    // Sepet + form alanlarindan teklifKaydet()/satisSozlesmesiOlustur() icin
    // ortak QVariantMap'i uretir. "Teklifi Kaydet" ve "Satış Sözleşmesi"
    // butonlari AYNI veriyi kullanir; sozlesme butonu teklif henuz
    // kaydedilmemis olsa bile calisabilsin diye musteriAdi'ni de tasir.
    function teklifVerisiOlustur() {
        const kalemler = root.sepet.map(k => ({
            urunId: k.urunId || 0,
            urunKodu: k.urunKodu || "MANUEL",
            aciklama: k.aciklama,
            adet: k.adet,
            birimFiyat: k.birimFiyatTl,
            indirimliBirimFiyat: k.birimFiyatTl * (1 - root.indirimOrani / 100),
            toplamTutar: k.birimFiyatTl * (1 - root.indirimOrani / 100) * k.adet,
            maliyetFiyati: k.maliyet,
            paraBirimi: "TL",
            kur: 1
        }))

        return {
            musteriId: root.secilenMusteriId,
            musteriAdi: root.secilenFirmaAdi,
            kullaniciId: root.kullaniciId,
            genelIndirimOrani: root.indirimOrani,
            kdvOrani: root.kdvOrani,
            paketlemeUcreti: root.paketlemeUcretiTl,
            tasimaUcreti: root.tasimaUcretiTl,
            paraBirimi: paraBirimiCombo.currentText,
            dil: dilCombo.currentText,
            ilgiliKisi: ilgiliKisiAlani.text,
            ilgiliKisiTelefonu: ilgiliKisiTelAlani.text,
            ilgiliKisiEposta: ilgiliKisiEpostaAlani.text,
            teslimatSekli: teslimatSekliAlani.text,
            teslimatYeri: teslimatYeriAlani.text,
            indirimliToplam: root.indirimliToplamTl,
            kdvTutari: root.kdvTutariTl,
            genelToplam: root.genelToplamTl,
            kalemler: kalemler
        }
    }

    function sepeteEkle(kalem) {
        const yeniSepet = root.sepet.slice()
        yeniSepet.push(kalem)
        root.sepet = yeniSepet
    }

    function sepettenCikar(dizinIndex) {
        const yeniSepet = root.sepet.slice()
        yeniSepet.splice(dizinIndex, 1)
        root.sepet = yeniSepet
    }

    // --- Canli hesaplamalar ---
    readonly property real indirimOrani: parseFloat(indirimAlani.text) || 0
    readonly property real kdvOrani: parseFloat(kdvAlani.text) || 0
    readonly property real paketlemeUcretiTl: parseFloat(paketlemeAlani.text) || 0
    readonly property real tasimaUcretiTl: parseFloat(tasimaAlani.text) || 0

    readonly property real toplamMaliyetTl: sepet.reduce((acc, k) => acc + (k.maliyet * k.adet), 0)
    readonly property real indirimsizToplamTl: sepet.reduce((acc, k) => acc + (k.birimFiyatTl * k.adet), 0)
    readonly property real indirimliToplamTl: indirimsizToplamTl * (1 - indirimOrani / 100)
    readonly property real kdvTutariTl: indirimliToplamTl * (kdvOrani / 100)
    readonly property real genelToplamTl: indirimliToplamTl + kdvTutariTl + paketlemeUcretiTl + tasimaUcretiTl
    readonly property real karTutariTl: indirimliToplamTl - toplamMaliyetTl
    readonly property real karOrani: indirimliToplamTl > 0 ? (karTutariTl / indirimliToplamTl * 100) : 0

    function paraFormat(deger) {
        return deger.toLocaleString(Qt.locale("tr_TR"), 'f', 2)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.arkaplan
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Label {
                text: "Teklif Oluştur"
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutBaslik
                font.bold: true
                color: Theme.metinBirincil
            }
            Item { Layout.fillWidth: true }
            Label {
                id: bilgiMesaji
                color: Theme.basariAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
            }
        }

        // ---- Ust bilgi paneli: musteri / ucretler / teslimat / dil-para birimi ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Musteri + ilgili kisi
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.preferredHeight: musteriGrid.implicitHeight + 24
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                GridLayout {
                    id: musteriGrid
                    anchors.fill: parent
                    anchors.margins: 12
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8

                    ColumnLayout {
                        Layout.columnSpan: 2
                        spacing: 4
                        Label { text: "FİRMA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: firmaAramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 6

                                TextField {
                                    id: firmaAramaKutusu
                                    Layout.fillWidth: true
                                    background: null
                                    color: Theme.metinBirincil
                                    placeholderTextColor: Theme.metinCokSoluk
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    placeholderText: root.secilenFirmaAdi.length > 0 ? root.secilenFirmaAdi : "Firma ara veya seç..."
                                    verticalAlignment: TextInput.AlignVCenter
                                    onTextChanged: {
                                        musteriSonuclari.model = database.musteriAra(text, 15)
                                        musteriPopup.open()
                                    }
                                    onFocusChanged: {
                                        if (focus) {
                                            musteriSonuclari.model = database.musteriAra(text, 15)
                                            musteriPopup.open()
                                        }
                                    }
                                }

                                Label {
                                    visible: root.secilenMusteriId > 0
                                    text: "✓ " + root.secilenFirmaAdi
                                    color: Theme.basariAcik
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 220
                                }
                            }

                            Popup {
                                id: musteriPopup
                                y: parent.height + 4
                                width: parent.width
                                padding: 4
                                modal: false
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                                background: Rectangle {
                                    color: Theme.panel
                                    radius: Theme.radiusNormal
                                    border.width: 1
                                    border.color: Theme.kenarlik
                                }

                                contentItem: ListView {
                                    id: musteriSonuclari
                                    implicitHeight: Math.min(240, count * 44)
                                    clip: true
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: musteriSonuclari.width
                                        height: 44
                                        color: musteriSatiriAlani.containsMouse ? Theme.panelHover : "transparent"
                                        radius: Theme.radiusKucuk

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 0
                                            Label {
                                                text: modelData.firmaAdi
                                                color: Theme.metinBirincil
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: Theme.fontBoyutNormal
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: modelData.ilgiliKisi
                                                visible: text.length > 0
                                                color: Theme.metinSoluk
                                                font.family: Theme.fontAilesi
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        MouseArea {
                                            id: musteriSatiriAlani
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.secilenMusteriId = modelData.musteriId
                                                root.secilenFirmaAdi = modelData.firmaAdi
                                                ilgiliKisiAlani.text = modelData.ilgiliKisi
                                                ilgiliKisiTelAlani.text = modelData.ilgiliKisiTelefonu
                                                ilgiliKisiEpostaAlani.text = modelData.firmaEposta
                                                firmaAramaKutusu.text = ""
                                                musteriPopup.close()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: "İLGİLİ KİŞİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: ilgiliKisiAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                            TextField {
                                id: ilgiliKisiAlani
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                background: null
                                color: Theme.metinBirincil
                                placeholderTextColor: Theme.metinCokSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                verticalAlignment: TextInput.AlignVCenter
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: "TELEFON"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: ilgiliKisiTelAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                            TextField {
                                id: ilgiliKisiTelAlani
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                background: null
                                color: Theme.metinBirincil
                                placeholderTextColor: Theme.metinCokSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                verticalAlignment: TextInput.AlignVCenter
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.columnSpan: 2
                        spacing: 4
                        Label { text: "İLGİLİ KİŞİ E-POSTA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: ilgiliKisiEpostaAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                            TextField {
                                id: ilgiliKisiEpostaAlani
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                background: null
                                color: Theme.metinBirincil
                                placeholderTextColor: Theme.metinCokSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                verticalAlignment: TextInput.AlignVCenter
                            }
                        }
                    }
                }
            }

            // Ucretler
            Rectangle {
                Layout.preferredWidth: 300
                Layout.preferredHeight: musteriGrid.implicitHeight + 24
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label { text: "ÜCRETLER"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }

                    GridLayout {
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: 4
                            Label { text: "İndirim"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                            UcretAlani { id: indirimAlaniWrap; metin: "0"; birim: "%" }
                        }
                        ColumnLayout {
                            spacing: 4
                            Label { text: "KDV"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                            UcretAlani { id: kdvAlaniWrap; metin: "20"; birim: "%" }
                        }
                        ColumnLayout {
                            spacing: 4
                            Label { text: "Paketleme"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                            UcretAlani { id: paketlemeAlaniWrap; metin: "0"; birim: "TL" }
                        }
                        ColumnLayout {
                            spacing: 4
                            Label { text: "Taşıma"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk }
                            UcretAlani { id: tasimaAlaniWrap; metin: "0"; birim: "TL" }
                        }
                    }

                    // NOT: yukaridaki UcretAlani bileseninin ic TextField'ina disaridan
                    // dogrudan id ile erisemedigimiz icin (component-local scope), gercek
                    // hesaplama TextField'larini burada ayri, gizli tutuyoruz ve UcretAlani
                    // alanlariyla iki yonlu baglantiliyoruz.
                    TextField { id: indirimAlani; visible: false; text: indirimAlaniWrap.metin }
                    TextField { id: kdvAlani; visible: false; text: kdvAlaniWrap.metin }
                    TextField { id: paketlemeAlani; visible: false; text: paketlemeAlaniWrap.metin }
                    TextField { id: tasimaAlani; visible: false; text: tasimaAlaniWrap.metin }

                    Item { Layout.fillHeight: true }
                }
            }

            // Teslimat
            Rectangle {
                Layout.preferredWidth: 240
                Layout.preferredHeight: musteriGrid.implicitHeight + 24
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    ColumnLayout {
                        spacing: 4
                        Label { text: "TESLİMAT ŞEKLİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: teslimatSekliAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                            TextField {
                                id: teslimatSekliAlani
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                background: null
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                verticalAlignment: TextInput.AlignVCenter
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: "TESLİMAT YERİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: teslimatYeriAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                            TextField {
                                id: teslimatYeriAlani
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                background: null
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                verticalAlignment: TextInput.AlignVCenter
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Dil / Para birimi
            Rectangle {
                Layout.preferredWidth: 150
                Layout.preferredHeight: musteriGrid.implicitHeight + 24
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    ColumnLayout {
                        spacing: 4
                        Label { text: "DİL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            ComboBox {
                                id: dilCombo
                                anchors.fill: parent
                                background: null
                                model: ["TR", "EN"]
                                // Dil degisince urun arama sonuclarini (ve dolayisiyla
                                // aciklamalari) hemen yeniden cek -- kullanici tekrar
                                // yazmak zorunda kalmasin.
                                onCurrentTextChanged: urunListesi.model = database.urunAra(urunAramaKutusu.text, 40, dilCombo.currentText)
                                contentItem: Text {
                                    text: dilCombo.displayText
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 12
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: "PARA BİRİMİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.girdiYuksekligi
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            ComboBox {
                                id: paraBirimiCombo
                                anchors.fill: parent
                                background: null
                                model: ["TL", "USD", "EUR"]
                                // TL disi bir para birimine gecildiginde, kur henuz
                                // girilmemisse (0) otomatik olarak internetten cekmeyi
                                // dene -- kullanicinin ayrica "Kuru Güncelle"ye
                                // basmasini beklemeden. Basarisiz olursa (agsizlik vs.)
                                // guncelKuruCek() zaten hata mesaji gosterip elle giris
                                // alanlarini fallback olarak birakiyor.
                                onCurrentTextChanged: {
                                    if (paraBirimiCombo.currentText === "USD" && root.usdKur <= 0)
                                        root.guncelKuruCek()
                                    else if (paraBirimiCombo.currentText === "EUR" && root.eurKur <= 0)
                                        root.guncelKuruCek()
                                }
                                contentItem: Text {
                                    text: paraBirimiCombo.displayText
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 12
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ---- Urun ara + sepet ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Urun arama
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Label { text: "ÜRÜN ARA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.girdiYuksekligi
                        radius: Theme.radiusKucuk
                        color: Theme.arkaplan
                        border.width: 1
                        border.color: urunAramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                        TextField {
                            id: urunAramaKutusu
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            background: null
                            color: Theme.metinBirincil
                            placeholderTextColor: Theme.metinCokSoluk
                            placeholderText: "Ürün kodu veya açıklaması ara..."
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            verticalAlignment: TextInput.AlignVCenter
                            onTextChanged: urunListesi.model = database.urunAra(text, 40, dilCombo.currentText)
                            Component.onCompleted: urunListesi.model = database.urunAra("", 40, dilCombo.currentText)
                        }
                    }

                    ListView {
                        id: urunListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        reuseItems: false

                        delegate: Rectangle {
                            id: urunSatiri
                            required property var modelData
                            width: ListView.view.width
                            height: 52
                            radius: Theme.radiusKucuk
                            color: urunSatiriAlani.containsMouse ? Theme.panelHover : Theme.arkaplanIkincil
                            border.width: 1
                            border.color: Theme.kenarlik
                            layer.enabled: true

                            MouseArea {
                                id: urunSatiriAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Label {
                                        text: urunSatiri.modelData.urunKodu
                                        color: Theme.metinBirincil
                                        font.family: Theme.fontAilesi
                                        font.bold: true
                                        font.pixelSize: Theme.fontBoyutKucuk
                                    }
                                    Label {
                                        text: urunSatiri.modelData.urunAciklamasi
                                        color: Theme.metinSoluk
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        maximumLineCount: 1
                                    }
                                }

                                Label {
                                    text: root.paraFormat(urunSatiri.modelData.birimFiyat) + " ₺"
                                    color: Theme.vurguAcik
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                }

                                Button {
                                    text: "Seç"
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 30
                                    onClicked: root.sepeteEkle({
                                        urunId: urunSatiri.modelData.urunId,
                                        urunKodu: urunSatiri.modelData.urunKodu,
                                        aciklama: urunSatiri.modelData.urunAciklamasi,
                                        adet: 1,
                                        birimFiyatTl: urunSatiri.modelData.birimFiyat,
                                        maliyet: urunSatiri.modelData.maliyet
                                    })
                                    background: Rectangle {
                                        radius: 5
                                        color: Theme.vurgu
                                    }
                                    contentItem: Text {
                                        text: "Seç"
                                        color: "#ffffff"
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: Theme.fontBoyutKucuk
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Sepet
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "SEPET"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "+ Manuel Ürün Ekle"
                            Layout.preferredHeight: 30
                            onClicked: manuelUrunDialogu.open()
                            background: Rectangle {
                                radius: Theme.radiusKucuk
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.kenarlikVurgu
                            }
                            contentItem: Text {
                                text: "+ Manuel Ürün Ekle"
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.sepet.length > 0
                        Label { text: "AÇIKLAMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; Layout.fillWidth: true }
                        Label { text: "ADET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; Layout.preferredWidth: 50 }
                        Label { text: "BİRİM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; Layout.preferredWidth: 70 }
                        Label { text: "TOPLAM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; Layout.preferredWidth: 80 }
                        Label { text: ""; Layout.preferredWidth: 28 }
                    }

                    ListView {
                        id: sepetListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        reuseItems: false
                        model: root.sepet

                        Label {
                            anchors.centerIn: parent
                            visible: root.sepet.length === 0
                            text: "Sepet boş. Soldan ürün seçerek ekleyin."
                            color: Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                        }

                        delegate: Rectangle {
                            id: sepetSatiri
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            height: 48
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplanIkincil
                            border.width: 1
                            border.color: Theme.kenarlik
                            layer.enabled: true

                            readonly property real birimIndirimli: sepetSatiri.modelData.birimFiyatTl * (1 - root.indirimOrani / 100)
                            readonly property real satirToplamTl: birimIndirimli * sepetSatiri.modelData.adet

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6

                                Label {
                                    text: sepetSatiri.modelData.aciklama
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                SpinBox {
                                    Layout.preferredWidth: 50
                                    from: 1
                                    to: 99999
                                    value: sepetSatiri.modelData.adet
                                    editable: true
                                    onValueModified: {
                                        const yeniSepet = root.sepet.slice()
                                        yeniSepet[sepetSatiri.index].adet = value
                                        root.sepet = yeniSepet
                                    }
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.birimIndirimli)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.metinIkincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 70
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.satirToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.vurguAcik
                                    font.family: Theme.fontAilesi
                                    font.bold: true
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 80
                                }

                                Button {
                                    text: "✕"
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    onClicked: root.sepettenCikar(sepetSatiri.index)
                                    background: Rectangle {
                                        radius: 5
                                        color: "transparent"
                                    }
                                    contentItem: Text {
                                        text: "✕"
                                        color: Theme.tehlikeAcik
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Doviz kurlari + toplamlar + aksiyonlar ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 116
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik
            visible: paraBirimiCombo.currentText !== "TL"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 24

                    ColumnLayout {
                        spacing: 4
                        Label { text: "1 USD KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 34
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            TextField {
                                id: usdKurAlani
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                background: null
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                validator: DoubleValidator { bottom: 0; decimals: 4 }
                                verticalAlignment: TextInput.AlignVCenter
                                onTextChanged: root.usdKur = parseFloat(text) || 0
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: "1 EUR KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                        Rectangle {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 34
                            radius: Theme.radiusKucuk
                            color: Theme.arkaplan
                            border.width: 1
                            border.color: Theme.kenarlik
                            TextField {
                                id: eurKurAlani
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                background: null
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                validator: DoubleValidator { bottom: 0; decimals: 4 }
                                verticalAlignment: TextInput.AlignVCenter
                                onTextChanged: root.eurKur = parseFloat(text) || 0
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Label { text: " "; color: "transparent"; font.pixelSize: 10 }
                        Rectangle {
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 34
                            radius: Theme.radiusKucuk
                            color: kurAlani.containsMouse ? Theme.panelHover : Theme.panelVurgu
                            border.width: 1
                            border.color: Theme.kenarlikVurgu
                            opacity: root.kurCekiliyor ? 0.6 : 1

                            Label {
                                anchors.centerIn: parent
                                text: root.kurCekiliyor ? "Çekiliyor..." : "Kuru Güncelle"
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                font.bold: true
                            }

                            MouseArea {
                                id: kurAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.kurCekiliyor
                                onClicked: root.guncelKuruCek()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                Label {
                    text: root.kurMesaji.length > 0
                          ? root.kurMesaji
                          : "Kuru internetten çekmek için \"Kuru Güncelle\"ye basın, ya da yukarıya elle girin."
                    color: root.kurMesajiHata ? Theme.tehlike : Theme.metinCokSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.italic: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 32

                GridLayout {
                    columns: 3
                    columnSpacing: 32
                    rowSpacing: 6
                    Layout.fillWidth: true

                    Ozet { baslik: "Toplam Maliyet"; deger: root.paraFormat(root.tlDenCevir(root.toplamMaliyetTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Kar Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.karTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText); renk: Theme.basariAcik }
                    Ozet { baslik: "Kar Oranı"; deger: root.paraFormat(root.karOrani) + " %"; renk: Theme.basariAcik }

                    Ozet { baslik: "İndirimli Toplam"; deger: root.paraFormat(root.tlDenCevir(root.indirimliToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "KDV Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.kdvTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Genel Toplam"; deger: root.paraFormat(root.tlDenCevir(root.genelToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText); renk: Theme.vurguAcik }
                }

                ColumnLayout {
                    spacing: 8
                    Button {
                        id: sozlesmeButonu
                        text: "Satış Sözleşmesi"
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 40
                        onClicked: {
                            if (root.secilenMusteriId <= 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Sözleşme oluşturmak için önce bir müşteri seçin."
                                return
                            }
                            if (root.sepet.length === 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Sözleşme oluşturmak için sepette en az bir ürün olmalı."
                                return
                            }

                            bilgiMesaji.color = Theme.basariAcik
                            bilgiMesaji.text = "Satış sözleşmesi hazırlanıyor..."

                            const sonuc = database.satisSozlesmesiOlustur(root.teklifVerisiOlustur())
                            if (sonuc.basarili) {
                                bilgiMesaji.text = "Satış sözleşmesi: " + sonuc.dosyaYolu
                                Qt.openUrlExternally("file:///" + sonuc.dosyaYolu)
                            } else {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Satış sözleşmesi oluşturulamadı: " + sonuc.hata
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusKucuk
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.kenarlik
                        }
                        contentItem: Text {
                            text: "Satış Sözleşmesi"
                            color: Theme.metinBirincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        id: kaydetButonu
                        text: "Teklifi Kaydet"
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 40
                        onClicked: {
                            if (root.secilenMusteriId <= 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Lütfen önce bir müşteri seçin."
                                return
                            }
                            if (root.sepet.length === 0) {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = "Sepette en az bir ürün olmalı."
                                return
                            }

                            const sonuc = database.teklifKaydet(root.teklifVerisiOlustur())
                            if (sonuc.basarili) {
                                bilgiMesaji.color = Theme.basariAcik
                                bilgiMesaji.text = "Teklif #" + sonuc.teklifId + " kaydedildi. PDF hazırlanıyor..."

                                const pdfSonuc = database.teklifPdfOlustur(sonuc.teklifId)
                                if (pdfSonuc.basarili) {
                                    bilgiMesaji.text = "Teklif #" + sonuc.teklifId + " kaydedildi. PDF: " + pdfSonuc.dosyaYolu
                                    Qt.openUrlExternally("file:///" + pdfSonuc.dosyaYolu)
                                } else {
                                    bilgiMesaji.text = "Teklif #" + sonuc.teklifId + " kaydedildi, ancak PDF oluşturulamadı: " + pdfSonuc.hata
                                }

                                root.sepet = []
                                root.secilenMusteriId = 0
                                root.secilenFirmaAdi = ""
                                ilgiliKisiAlani.text = ""
                                ilgiliKisiTelAlani.text = ""
                                ilgiliKisiEpostaAlani.text = ""
                            } else {
                                bilgiMesaji.color = Theme.tehlikeAcik
                                bilgiMesaji.text = sonuc.hata
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusKucuk
                            color: kaydetButonu.hovered ? Theme.vurguHover : Theme.vurgu
                        }
                        contentItem: Text {
                            text: "Teklifi Kaydet"
                            color: "#ffffff"
                            font.family: Theme.fontAilesi
                            font.bold: true
                            font.pixelSize: Theme.fontBoyutKucuk
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // ---- Manuel urun ekleme dialogu ----
    Dialog {
        id: manuelUrunDialogu
        title: "Sepete Manuel Ürün Ekle"
        modal: true
        width: 380
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        onOpened: {
            manuelAciklama.text = ""
            manuelAdet.text = "1"
            manuelFiyat.text = "0"
            manuelMaliyet.text = "0"
        }

        onAccepted: {
            if (manuelAciklama.text.trim().length === 0)
                return
            root.sepeteEkle({
                urunId: 0,
                urunKodu: "MANUEL",
                aciklama: manuelAciklama.text,
                adet: parseInt(manuelAdet.text) || 1,
                birimFiyatTl: parseFloat(manuelFiyat.text) || 0,
                maliyet: parseFloat(manuelMaliyet.text) || 0
            })
        }

        // NOT: alanlara onOpened'da varsayilan metin ("1", "0") yazildigi icin
        // placeholderText hicbir zaman gorunmuyor -- kullanici hangi alanin ne
        // oldugunu anlayamiyordu. Bunun icin her alanin USTUNE, icerikten
        // bagimsiz DAIMA gorunen kucuk bir Label ekliyoruz.
        contentItem: ColumnLayout {
            spacing: 10

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "ÜRÜN AÇIKLAMASI"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                TextField {
                    id: manuelAciklama
                    Layout.fillWidth: true
                    placeholderText: "Örn: Özel kesim conta"
                    color: Theme.metinBirincil
                    placeholderTextColor: Theme.metinCokSoluk
                    background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "ADET"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    TextField {
                        id: manuelAdet
                        Layout.fillWidth: true
                        validator: IntValidator { bottom: 1 }
                        color: Theme.metinBirincil
                        background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
                    }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "BİRİM FİYAT (TL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    TextField {
                        id: manuelFiyat
                        Layout.fillWidth: true
                        validator: DoubleValidator { bottom: 0; decimals: 2 }
                        color: Theme.metinBirincil
                        background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
                    }
                }
            }
            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "MALİYET (TL, OPSİYONEL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                TextField {
                    id: manuelMaliyet
                    Layout.fillWidth: true
                    validator: DoubleValidator { bottom: 0; decimals: 2 }
                    color: Theme.metinBirincil
                    background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
                }
            }
        }
    }
}
