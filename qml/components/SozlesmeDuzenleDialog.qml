import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Teklif PDF'inin son sayfasindaki "Satış Sözleşmesi" maddelerini duzenlemek
// icin acilan pencere ("Satış Sözleşmesi" butonu bunu acar).
//
// Maddeler PDF'te basilacagi haliyle duzenlenir: numarali maddeler, "○" alt
// maddeler, {{DEGISKEN}}'ler doldurulmus ve bu teklife uymayan [KOSUL]'lu
// satirlar (ör. döviz teklifinde [TL] satiri) gizli. Arka planda metin yine
// DUZ METIN olarak saklanir (bkz. TeklifPdfOlusturucu::varsayilanSozlesmeMetni);
// satirlara ayirma ve geri birlestirme Database::sozlesmeSatirlari /
// sozlesmeSatirlarindanMetin'de yapilir, etiketler ve degiskenler korunur.
//
// Pencere metni KENDISI KAYDETMEZ: "Kaydet"e basilinca sadece kaydedildi()
// sinyalini yayinlar, kalici kayit/teklife baglama isini acan ekran yapar
// (bkz. TeklifVerPage.qml).
Dialog {
    id: kok

    // Pencere acilirken gosterilecek metin (teklife kayitli metin veya
    // varsayilan). Acan ekran her acilista bunu doldurur.
    property string metin: ""

    // "Varsayılana Dön" butonunun yazacagi fabrika metni (dile gore degisir).
    property string varsayilanMetin: ""

    // Kabul edilmis / tamamlanmis teklifte sozlesme yalnizca okunur: metin
    // degistirilemez, "Varsayılana Dön" ve "Kaydet" gizlenir.
    property bool saltOkunur: false

    // [KOSUL]/{{DEGISKEN}} isaretlerini PDF'teki gibi doldurmak icin teklifin
    // o anki secimleri (TeklifVerPage.teklifVerisiOlustur()). Acan ekran doldurur.
    property var teklifVerisi: ({})

    // Bu teklife uymadigi icin gizlenen (PDF'e basilmayacak) madde sayisi.
    property int gizliMaddeSayisi: 0

    // Kullanici "Kaydet"e bastiginda, duzenlenmis metinle yayinlanir.
    signal kaydedildi(string yeniMetin)

    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 80 : 820, 820)
    height: Math.min(parent ? parent.height - 60 : 640, 660)
    padding: 20

    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusNormal
        border.color: Theme.kenarlik
        border.width: 1
    }

    // Her acilista maddeler, acan ekranin verdigi metinle bastan doldurulur --
    // onceki oturumdan kalan yarim duzenleme tasinmasin.
    onOpened: {
        modeliDoldur(kok.metin)
        if (!kok.saltOkunur)
            odakla(ilkGorunurSatir(), -1)
    }

    // Her satir: etiketler, hamIcerik, orijinalGorunen, gorunen, alt, gorunur
    // (bkz. Database::sozlesmeSatirlari) + ekran icin numara, altGorunum.
    ListModel { id: satirModeli }

    function bosSatir(alt) {
        return { etiketler: "", hamIcerik: "", orijinalGorunen: "", gorunen: "",
                 alt: alt, gorunur: true, numara: 0, altGorunum: false }
    }

    function modeliDoldur(kaynak) {
        satirModeli.clear()
        const satirlar = database.sozlesmeSatirlari(kaynak, kok.teklifVerisi)
        for (let i = 0; i < satirlar.length; ++i)
            satirModeli.append(Object.assign({ numara: 0, altGorunum: false }, satirlar[i]))
        if (ilkGorunurSatir() < 0)
            satirModeli.append(bosSatir(false))
        numaralariGuncelle()
    }

    // PDF'teki numaralandirmanin aynisi: gizli satirlar sayilmaz, ustunde ana
    // madde olmayan alt madde normal madde gibi numaralanir.
    function numaralariGuncelle() {
        let numara = 0
        let anaMaddeVar = false
        let gizli = 0
        for (let i = 0; i < satirModeli.count; ++i) {
            const s = satirModeli.get(i)
            if (!s.gorunur) {
                ++gizli
                continue
            }
            const altGorunum = s.alt && anaMaddeVar
            if (!altGorunum) {
                ++numara
                anaMaddeVar = true
            }
            satirModeli.setProperty(i, "altGorunum", altGorunum)
            satirModeli.setProperty(i, "numara", altGorunum ? 0 : numara)
        }
        kok.gizliMaddeSayisi = gizli
    }

    function ilkGorunurSatir() {
        for (let i = 0; i < satirModeli.count; ++i)
            if (satirModeli.get(i).gorunur)
                return i
        return -1
    }

    function komsuGorunurSatir(i, yon) {
        for (let j = i + yon; j >= 0 && j < satirModeli.count; j += yon)
            if (satirModeli.get(j).gorunur)
                return j
        return -1
    }

    // konum < 0: metnin sonuna.
    function odakla(i, konum) {
        if (i < 0)
            return
        Qt.callLater(function() {
            const oge = satirTekrarlayici.itemAt(i)
            if (!oge)
                return
            oge.alan.forceActiveFocus()
            oge.alan.cursorPosition = konum < 0 ? oge.alan.length : Math.min(konum, oge.alan.length)
        })
    }

    function satirMetniniAyarla(i, yeniMetin) {
        satirModeli.setProperty(i, "gorunen", yeniMetin)
        const oge = satirTekrarlayici.itemAt(i)
        if (oge && oge.alan.text !== yeniMetin)
            oge.alan.text = yeniMetin
    }

    function altMaddeYap(i, alt) {
        satirModeli.setProperty(i, "alt", alt)
        numaralariGuncelle()
    }

    // Kelime islemcideki madde listesi davranisi:
    //   Enter: yeni madde (imlec ortadaysa madde ikiye bolunur),
    //   Tab / Shift+Tab: alt madde yap / ana madde yap,
    //   Backspace (madde basinda): alt maddeyi ana maddeye cevirir, ana maddeyi
    //   ustteki maddeyle birlestirir (bos madde boylece silinir),
    //   Yukari/Asagi: ilk/son satirdaysa ust/alt maddeye gecer.
    function tusIsle(i, alan, olay) {
        if (kok.saltOkunur)
            return
        const s = satirModeli.get(i)

        if ((olay.key === Qt.Key_Return || olay.key === Qt.Key_Enter)
                && !(olay.modifiers & Qt.ShiftModifier)) {
            olay.accepted = true
            // Bos alt maddede Enter: listeden cikar gibi ana maddeye doner.
            if (alan.length === 0 && s.alt) {
                altMaddeYap(i, false)
                return
            }
            const konum = alan.cursorPosition
            const sonra = alan.text.slice(konum)
            satirMetniniAyarla(i, alan.text.slice(0, konum))
            // Bolunen maddenin ikinci yarisi ayni kosullari ve ham icerigi
            // tasir ki icindeki tarih/para birimi yeniden degiskene cevrilebilsin.
            const yeni = sonra.length > 0
                ? { etiketler: s.etiketler, hamIcerik: s.hamIcerik, orijinalGorunen: "",
                    gorunen: sonra, alt: s.alt, gorunur: true, numara: 0, altGorunum: false }
                : bosSatir(s.alt)
            satirModeli.insert(i + 1, yeni)
            numaralariGuncelle()
            odakla(i + 1, 0)
        } else if (olay.key === Qt.Key_Tab) {
            olay.accepted = true
            altMaddeYap(i, true)
        } else if (olay.key === Qt.Key_Backtab) {
            olay.accepted = true
            altMaddeYap(i, false)
        } else if (olay.key === Qt.Key_Backspace && alan.cursorPosition === 0
                   && alan.selectedText.length === 0) {
            if (s.alt) {
                olay.accepted = true
                altMaddeYap(i, false)
                return
            }
            const onceki = komsuGorunurSatir(i, -1)
            if (onceki < 0)
                return
            olay.accepted = true
            const p = satirModeli.get(onceki)
            const birlesmeKonumu = p.gorunen.length
            const birlesik = p.gorunen + alan.text
            if (alan.length > 0)
                satirModeli.setProperty(onceki, "hamIcerik", p.hamIcerik + " " + s.hamIcerik)
            satirModeli.remove(i)
            satirMetniniAyarla(onceki, birlesik)
            numaralariGuncelle()
            odakla(onceki, birlesmeKonumu)
        } else if (olay.key === Qt.Key_Up && alan.cursorRectangle.y < 2) {
            const onceki = komsuGorunurSatir(i, -1)
            if (onceki >= 0) {
                olay.accepted = true
                odakla(onceki, -1)
            }
        } else if (olay.key === Qt.Key_Down
                   && alan.cursorRectangle.y + alan.cursorRectangle.height > alan.contentHeight - 2) {
            const sonraki = komsuGorunurSatir(i, 1)
            if (sonraki >= 0) {
                olay.accepted = true
                odakla(sonraki, 0)
            }
        }
    }

    function metniTopla() {
        const satirlar = []
        for (let i = 0; i < satirModeli.count; ++i) {
            const s = satirModeli.get(i)
            satirlar.push({ etiketler: s.etiketler, hamIcerik: s.hamIcerik,
                            orijinalGorunen: s.orijinalGorunen, gorunen: s.gorunen,
                            alt: s.alt, gorunur: s.gorunur })
        }
        return database.sozlesmeSatirlarindanMetin(satirlar, kok.teklifVerisi)
    }

    header: RowLayout {
        spacing: 8
        Item { Layout.preferredWidth: 12 }
        Rectangle {
            Layout.topMargin: 18
            Layout.preferredWidth: 4
            Layout.preferredHeight: 16
            radius: 2
            color: Theme.vurgu
        }
        Label {
            Layout.topMargin: 18
            Layout.fillWidth: true
            text: "Satış Sözleşmesi"
            color: Theme.metinBirincil
            font.family: Theme.fontAilesi
            font.bold: true
            font.pixelSize: Theme.fontBoyutOrta
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusKucuk
            color: Theme.arkaplan
            border.width: 1
            border.color: Theme.kenarlik

            ScrollView {
                id: kaydirma
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                contentWidth: availableWidth

                Column {
                    id: satirSutunu
                    width: kaydirma.availableWidth
                    spacing: 6

                    Repeater {
                        id: satirTekrarlayici
                        model: satirModeli

                        delegate: Item {
                            id: satirOgesi
                            required property int index
                            required property string gorunen
                            required property bool gorunur
                            required property bool altGorunum
                            required property int numara
                            property alias alan: satirAlani

                            readonly property int girinti: altGorunum ? 28 : 0

                            width: satirSutunu.width
                            visible: gorunur
                            height: gorunur ? satirAlani.implicitHeight : 0

                            // Madde isareti: PDF'teki gibi "1." veya alt maddede "○".
                            Text {
                                x: satirOgesi.girinti
                                y: satirAlani.topPadding
                                width: 24
                                horizontalAlignment: Text.AlignRight
                                text: satirOgesi.altGorunum ? "○" : satirOgesi.numara + "."
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: satirOgesi.altGorunum ? Theme.fontBoyutKucuk : Theme.fontBoyutNormal
                            }

                            TextArea {
                                id: satirAlani
                                x: satirOgesi.girinti + 32
                                width: parent.width - x
                                text: satirOgesi.gorunen
                                readOnly: kok.saltOkunur
                                background: null
                                leftPadding: 0
                                rightPadding: 0
                                topPadding: 1
                                bottomPadding: 1
                                color: Theme.metinBirincil
                                placeholderText: kok.saltOkunur ? "" : "Madde yazın..."
                                placeholderTextColor: Theme.metinCokSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                wrapMode: TextArea.Wrap
                                selectByMouse: true

                                onTextChanged: {
                                    if (text !== satirOgesi.gorunen)
                                        satirModeli.setProperty(satirOgesi.index, "gorunen", text)
                                }
                                Keys.onPressed: function(olay) {
                                    kok.tusIsle(satirOgesi.index, satirAlani, olay)
                                }
                            }
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !kok.saltOkunur
            wrapMode: Text.WordWrap
            color: Theme.metinSoluk
            font.family: Theme.fontAilesi
            font.pixelSize: Theme.fontBoyutKucuk
            text: "Enter: yeni madde  ·  Tab: alt madde  ·  Shift+Tab: ana madde  ·  Boş maddede Backspace: sil"
                  + (kok.gizliMaddeSayisi > 0
                     ? "\nBu teklifin para birimi / nakliye / KDV seçimine uymayan "
                       + kok.gizliMaddeSayisi + " alternatif madde gizli; seçim değişirse PDF'te onlar çıkar."
                     : "")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 10

            Button {
                id: varsayilanButonu
                visible: !kok.saltOkunur
                Layout.preferredWidth: 150
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Varsayılana Dön"
                // Metni geri almak icin bir sonraki adim yok: kullanici yanlislikla
                // basarsa "İptal" ile pencereyi kapatip degisiklikleri atabilir.
                onClicked: kok.modeliDoldur(kok.varsayilanMetin)
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: varsayilanButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: varsayilanButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    text: varsayilanButonu.text
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                id: iptalButonu
                Layout.preferredWidth: 110
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: kok.saltOkunur ? "Kapat" : "İptal"
                onClicked: kok.close()
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: iptalButonu.hovered ? Theme.panelHover : "transparent"
                    border.width: 1
                    border.color: iptalButonu.hovered ? Theme.metinSoluk : Theme.kenarlik
                }
                contentItem: Text {
                    text: iptalButonu.text
                    color: Theme.metinIkincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                id: kaydetButonu
                visible: !kok.saltOkunur
                Layout.preferredWidth: 150
                Layout.preferredHeight: Theme.girdiYuksekligi
                text: "Sözleşmeyi Kaydet"
                onClicked: {
                    kok.kaydedildi(kok.metniTopla())
                    kok.close()
                }
                background: Rectangle {
                    radius: Theme.radiusKucuk
                    color: kaydetButonu.hovered ? Theme.vurguHover : Theme.vurgu
                }
                contentItem: Text {
                    text: kaydetButonu.text
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
