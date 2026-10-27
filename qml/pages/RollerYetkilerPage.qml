import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

// Yonetim / Roller ve Yetkiler: solda rol listesi, sagda secili rolun adi,
// modul bazinda Görebilir / Düzenleyebilir yetkileri ve role atanmis personel.
//
// Sistem rolleri ("Yönetici", "Göç - Geçici Tam Yetkili") yonetici
// korumalarinin dayanagi oldugu icin salt okunurdur (bkz. sistemRoluMu).
// Kaydetme ve silme yonetici sifresiyle onaylanir (Personellerim ile ayni
// gerekce); asil denetim sunucudadir (Database::rolKaydet / rolSil).
Item {
    id: root

    // YONETIM modulunde duzenleme yetkisi yoksa ekran salt okunur acilir.
    property bool duzenleyebilir: true
    property bool otomatikYukle: true

    property var moduller: []
    property var roller: []
    property bool yukleniyor: false
    property string listeHatasi: ""

    // Duzenlenen rolun kopyasi: {rolId (0 = yeni), rolAdi, sistemRolu,
    // toplamKisi, aktifPersonel, yetkiler: {"<modulId>": {gorebilir, duzenleyebilir}}}
    property var secili: null
    property string acilisAnlikGoruntusu: ""
    // Liste yenilendiginde secilecek rol (kayit/silme sonrasi).
    property int secilecekRolId: 0

    readonly property bool yeniRol: root.secili !== null && root.secili.rolId === 0
    readonly property bool saltOkunur: !root.duzenleyebilir
                                       || (root.secili !== null && root.secili.sistemRolu === true)
    readonly property bool degisti: root.secili !== null
                                    && JSON.stringify(root.formAnlikGoruntusu()) !== root.acilisAnlikGoruntusu

    function sayfayiYukle() {
        islemHatasi.text = ""
        root.listeHatasi = ""
        root.yukleniyor = true
        database.rolYetkiListesiGetirBaslat()
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onRolYetkiListesiHazir(sonuc) {
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            if (!sonuc || sonuc.roller === undefined) {
                root.listeHatasi = "Roller yüklenemedi: veritabanına bağlanılamadı."
                return
            }

            root.moduller = sonuc.moduller
            root.roller = sonuc.roller

            // Yeni rol taslagi acikken liste yenilenirse taslak korunur.
            if (root.yeniRol && root.secilecekRolId === 0)
                return

            const hedefId = root.secilecekRolId > 0 ? root.secilecekRolId
                          : (root.secili ? root.secili.rolId : 0)
            root.secilecekRolId = 0
            const hedef = root.roller.find(r => r.rolId === hedefId)
            root.rolSec(hedef || (root.roller.length > 0 ? root.roller[0] : null))
        }
    }

    Component.onCompleted: if (otomatikYukle) sayfayiYukle()

    Timer {
        id: zamanAsimiZamanlayici
        interval: 25000
        onTriggered: {
            if (!root.yukleniyor)
                return
            root.yukleniyor = false
            root.listeHatasi = "Roller sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    function rolSec(rol) {
        formHatasi.text = ""
        if (!rol) {
            root.secili = null
            root.acilisAnlikGoruntusu = ""
            return
        }
        const yetkiler = {}
        for (const m of root.moduller) {
            const y = rol.yetkiler ? rol.yetkiler[String(m.modulId)] : undefined
            yetkiler[String(m.modulId)] = {
                gorebilir: y ? y.gorebilir === true : false,
                duzenleyebilir: y ? y.duzenleyebilir === true : false
            }
        }
        root.secili = {
            rolId: rol.rolId,
            rolAdi: rol.rolAdi,
            sistemRolu: rol.sistemRolu === true,
            toplamKisi: rol.toplamKisi || 0,
            aktifPersonel: rol.aktifPersonel || [],
            yetkiler: yetkiler
        }
        rolAdiAlani.text = rol.rolAdi
        root.acilisAnlikGoruntusu = JSON.stringify(root.formAnlikGoruntusu())
    }

    // Kaydedilmemis degisiklik varsa once onay ister.
    function gecisYap(yapilacak) {
        if (!root.degisti) {
            yapilacak()
            return
        }
        onayDialogu.iste("Kaydedilmemiş Değişiklikler",
                         "Bu roldeki değişiklikler kaydedilmedi. Vazgeçilsin mi?",
                         "Vazgeç", true, yapilacak)
    }

    function yeniRolAc() {
        root.rolSec({ rolId: 0, rolAdi: "", sistemRolu: false, toplamKisi: 0,
                      aktifPersonel: [], yetkiler: {} })
        rolAdiAlani.alan.forceActiveFocus()
    }

    function formAnlikGoruntusu() {
        if (!root.secili)
            return null
        return { rolAdi: rolAdiAlani.text.trim(), yetkiler: root.secili.yetkiler }
    }

    // Duzenleme gorme yetkisini gerektirir; gorme kaldirilirsa duzenleme de gider.
    function yetkiDegistir(modulId, alanAdi, deger) {
        const kopya = Object.assign({}, root.secili)
        const yetkiler = Object.assign({}, kopya.yetkiler)
        const y = Object.assign({}, yetkiler[String(modulId)])
        y[alanAdi] = deger
        if (alanAdi === "duzenleyebilir" && deger)
            y.gorebilir = true
        if (alanAdi === "gorebilir" && !deger)
            y.duzenleyebilir = false
        yetkiler[String(modulId)] = y
        kopya.yetkiler = yetkiler
        root.secili = kopya
    }

    function kaydet() {
        const yetkiListesi = root.moduller.map(m => ({
            modulId: m.modulId,
            gorebilir: root.secili.yetkiler[String(m.modulId)].gorebilir,
            duzenleyebilir: root.secili.yetkiler[String(m.modulId)].duzenleyebilir
        }))
        const sonuc = database.rolKaydet(root.secili.rolId,
                                         { rolAdi: rolAdiAlani.text.trim(), yetkiler: yetkiListesi })
        if (!sonuc.basarili) {
            formHatasi.text = sonuc.hata
            return
        }
        formHatasi.text = ""
        root.secilecekRolId = sonuc.rolId
        root.acilisAnlikGoruntusu = JSON.stringify(root.formAnlikGoruntusu())
        root.sayfayiYukle()
        // Personellerim'deki rol secim listesi de yenilensin.
        database.rolListesiGetirBaslat()
    }

    function sil() {
        const sonuc = database.rolSil(root.secili.rolId)
        if (!sonuc.basarili) {
            formHatasi.text = sonuc.hata
            return
        }
        root.secili = null
        root.acilisAnlikGoruntusu = ""
        root.sayfayiYukle()
        database.rolListesiGetirBaslat()
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

            ColumnLayout {
                spacing: 2
                Label {
                    text: "Roller ve Yetkiler"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.roller.length + " rol"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                id: islemHatasi
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                visible: text.length > 0
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 360
            }

            TemaButon {
                text: "+ Rol Ekle"
                tur: "birincil"
                visible: root.duzenleyebilir
                enabled: !root.yeniRol
                onClicked: root.gecisYap(function() { root.yeniRolAc() })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // ---- Sol: rol listesi ----
            Item {
                Layout.preferredWidth: 300
                Layout.fillHeight: true

                ListView {
                    id: rolListesiGorunumu
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: root.roller

                    delegate: Rectangle {
                        id: kart
                        required property var modelData
                        readonly property bool seciliMi: root.secili !== null
                                                         && root.secili.rolId === kart.modelData.rolId

                        width: ListView.view.width
                        height: 58
                        radius: Theme.radiusKucuk
                        color: kart.seciliMi ? Theme.panelVurgu
                             : (kartAlani.containsMouse ? Theme.panelHover : Theme.panel)
                        border.width: 1
                        border.color: kart.seciliMi ? Theme.kenarlikVurgu : Theme.kenarlik

                        MouseArea {
                            id: kartAlani
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (kart.seciliMi)
                                    return
                                const rol = kart.modelData
                                root.gecisYap(function() { root.rolSec(rol) })
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                KisalanMetin {
                                    Layout.fillWidth: true
                                    text: kart.modelData.rolAdi
                                    color: Theme.metinBirincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutNormal
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: kart.modelData.sistemRolu
                                    Layout.preferredWidth: sistemYazisi.implicitWidth + 12
                                    Layout.preferredHeight: 18
                                    radius: 4
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Theme.kenarlikVurguSoluk
                                    Text {
                                        id: sistemYazisi
                                        anchors.centerIn: parent
                                        text: "sistem"
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 9
                                        color: Theme.metinSoluk
                                    }
                                }
                            }
                            Label {
                                text: kart.modelData.toplamKisi > 0
                                      ? kart.modelData.toplamKisi + " personel" : "Atanmış personel yok"
                                color: Theme.metinSoluk
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutKucuk
                            }
                        }
                    }
                }

                ListeDurumu {
                    anchors.fill: parent
                    yukleniyor: root.yukleniyor
                    hata: root.listeHatasi
                    kayitSayisi: root.roller.length
                    bosMetin: "Henüz rol tanımlanmamış."
                }
            }

            // ---- Sag: secili rolun detayi ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusNormal
                color: Theme.panel
                border.width: 1
                border.color: Theme.kenarlik

                Label {
                    anchors.centerIn: parent
                    visible: root.secili === null && !root.yukleniyor && root.listeHatasi.length === 0
                    text: "Soldan bir rol seçin."
                    color: Theme.metinSoluk
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14
                    visible: root.secili !== null

                    Label {
                        text: root.yeniRol ? "Yeni Rol" : (root.secili ? root.secili.rolAdi : "")
                        color: Theme.metinBirincil
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutOrta
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Label {
                        visible: root.secili !== null && root.secili.sistemRolu === true
                        text: "Sistem rolü; adı ve yetkileri değiştirilemez."
                        color: Theme.uyariAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                    }

                    EtiketliAlan {
                        id: rolAdiAlani
                        etiket: "ROL ADI *"
                        enabled: !root.saltOkunur
                        Layout.maximumWidth: 420
                        Component.onCompleted: rolAdiAlani.alan.maximumLength = 50
                    }

                    Label {
                        text: "MODÜL YETKİLERİ"
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        Layout.topMargin: 4
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 560
                        Layout.preferredHeight: yetkiSutunu.implicitHeight
                        radius: Theme.radiusKucuk
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.kenarlik

                        ColumnLayout {
                            id: yetkiSutunu
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                color: Theme.arkaplanIkincil
                                radius: Theme.radiusKucuk

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    Label { text: "MODÜL"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                                    Label { text: "GÖREBİLİR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 120 }
                                    Label { text: "DÜZENLEYEBİLİR"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 120 }
                                }
                            }

                            Repeater {
                                model: root.moduller

                                delegate: Rectangle {
                                    id: modulSatiri
                                    required property var modelData
                                    required property int index
                                    readonly property var yetki: root.secili
                                        ? root.secili.yetkiler[String(modulSatiri.modelData.modulId)]
                                        : null

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    color: "transparent"

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 1
                                        color: Theme.kenarlik
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14

                                        Label {
                                            text: modulSatiri.modelData.modulAdi
                                            color: Theme.metinBirincil
                                            font.family: Theme.fontAilesi
                                            font.pixelSize: Theme.fontBoyutNormal
                                            Layout.fillWidth: true
                                        }
                                        Item {
                                            Layout.preferredWidth: 120
                                            Layout.fillHeight: true
                                            TemaOnayKutusu {
                                                anchors.verticalCenter: parent.verticalCenter
                                                enabled: !root.saltOkunur
                                                checked: modulSatiri.yetki ? modulSatiri.yetki.gorebilir : false
                                                onToggled: root.yetkiDegistir(modulSatiri.modelData.modulId,
                                                                              "gorebilir", checked)
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: 120
                                            Layout.fillHeight: true
                                            TemaOnayKutusu {
                                                anchors.verticalCenter: parent.verticalCenter
                                                enabled: !root.saltOkunur
                                                checked: modulSatiri.yetki ? modulSatiri.yetki.duzenleyebilir : false
                                                onToggled: root.yetkiDegistir(modulSatiri.modelData.modulId,
                                                                              "duzenleyebilir", checked)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        visible: !root.yeniRol
                        text: "PERSONEL"
                        color: Theme.metinSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        Layout.topMargin: 4
                    }

                    Flow {
                        visible: !root.yeniRol
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.secili ? root.secili.aktifPersonel : []
                            delegate: Rectangle {
                                id: personelCipi
                                required property string modelData
                                width: personelYazisi.implicitWidth + 20
                                height: 26
                                radius: 13
                                color: Theme.panelYukseltilmis
                                border.width: 1
                                border.color: Theme.kenarlik
                                Text {
                                    id: personelYazisi
                                    anchors.centerIn: parent
                                    text: personelCipi.modelData
                                    color: Theme.metinIkincil
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: Theme.fontBoyutKucuk
                                }
                            }
                        }

                        Label {
                            readonly property int pasifSayisi: root.secili
                                ? root.secili.toplamKisi - root.secili.aktifPersonel.length : 0
                            visible: root.secili !== null && (pasifSayisi > 0 || root.secili.toplamKisi === 0)
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                            text: root.secili && root.secili.toplamKisi === 0
                                  ? "Bu role atanmış personel yok."
                                  : "+" + pasifSayisi + " pasif"
                            color: Theme.metinSoluk
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutKucuk
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Label {
                        id: formHatasi
                        visible: text.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Theme.tehlikeAcik
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutKucuk
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.duzenleyebilir
                        spacing: 8

                        Item {
                            // Silme yalnizca kimseye atanmamis, "Yönetici" disindaki
                            // rollerde mumkun; neden kapali oldugu ipucunda yazar.
                            visible: !root.yeniRol && root.secili !== null
                                     && root.secili.rolAdi !== "Yönetici"
                            Layout.preferredWidth: silButonu.implicitWidth
                            Layout.preferredHeight: silButonu.implicitHeight

                            TemaButon {
                                id: silButonu
                                anchors.fill: parent
                                text: "Rolü Sil"
                                tur: "tehlike"
                                enabled: root.secili !== null && root.secili.toplamKisi === 0 && !root.degisti
                                onClicked: {
                                    const ad = root.secili.rolAdi
                                    sifreDialogu.iste("Rolü Sil", "\"" + ad + "\" rolü kalıcı olarak silinsin mi?",
                                                      "Sil", true, function() { root.sil() })
                                }
                            }
                            MouseArea {
                                id: silIpucuAlani
                                anchors.fill: parent
                                visible: !silButonu.enabled
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                ToolTip.visible: silIpucuAlani.containsMouse
                                ToolTip.text: root.degisti
                                              ? "Önce değişiklikleri kaydedin veya vazgeçin."
                                              : "Personele atanmış rol silinemez."
                            }
                        }

                        Item { Layout.fillWidth: true }

                        TemaButon {
                            text: "Vazgeç"
                            visible: !root.saltOkunur && (root.degisti || root.yeniRol)
                            onClicked: {
                                if (root.yeniRol) {
                                    const ilk = root.roller.length > 0 ? root.roller[0] : null
                                    root.rolSec(ilk)
                                } else {
                                    const id = root.secili.rolId
                                    root.rolSec(root.roller.find(r => r.rolId === id) || null)
                                }
                            }
                        }

                        TemaButon {
                            text: root.yeniRol ? "Rolü Oluştur" : "Kaydet"
                            tur: "birincil"
                            visible: !root.saltOkunur
                            enabled: root.degisti || root.yeniRol
                            onClicked: {
                                formHatasi.text = ""
                                if (rolAdiAlani.text.trim().length === 0) {
                                    formHatasi.text = "Rol adı boş olamaz."
                                    return
                                }
                                sifreDialogu.iste(root.yeniRol ? "Rolü Oluştur" : "Rolü Kaydet", "",
                                                  "Kaydet", false, function() { root.kaydet() })
                            }
                        }
                    }
                }
            }
        }
    }

    SifreOnayDialog { id: sifreDialogu }
    OnayDialog { id: onayDialogu }
}
