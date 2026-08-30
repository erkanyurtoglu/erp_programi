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
    // Manuel urun ekleme dialogundaki alan stili (bkz. UrunlerimPage.qml'deki
    // ayni amacli FormAlani bileseni).
    component ManuelUrunAlani: TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.girdiYuksekligi + 6
        color: Theme.metinBirincil
        placeholderTextColor: Theme.metinCokSoluk
        font.family: Theme.fontAilesi
        font.pixelSize: Theme.fontBoyutNormal
        leftPadding: 12
        rightPadding: 12
        background: Rectangle { color: Theme.arkaplan; radius: Theme.radiusKucuk; border.width: 1; border.color: Theme.kenarlik }
    }

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
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 2
            TextField {
                id: girdi
                Layout.fillWidth: true
                leftPadding: 0
                rightPadding: 0
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

    // Sepet satirlarindaki elle degistirilebilir Maliyet/Birim Fiyat hucreleri
    // icin kompakt sayisal girdi kutusu.
    component SepetSayiAlani: Rectangle {
        property alias metin: sayiGirdisi.text
        signal degisti(real yeniDeger)
        Layout.preferredWidth: 78
        Layout.preferredHeight: 30
        radius: Theme.radiusKucuk
        color: Theme.arkaplan
        border.width: 1
        border.color: sayiGirdisi.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

        TextField {
            id: sayiGirdisi
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            background: null
            color: Theme.metinBirincil
            font.family: "Consolas"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            verticalAlignment: TextInput.AlignVCenter
            validator: DoubleValidator { bottom: 0; decimals: 2 }
            selectByMouse: true
            onEditingFinished: parent.degisti(parseFloat(text) || 0)
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

    // Kart baslik + ince ayirici cizgi: sol "Teklif Bilgileri" seridindeki
    // mantiksal gruplari (musteri, ticari sartlar, teslimat, dil/para birimi)
    // birbirinden gorsel olarak ayirmak icin kullanilir. Vurgu renginde kucuk
    // bir "bayrak" isaretiyle grubun kimligini one cikarir.
    component BolumBasligi: ColumnLayout {
        property string baslik: ""
        spacing: 10
        Layout.fillWidth: true

        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Rectangle {
                width: 4
                height: 14
                radius: 2
                color: Theme.vurgu
            }
            Label {
                text: parent.parent.baslik
                color: Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.kenarlik
        }
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
    // Kur karti varsayilan olarak kompakt/salt-okunur gorunur; kullanici
    // "Elle düzenle"ye basarsa true olur, "Otomatik görünüme dön" ile geri doner.
    property bool kurElleDuzenleModu: false

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
    // Secili para birimi icin gecerli kur degerini dondurur (TL ise 1).
    function gecerliKur() {
        if (paraBirimiCombo.currentText === "USD") return root.usdKur > 0 ? root.usdKur : 1
        if (paraBirimiCombo.currentText === "EUR") return root.eurKur > 0 ? root.eurKur : 1
        return 1
    }

    // Sepet + form alanlarindan teklifKaydet()/satisSozlesmesiOlustur() icin
    // ortak QVariantMap'i uretir. Tum parasal tutarlar (kalemler ve toplamlar)
    // KAYDEDILECEGI para birimine (paraBirimiCombo) cevrilerek gonderilir --
    // boylece "USD teklif" veritabaninda da gercekten USD tutarlarla, dogru
    // ParaBirimi etiketiyle saklanir; PDF/sozlesme de dogrudan bu degerleri
    // kullanabilir (ayrica cevirmeye gerek kalmaz).
    function teklifVerisiOlustur() {
        const secilenParaBirimi = paraBirimiCombo.currentText
        const kur = root.gecerliKur()

        const kalemler = root.sepet.map(k => {
            const indirimliBirim = k.birimFiyatTl * (1 - root.indirimOrani / 100)
            return {
                urunId: k.urunId || 0,
                urunKodu: k.urunKodu || "MANUEL",
                aciklama: k.aciklama,
                adet: k.adet,
                birimFiyat: root.tlDenCevir(k.birimFiyatTl),
                indirimliBirimFiyat: root.tlDenCevir(indirimliBirim),
                toplamTutar: root.tlDenCevir(indirimliBirim * k.adet),
                maliyetFiyati: root.tlDenCevir(k.maliyet),
                paraBirimi: secilenParaBirimi,
                kur: kur
            }
        })

        return {
            musteriId: root.secilenMusteriId,
            musteriAdi: root.secilenFirmaAdi,
            kullaniciId: root.kullaniciId,
            genelIndirimOrani: root.indirimOrani,
            kdvOrani: root.kdvOrani,
            paketlemeUcreti: root.tlDenCevir(root.paketlemeUcretiTl),
            tasimaUcreti: root.tlDenCevir(root.tasimaUcretiTl),
            paraBirimi: secilenParaBirimi,
            dil: dilCombo.currentText,
            ilgiliKisi: ilgiliKisiAlani.text,
            ilgiliKisiTelefonu: ilgiliKisiTelAlani.text,
            ilgiliKisiEposta: ilgiliKisiEpostaAlani.text,
            teslimatSekli: teslimatSekliAlani.text,
            teslimatYeri: teslimatYeriAlani.text,
            indirimliToplam: root.tlDenCevir(root.indirimliToplamTl),
            kdvTutari: root.tlDenCevir(root.kdvTutariTl),
            genelToplam: root.tlDenCevir(root.genelToplamTl),
            kalemler: kalemler
        }
    }

    function sepeteEkle(kalem) {
        const yeniSepet = root.sepet.slice()
        // Ayni urun zaten sepette varsa yeni bir satir eklemek yerine
        // mevcut satirin adedini artir (manuel eklenen kalemler haric).
        if (kalem.urunKodu !== "MANUEL" && kalem.urunId) {
            const mevcutIndex = yeniSepet.findIndex(k => k.urunId === kalem.urunId)
            if (mevcutIndex !== -1) {
                yeniSepet[mevcutIndex] = Object.assign({}, yeniSepet[mevcutIndex])
                yeniSepet[mevcutIndex].adet += kalem.adet
                root.sepet = yeniSepet
                return
            }
        }
        yeniSepet.push(kalem)
        root.sepet = yeniSepet
    }

    function sepettenCikar(dizinIndex) {
        const yeniSepet = root.sepet.slice()
        yeniSepet.splice(dizinIndex, 1)
        root.sepet = yeniSepet
    }

    // Sepet satirindaki adet/maliyet/birim fiyat elle degistirildiginde cagrilir --
    // alttaki tum ozet hesaplamalari (readonly property'ler) sepet'e bagli oldugu
    // icin bu atama tek basina hepsini yeniden hesaplatir.
    function sepetAlaniGuncelle(dizinIndex, alanAdi, deger) {
        const yeniSepet = root.sepet.slice()
        yeniSepet[dizinIndex] = Object.assign({}, yeniSepet[dizinIndex])
        yeniSepet[dizinIndex][alanAdi] = deger
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

    // Bos alana (herhangi bir kontrole denk gelmeyen bolgeye) tiklaninca
    // aktif odagi (ornegin Firma ara kutusundaki imleci) birakmak icin --
    // QtQuick'te odaklanabilir olmayan bir alana tiklamak varsayilan olarak
    // hicbir seyi odaktan cikarmiyor, bu yuzden acikca root'a odak veriyoruz.
    // Diger kontroller bunun uzerinde durdugu icin onlara tiklamalar buraya
    // gecmeden once kendi MouseArea/TextField'larinca yakalanir.
    MouseArea {
        anchors.fill: parent
        onClicked: root.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Baslik ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Teklif Oluştur"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: "Müşteri, ürün ve şartları belirleyip yeni bir satış teklifi hazırlayın"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                id: bilgiMesajiKutusu
                visible: bilgiMesaji.text.length > 0
                radius: Theme.radiusNormal
                color: bilgiMesaji.color === Theme.tehlikeAcik ? Qt.rgba(0.97, 0.44, 0.44, 0.12) : Qt.rgba(0.29, 0.87, 0.5, 0.12)
                border.width: 1
                border.color: bilgiMesaji.color === Theme.tehlikeAcik ? Theme.tehlikeAcik : Theme.basariAcik
                implicitWidth: bilgiMesaji.implicitWidth + 24
                implicitHeight: bilgiMesaji.implicitHeight + 14
                Label {
                    id: bilgiMesaji
                    anchors.centerIn: parent
                    color: Theme.basariAcik
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    font.bold: true
                }
            }
        }

        // ---- Ust "Teklif Bilgileri" seridi: musteri/ticari sartlar/teslimat/dil-para
        // alanlari artik SOLDA dikey bir kolonda degil, ekranin USTUNDE iki satirlik
        // yatay bir seritte topluca yer aliyor. Boylece hem yukseklik hem genislik
        // olarak ekranin buyuk cogunlugu Urun Ara + Sepet'e ayrilabiliyor.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: ustBilgiSutunu.implicitHeight + 28
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            ColumnLayout {
                id: ustBilgiSutunu
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ---- 4 mantiksal grup, yan yana; her grup kendi icinde 2 satir ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    // --- Grup 1: MUSTERI (firma/ilgili kisi/telefon/eposta) -- genis, esnek ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Firma tek basina, satirin tamamini kaplar -- arama/secim
                            // kutusu en genis alani hak ediyor.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Label { text: "🏢  FİRMA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
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
                                            // Arama artik veritabanina asenkron gidiyor (Database::musteriAraBaslat
                                            // + musteriSonuclariHazir sinyali, ayri thread'de calisir -- bkz.
                                            // AramaWorker) ve her tus basisinda degil, kullanici yazmayi
                                            // kestikten kisa bir sure sonra tetiklenir (debounce). Bu ikisi
                                            // birlikte, once her karakterde UI thread'ini bloke eden senkron
                                            // sorgularin sebep oldugu donma/kasmayi gideriyor.
                                            onTextChanged: {
                                                musteriAramaTimer.restart()
                                                musteriPopup.open()
                                            }
                                            onFocusChanged: {
                                                if (focus) {
                                                    database.musteriAraBaslat(text, 15)
                                                    musteriPopup.open()
                                                }
                                            }

                                            Timer {
                                                id: musteriAramaTimer
                                                interval: 250
                                                onTriggered: database.musteriAraBaslat(firmaAramaKutusu.text, 15)
                                            }

                                            Connections {
                                                target: database
                                                function onMusteriSonuclariHazir(arama, sonuclar) {
                                                    // Kullanici bu sonuc donene kadar yazmaya devam etmis
                                                    // olabilir -- artik guncel olmayan (eskimis) sonucu
                                                    // gormezden gel.
                                                    if (arama === firmaAramaKutusu.text)
                                                        musteriSonuclari.model = sonuclar
                                                }
                                            }
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
                                                        ilgiliKisiAlani.cursorPosition = 0
                                                        ilgiliKisiTelAlani.text = modelData.ilgiliKisiTelefonu
                                                        ilgiliKisiTelAlani.cursorPosition = 0
                                                        ilgiliKisiEpostaAlani.text = modelData.firmaEposta
                                                        ilgiliKisiEpostaAlani.cursorPosition = 0
                                                        firmaAramaKutusu.text = ""
                                                        musteriPopup.close()
                                                        // Odak firma kutusunda kalirsa bir sonraki
                                                        // tiklama onFocusChanged'i tetiklemez (odak
                                                        // zaten true'dur) ve popup acilmaz; odagi
                                                        // birakip bir sonraki tiklamada yeniden
                                                        // acilmasini sagliyoruz.
                                                        firmaAramaKutusu.focus = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                        }

                        // Telefon / Ilgili Kisi / Ilgili Kisi E-posta -- Firma'nin
                        // altinda, ucu esit genislikte 3 kutu.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                Layout.minimumWidth: 150
                                Layout.maximumWidth: 150
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
                                Layout.preferredWidth: 150
                                Layout.minimumWidth: 150
                                Layout.maximumWidth: 150
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
                                Layout.fillWidth: true
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

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 2: TICARI SARTLAR (indirim/kdv/paketleme/tasima) -- kisa degerler, dar ---
                    // NOT: minimumWidth/maximumWidth de sabitlenmezse, ic alanlarin
                    // (TextField/Label) dogal minimum genisligi preferredWidth'i ezip
                    // grubu istenenden cok daha genis gosterebiliyor -- ucu ucuna
                    // sabitlemek genislik farkinin gercekten gorunur olmasini saglar.
                    ColumnLayout {
                        Layout.preferredWidth: 210
                        Layout.minimumWidth: 210
                        Layout.maximumWidth: 210
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "💳  İNDİRİM %"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; elide: Text.ElideRight; Layout.maximumWidth: 100 }
                                UcretAlani { id: indirimAlaniWrap; metin: "0"; birim: "%" }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "KDV %"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                                UcretAlani { id: kdvAlaniWrap; metin: "20"; birim: "%" }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "PAKETLEME"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; elide: Text.ElideRight; Layout.maximumWidth: 100 }
                                UcretAlani { id: paketlemeAlaniWrap; metin: "0"; birim: "TL" }
                            }
                            ColumnLayout {
                                Layout.preferredWidth: 100
                                Layout.minimumWidth: 100
                                Layout.maximumWidth: 100
                                spacing: 4
                                Label { text: "TAŞIMA"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
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
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 3: TESLIMAT (sekli/yeri) -- tek sutun, orta genislik ---
                    ColumnLayout {
                        Layout.preferredWidth: 240
                        Layout.minimumWidth: 240
                        Layout.maximumWidth: 240
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "🚚  TESLİMAT ŞEKLİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
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
                            Layout.fillWidth: true
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
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.leftMargin: 16; Layout.rightMargin: 16; color: Theme.kenarlik }

                    // --- Grup 4: DIL & PARA BIRIMI -- kisa secim kutulari, en dar ---
                    ColumnLayout {
                        Layout.preferredWidth: 150
                        Layout.minimumWidth: 150
                        Layout.maximumWidth: 150
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: "🌐  DİL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
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
                                    onCurrentTextChanged: database.urunAraBaslat(urunAramaKutusu.text, 40, dilCombo.currentText)
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
                            Layout.fillWidth: true
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
                    }
                }
            }
        }

        // ---- Urun ara + sepet: ust serit artik yatayda oldugu icin bu alan
        // ekranin TAM genisligini kullanabiliyor -- Sepet'teki Aciklama sutunu
        // dahil her sutun cok daha rahat nefes alir.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // Urun arama
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 360
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    BolumBasligi { baslik: "🔍  ÜRÜN ARA" }

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
                            // Sayfa acilir acilmaz (Component.onCompleted) ve her tus basisinda
                            // eskiden database.urunAra() DOGRUDAN ve SENKRON cagriliyordu -- SQL
                            // Server'a agdan yapilan bu sorgu bitene kadar tum pencere donuyordu
                            // ("Yanit Vermiyor"). Artik urunAraBaslat() sadece istegi ayri thread'e
                            // (AramaWorker) yolluyor; sonuc asagidaki Connections uzerinden asenkron
                            // geliyor. Yazarken de her karakterde degil, debounce ile tetikleniyor.
                            onTextChanged: urunAramaTimer.restart()
                            Component.onCompleted: database.urunAraBaslat("", 40, dilCombo.currentText)

                            Timer {
                                id: urunAramaTimer
                                interval: 250
                                onTriggered: database.urunAraBaslat(urunAramaKutusu.text, 40, dilCombo.currentText)
                            }

                            Connections {
                                target: database
                                function onUrunSonuclariHazir(arama, dil, sonuclar) {
                                    if (arama === urunAramaKutusu.text && dil === dilCombo.currentText)
                                        urunListesi.model = sonuclar
                                }
                            }
                        }
                    }

                    ListView {
                        id: urunListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
                        reuseItems: false

                        delegate: Rectangle {
                            id: urunSatiri
                            required property var modelData
                            required property int index
                            width: ListView.view.width - 2
                            height: 54
                            radius: Theme.radiusKucuk
                            color: urunSatiriAlani.containsMouse ? Theme.panelHover : (index % 2 === 0 ? Theme.arkaplanIkincil : Theme.panel)
                            border.width: 1
                            border.color: urunSatiriAlani.containsMouse ? Theme.kenarlikVurgu : Theme.kenarlik
                            Behavior on border.color { ColorAnimation { duration: 120 } }
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
                                        Layout.preferredWidth: 0
                                        Layout.minimumWidth: 0
                                        maximumLineCount: 1
                                    }
                                }

                                Label {
                                    text: root.paraFormat(urunSatiri.modelData.birimFiyat) + " ₺"
                                    color: Theme.vurguAcik
                                    font.family: "Consolas"
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    Layout.rightMargin: 8
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
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { width: 4; height: 14; radius: 2; color: Theme.vurgu }
                        Label { text: "🛒  SEPET"; color: Theme.metinIkincil; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1.2; font.bold: true }
                        Label {
                            text: root.sepet.length > 0 ? ("(" + root.sepet.length + ")") : ""
                            color: Theme.metinCokSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        // Eski WPF programindaki gibi kompakt "+" ikon-butonu: buyuk
                        // "+ Manuel Ürün Ekle" butonu yerine az yer kaplayan bir kisayol.
                        Rectangle {
                            id: manuelEkleButonu
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: Theme.radiusKucuk
                            color: manuelEkleAlani.containsMouse ? Theme.panelHover : "transparent"
                            border.width: 1
                            border.color: Theme.kenarlikVurgu

                            Label {
                                anchors.centerIn: parent
                                text: "+"
                                color: Theme.vurguAcik
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutOrta
                                font.bold: true
                            }

                            MouseArea {
                                id: manuelEkleAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: manuelUrunDialogu.open()
                            }

                            ToolTip.visible: manuelEkleAlani.containsMouse
                            ToolTip.text: "Sepete manuel ürün ekle"
                            ToolTip.delay: 400
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.sepet.length > 0
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: "KOD"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 60 }
                            Label { text: "AÇIKLAMA"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0 }
                            Label { text: "ADET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "MALİYET"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "FİYAT"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "İNDİRİMLİ"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 76; horizontalAlignment: Text.AlignRight }
                            Label { text: "TOPLAM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight }
                            Label { text: ""; Layout.preferredWidth: 24 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.kenarlik
                        }
                    }

                    ListView {
                        id: sepetListesi
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 6
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
                            width: ListView.view.width - 2
                            height: 56
                            radius: Theme.radiusKucuk
                            color: satirAlani.containsMouse ? Theme.panelHover : (sepetSatiri.index % 2 === 0 ? Theme.arkaplanIkincil : Theme.panel)
                            border.width: 1
                            border.color: satirAlani.containsMouse ? Theme.kenarlikVurgu : Theme.kenarlik
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            layer.enabled: true

                            readonly property real birimIndirimli: sepetSatiri.modelData.birimFiyatTl * (1 - root.indirimOrani / 100)
                            readonly property real satirToplamTl: birimIndirimli * sepetSatiri.modelData.adet

                            MouseArea {
                                id: satirAlani
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                z: -1
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 60
                                    Layout.preferredHeight: 22
                                    radius: Theme.radiusKucuk
                                    color: Theme.panelVurgu
                                    border.width: 1
                                    border.color: Theme.kenarlik
                                    Label {
                                        anchors.centerIn: parent
                                        text: sepetSatiri.modelData.urunKodu || "MANUEL"
                                        color: Theme.metinIkincil
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                Label {
                                    text: sepetSatiri.modelData.aciklama
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    Layout.minimumWidth: 0
                                }

                                SpinBox {
                                    id: adetSpin
                                    Layout.preferredWidth: 58
                                    Layout.preferredHeight: 30
                                    from: 1
                                    to: 99999
                                    value: sepetSatiri.modelData.adet
                                    editable: true
                                    onValueModified: root.sepetAlaniGuncelle(sepetSatiri.index, "adet", value)

                                    background: Rectangle {
                                        radius: Theme.radiusKucuk
                                        color: Theme.arkaplan
                                        border.width: 1
                                        border.color: adetSpin.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik
                                    }
                                    contentItem: TextInput {
                                        text: adetSpin.textFromValue(adetSpin.value, adetSpin.locale)
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 11
                                        color: Theme.metinBirincil
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        readOnly: !adetSpin.editable
                                        validator: adetSpin.validator
                                        selectByMouse: true
                                    }
                                    up.indicator: Item {}
                                    down.indicator: Item {}
                                }

                                SepetSayiAlani {
                                    Layout.preferredWidth: 72
                                    metin: sepetSatiri.modelData.maliyet.toFixed(2)
                                    onDegisti: (yeniDeger) => root.sepetAlaniGuncelle(sepetSatiri.index, "maliyet", yeniDeger)
                                }

                                SepetSayiAlani {
                                    Layout.preferredWidth: 72
                                    metin: sepetSatiri.modelData.birimFiyatTl.toFixed(2)
                                    onDegisti: (yeniDeger) => root.sepetAlaniGuncelle(sepetSatiri.index, "birimFiyatTl", yeniDeger)
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.birimIndirimli)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.metinIkincil
                                    font.family: "Consolas"
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 76
                                }

                                Label {
                                    text: root.paraFormat(root.tlDenCevir(sepetSatiri.satirToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                                    color: Theme.vurguAcik
                                    font.family: "Consolas"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 82
                                }

                                Rectangle {
                                    id: silButonu
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    radius: Theme.radiusKucuk
                                    color: silAlani.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.15) : "transparent"

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: Theme.tehlikeAcik
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: silAlani
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.sepettenCikar(sepetSatiri.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Doviz kuru bilgi karti ----
        // Varsayilan: kompakt, salt-okunur "USD: .. TL  EUR: .. TL" gosterimi,
        // ekran acilir acilmaz (veya TL disi bir para birimi ilk secildiginde)
        // otomatik cekilir. Kullanici sadece istisnai durumlarda (ozel bir kur
        // girmek istediginde) kalem simgesiyle elle-giris moduna gecebilir.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.kurElleDuzenleModu ? 92 : 52
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik
            visible: paraBirimiCombo.currentText !== "TL"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                // --- Kompakt, salt-okunur gorunum (varsayilan) ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    visible: !root.kurElleDuzenleModu

                    Label {
                        text: root.kurCekiliyor
                              ? "Kur çekiliyor…"
                              : (root.usdKur > 0 || root.eurKur > 0)
                                ? "USD: " + root.paraFormat(root.usdKur) + " ₺" + "      " +
                                  "EUR: " + root.paraFormat(root.eurKur) + " ₺"
                                : "Kur bilgisi yok"
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        font.bold: true
                    }

                    Label {
                        text: root.kurMesaji
                        visible: text.length > 0
                        color: root.kurMesajiHata ? Theme.tehlikeAcik : Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.italic: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                    }

                    Item { Layout.fillWidth: true; visible: root.kurMesaji.length === 0 }

                    Label {
                        text: root.kurCekiliyor ? "Çekiliyor…" : "Kuru Güncelle"
                        color: kurGuncelleAlani.containsMouse ? Theme.vurguHover : Theme.vurguAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: 11
                        font.underline: kurGuncelleAlani.containsMouse
                        MouseArea {
                            id: kurGuncelleAlani
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.kurCekiliyor
                            onClicked: root.guncelKuruCek()
                        }
                    }

                    Label {
                        text: "✎ Elle düzenle"
                        color: kurElleAlani.containsMouse ? Theme.vurguHover : Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 11
                        MouseArea {
                            id: kurElleAlani
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                usdKurAlani.text = root.usdKur > 0 ? root.usdKur.toFixed(4) : ""
                                eurKurAlani.text = root.eurKur > 0 ? root.eurKur.toFixed(4) : ""
                                root.kurElleDuzenleModu = true
                            }
                        }
                    }
                }

                // --- Elle duzenleme modu (istisnai kullanim) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.kurElleDuzenleModu

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            spacing: 2
                            Label { text: "1 USD KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                            Rectangle {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 30
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
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    validator: DoubleValidator { bottom: 0; decimals: 4 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    onTextChanged: root.usdKur = parseFloat(text) || 0
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Label { text: "1 EUR KAÇ TL"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10 }
                            Rectangle {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 30
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
                                    font.pixelSize: Theme.fontBoyutKucuk
                                    validator: DoubleValidator { bottom: 0; decimals: 4 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    onTextChanged: root.eurKur = parseFloat(text) || 0
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: "Otomatik görünüme dön"
                            color: kurKapatAlani.containsMouse ? Theme.vurguHover : Theme.vurguAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignBottom
                            MouseArea {
                                id: kurKapatAlani
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.kurElleDuzenleModu = false
                            }
                        }
                    }

                    Label {
                        text: root.kurMesaji.length > 0
                              ? root.kurMesaji
                              : "Kur elle girildi; toplamlar bu değerlere göre hesaplanacak."
                        color: root.kurMesajiHata ? Theme.tehlike : Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.italic: true
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: Theme.radiusNormal
            color: Theme.panel
            border.width: 1
            border.color: Theme.kenarlik

            RowLayout {
                // Butonlar (butonGrubu) bu RowLayout disinda, parent'a sag
                // kenardan sabit anchor ile yerlestirildigi icin bu grup
                // butonGrubu.left'e kadar uzaniyor -- ozet/genel toplam
                // genisligi degistikce (rakamlar buyudukce) butonlar asla
                // hareket etmiyor, sadece bu grup gerekirse sikisiyor.
                anchors.left: parent.left
                anchors.right: butonGrubu.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 18
                clip: true

                // Ozet metrikleri: tek satirda yan yana, dikey yer kaplamadan.
                RowLayout {
                    spacing: 26
                    Layout.fillWidth: true

                    Ozet { baslik: "Toplam Maliyet"; deger: root.paraFormat(root.tlDenCevir(root.toplamMaliyetTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "Kar Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.karTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText); renk: Theme.basariAcik }
                    Ozet { baslik: "Kar Oranı"; deger: root.paraFormat(root.karOrani) + " %"; renk: Theme.basariAcik }
                    Ozet { baslik: "İndirimli Toplam"; deger: root.paraFormat(root.tlDenCevir(root.indirimliToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                    Ozet { baslik: "KDV Tutarı"; deger: root.paraFormat(root.tlDenCevir(root.kdvTutariTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText) }
                }

                // Genel Toplam: ekrandaki en kritik rakam oldugu icin diger ozet
                // metriklerinden ayri, vurgulu bir kutuda gosterilir -- ama artik
                // etiket+deger yan yana tek satirda, cubugun tam yuksekligine sigacak sekilde.
                Rectangle {
                    // Sabit genislik yerine icerige gore hesaplanan genislik: rakam
                    // buyudukce (ornegin 25.299.019,20 ₺ gibi) kutu tasmadan otomatik genisler.
                    Layout.preferredWidth: genelToplamIcerik.implicitWidth + 32
                    Layout.fillHeight: true
                    radius: Theme.radiusNormal
                    color: Theme.vurguZeminSoluk
                    border.width: 1
                    border.color: Theme.kenarlikVurguSoluk

                    RowLayout {
                        id: genelToplamIcerik
                        anchors.centerIn: parent
                        spacing: 8
                        Label {
                            text: "GENEL TOPLAM"
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 1
                        }
                        Label {
                            text: root.paraFormat(root.tlDenCevir(root.genelToplamTl)) + " " + root.paraBirimiSembol(paraBirimiCombo.currentText)
                            color: Theme.vurguAcik
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutBaslik
                            font.bold: true
                        }
                    }
                }
            }

            // Butonlar: alt alta degil yan yana -- cubuk yuksekligini artirmadan sigsin.
            // Sag kenara sabit anchor ile yerlestirilir; solundaki grup (ozet +
            // genel toplam) genisligi degistikce bu grup asla kaymaz.
            RowLayout {
                id: butonGrubu
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                    Button {
                        id: sozlesmeButonu
                        text: "Satış Sözleşmesi"
                        Layout.preferredWidth: 138
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
                            color: sozlesmeButonu.hovered ? Theme.panelHover : "transparent"
                            border.width: 1
                            border.color: sozlesmeButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
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
                        Layout.preferredWidth: 138
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

    // ---- Manuel urun ekleme dialogu ----
    // WPF'teki manuel urun ekleme penceresiyle ayni bilgi kumesini toplar
    // (kod, kategori, TR/EN aciklama, TL/USD/EUR birim fiyati, yurtici maliyet).
    // USD/EUR alanlari sadece kayit/gorsel amacli tutulur -- sepet hesaplari
    // (bkz. teklifVerisiOlustur) hala tek para biriminde (TL) calisir, WPF'ten
    // gocte alinan karar bu (UrunlerimPage.qml'deki ayni not).
    Dialog {
        id: manuelUrunDialogu
        modal: true
        width: 560
        padding: 20
        anchors.centerIn: parent

        background: Rectangle {
            color: Theme.panel
            radius: Theme.radiusNormal
            border.color: Theme.kenarlik
            border.width: 1
        }

        header: Label {
            text: "Manuel Ürün Ekle"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
            padding: 20
        }

        onOpened: {
            manuelKod.text = ""
            manuelKategori.text = ""
            manuelAciklama.text = ""
            manuelAciklamaEn.text = ""
            manuelFiyat.text = ""
            manuelFiyatUsd.text = ""
            manuelFiyatEur.text = ""
            manuelMaliyet.text = ""
            manuelHataMesaji.text = ""
        }

        function kaydet() {
            if (manuelAciklama.text.trim().length === 0) {
                manuelHataMesaji.text = "Ürün açıklaması zorunludur."
                return
            }
            root.sepeteEkle({
                urunId: 0,
                urunKodu: manuelKod.text.trim().length > 0 ? manuelKod.text.trim() : "MANUEL",
                kategori: manuelKategori.text,
                aciklama: manuelAciklama.text,
                aciklamaEn: manuelAciklamaEn.text,
                adet: 1,
                birimFiyatTl: parseFloat(manuelFiyat.text) || 0,
                birimFiyatUsd: parseFloat(manuelFiyatUsd.text) || 0,
                birimFiyatEur: parseFloat(manuelFiyatEur.text) || 0,
                maliyet: parseFloat(manuelMaliyet.text) || 0
            })
            manuelUrunDialogu.close()
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                id: manuelHataMesaji
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "ÜRÜN KODU"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelKod; placeholderText: "Örn: BTP-500" }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "KATEGORİ"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelKategori; placeholderText: "Örn: Basma-Eğilme Test Cihazları" }
                }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "ÜRÜN AÇIKLAMASI"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelAciklama; placeholderText: "Örn: Otomatik Beton Test Presi" }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "ÜRÜN AÇIKLAMASI (İNGİLİZCE)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelAciklamaEn; placeholderText: "Ex: Automatic Concrete Compression Test Press" }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "BİRİM SATIŞ FİYATI (TL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyat; placeholderText: "0.00"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "DOLAR BİRİM FİYATI (USD)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyatUsd; placeholderText: "0.00"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
                }
                ColumnLayout {
                    spacing: 3
                    Layout.fillWidth: true
                    Label { text: "EURO BİRİM FİYATI (EUR)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                    ManuelUrunAlani { id: manuelFiyatEur; placeholderText: "0.00"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
                }
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true
                Label { text: "YURTİÇİ MALİYET BİRİM FİYATI (TL)"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1 }
                ManuelUrunAlani { id: manuelMaliyet; placeholderText: "0.00"; validator: DoubleValidator { bottom: 0; decimals: 2 } }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 6
                    text: "Kaydet"
                    onClicked: manuelUrunDialogu.kaydet()
                    background: Rectangle {
                        radius: Theme.radiusKucuk
                        color: parent.hovered ? Theme.vurguHover : Theme.vurgu
                    }
                    contentItem: Text {
                        text: "Kaydet"
                        color: "#ffffff"
                        font.family: Theme.fontAilesi
                        font.bold: true
                        font.pixelSize: Theme.fontBoyutKucuk
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 6
                    text: "İptal"
                    onClicked: manuelUrunDialogu.close()
                    background: Rectangle {
                        radius: Theme.radiusKucuk
                        color: parent.hovered ? Theme.tehlikeHover : Theme.tehlike
                    }
                    contentItem: Text {
                        text: "İptal"
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
