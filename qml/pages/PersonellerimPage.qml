import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi

Item {
    id: root

    readonly property int sayfaBoyutu: 50

    property var sayfaSonucu: ({ kayitlar: [], toplamKayit: 0, toplamSayfa: 1, mevcutSayfa: 1 })
    property var kayitlarListesi: []
    property string aramaMetni: ""
    property var rolListesi: []

    property int aktifKullaniciId: 0

    // Varsayilan: yalnizca aktifler; pasifler kutu isaretlenince gosterilir.
    property bool pasifGoster: false

    property int bekleyenIstek: 0
    property bool yukleniyor: false
    property string listeHatasi: ""

    property bool otomatikYukle: true

    // Yonetim modulunde duzenleme yetkisi (bkz. YonetimModuluPage.yonetimDuzenleyebilir).
    // Yoksa liste ve Detay salt goruntulemedir; sunucu da yazmayi reddeder.
    property bool duzenleyebilir: true

    function sayfayiYukle(sayfaNo) {
        islemHatasi.text = ""
        root.listeHatasi = ""

        if (root.rolListesi.length === 0)
            database.rolListesiGetirBaslat()

        root.yukleniyor = true
        root.bekleyenIstek = database.personelListesiGetirBaslat(
            root.aramaMetni, sayfaNo, root.sayfaBoyutu, root.pasifGoster)
        zamanAsimiZamanlayici.restart()
    }

    Connections {
        target: database
        function onRolListesiHazir(roller) {
            root.rolListesi = roller
        }

        function onPersonelListesiHazir(istekNo, sonuc) {
            if (istekNo !== root.bekleyenIstek)
                return
            zamanAsimiZamanlayici.stop()
            root.yukleniyor = false

            if (!sonuc || sonuc.toplamSayfa === undefined) {
                root.listeHatasi = "Personel listesi yüklenemedi: veritabanına bağlanılamadı."
                root.kayitlarListesi = []
                return
            }

            root.sayfaSonucu = sonuc
            root.kayitlarListesi = sonuc.kayitlar
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
            root.listeHatasi = "Personel listesi sunucudan yanıt alınamadığı için yüklenemedi. "
                               + "Sunucu yoğun veya erişilemiyor olabilir; tekrar deneyin."
        }
    }

    Timer {
        id: aramaZamanlayici
        interval: 350
        onTriggered: root.sayfayiYukle(1)
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
                    text: "Personellerim"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.bold: true
                    color: Theme.metinBirincil
                }
                Label {
                    text: root.sayfaSonucu.toplamKayit + " kayıt"
                           + (root.pasifGoster ? "" : " (yalnızca aktifler)")
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

            TemaOnayKutusu {
                text: "Pasifleri göster"
                checked: root.pasifGoster
                onToggled: {
                    root.pasifGoster = checked
                    root.sayfayiYukle(1)
                }
            }

            Button {
                id: ekleButonu
                text: "+ Personel Ekle"
                visible: root.duzenleyebilir
                Layout.preferredHeight: 38
                onClicked: duzenlemeDialogu.formuAc(null)
                background: Rectangle { radius: Theme.radiusKucuk; color: ekleButonu.hovered ? Theme.vurguHover : Theme.vurgu }
                contentItem: Text {
                    text: ekleButonu.text
                    color: "#ffffff"
                    font.family: Theme.fontAilesi
                    font.bold: true
                    font.pixelSize: Theme.fontBoyutKucuk
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 14
                    rightPadding: 14
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.girdiYuksekligi
            radius: Theme.radiusKucuk
            color: Theme.panel
            border.width: 1
            border.color: aramaKutusu.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

            TextField {
                id: aramaKutusu
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                background: null
                color: Theme.metinBirincil
                placeholderTextColor: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
                placeholderText: "Ad soyad, kullanıcı adı, pozisyon veya telefon ara..."
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: {
                    root.aramaMetni = text
                    aramaZamanlayici.restart()
                }
            }
        }

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

                Label { text: "AD SOYAD"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 180 }
                Label { text: "KULLANICI ADI"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 140 }
                Label { text: "ROLLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.fillWidth: true }
                Label { text: "DURUM"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 80 }
                Label { text: "İŞLEMLER"; color: Theme.metinCokSoluk; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; font.letterSpacing: 1; Layout.preferredWidth: 150 }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: personelListesi
                anchors.fill: parent
                clip: true
                spacing: 4
                model: root.kayitlarListesi

                delegate: Rectangle {
                    id: satir
                    required property int index
                    required property var modelData

                    readonly property bool kendisiMi: satir.modelData.kullaniciId === root.aktifKullaniciId

                    width: ListView.view.width
                    height: 48
                    radius: Theme.radiusKucuk
                    color: satirAlani.containsMouse ? Theme.panelHover : Theme.panel
                    border.width: 1
                    border.color: Theme.kenarlik
                    opacity: satir.modelData.aktifMi ? 1.0 : 0.55

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

                        RowLayout {
                            // Layout turevlerinde Layout.fillWidth ORTUK olarak
                            // true'dur; kapatilmazsa preferredWidth taban deger olur
                            // ve sutun artan genisligi yutup sagindakileri ezer.
                            Layout.fillWidth: false
                            Layout.preferredWidth: 180
                            Layout.fillHeight: true
                            spacing: 6
                            KisalanMetin {
                                text: satir.modelData.adSoyad
                                color: Theme.metinBirincil
                                font.family: Theme.fontAilesi
                                font.bold: true
                                font.pixelSize: Theme.fontBoyutNormal
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                Layout.fillHeight: true
                                verticalAlignment: Text.AlignVCenter
                            }

                            Rectangle {
                                visible: satir.kendisiMi
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 18
                                radius: 4
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.kenarlikVurgu
                                Text {
                                    anchors.centerIn: parent
                                    text: "siz"
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 9
                                    color: Theme.vurguAcik
                                }
                            }
                        }
                        KisalanMetin {
                            text: satir.modelData.kullaniciAdi
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: Theme.fontBoyutNormal
                            Layout.preferredWidth: 140
                            elide: Text.ElideRight
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        KisalanMetin {
                            text: satir.modelData.rolAdlari
                            color: Theme.metinIkincil
                            font.family: Theme.fontAilesi
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            elide: Text.ElideRight
                            Layout.fillHeight: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        Item {
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 24

                            Rectangle {
                                width: 70
                                height: 24
                                radius: 5
                                color: satir.modelData.aktifMi ? Theme.basariZemin : Theme.kenarlik
                                border.width: 1
                                border.color: satir.modelData.aktifMi ? Theme.basari : Theme.kenarlik
                                Text {
                                    anchors.centerIn: parent
                                    text: satir.modelData.aktifMi ? "Aktif" : "Pasif"
                                    font.family: Theme.fontAilesi
                                    font.pixelSize: 10
                                    color: satir.modelData.aktifMi ? Theme.basariAcik : Theme.metinSoluk
                                }
                            }
                        }

                        RowLayout {
                            // Ortuk fillWidth kapatiliyor (bkz. ad soyad sutunu).
                            Layout.fillWidth: false
                            Layout.preferredWidth: 150
                            spacing: 6

                            Button {
                                id: detayButonu
                                text: "Detay"
                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 28
                                onClicked: duzenlemeDialogu.formuAc(satir.modelData)
                                background: Rectangle { radius: 5; color: detayButonu.hovered ? Theme.panelHover : "transparent"; border.width: 1; border.color: Theme.kenarlikVurgu }
                                contentItem: Text { text: "Detay"; color: Theme.vurguAcik; font.family: Theme.fontAilesi; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }


                            Item {
                                visible: root.duzenleyebilir
                                Layout.preferredWidth: 78
                                Layout.preferredHeight: 28

                                Button {
                                    id: durumButonu
                                    anchors.fill: parent
                                    text: satir.modelData.aktifMi ? "Pasife Al" : "Aktif Et"

                                    enabled: !(satir.kendisiMi && satir.modelData.aktifMi)
                                    onClicked: {
                                        const kullaniciId = satir.modelData.kullaniciId
                                        const yeniAktif = !satir.modelData.aktifMi
                                        sifreDialogu.iste(yeniAktif ? "Personeli Aktif Et" : "Personeli Pasife Al",
                                                          "\"" + satir.modelData.adSoyad + "\" "
                                                          + (yeniAktif ? "aktif edilsin mi?"
                                                                       : "pasife alınsın mı? Giriş yapamaz hale gelir, "
                                                                         + "geçmiş teklifleri olduğu gibi kalır."),
                                                          yeniAktif ? "Aktif Et" : "Pasife Al", !yeniAktif,
                                                          function() { root.aktifDurumDegistir(kullaniciId, yeniAktif) })
                                    }
                                    background: Rectangle {
                                        radius: 5
                                        color: "transparent"
                                        border.width: 1
                                        border.color: satir.modelData.aktifMi ? Theme.tehlike : Theme.basari
                                        opacity: durumButonu.enabled ? 1.0 : 0.4
                                    }
                                    contentItem: Text {
                                        text: durumButonu.text
                                        color: satir.modelData.aktifMi ? Theme.tehlikeAcik : Theme.basariAcik
                                        font.family: Theme.fontAilesi
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        opacity: durumButonu.enabled ? 1.0 : 0.4
                                    }
                                }


                                MouseArea {
                                    id: durumAlani
                                    anchors.fill: parent
                                    visible: !durumButonu.enabled
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    ToolTip.visible: durumAlani.containsMouse
                                    ToolTip.text: "Kendi hesabınızı pasife alamazsınız."
                                }
                            }
                        }
                    }
                }
            }

            ListeDurumu {
                anchors.fill: parent
                yukleniyor: root.yukleniyor
                hata: root.listeHatasi
                kayitSayisi: root.kayitlarListesi.length
                aramaVar: root.aramaMetni.trim().length > 0
                bosMetin: "Henüz personel eklenmemiş. \"+ Personel Ekle\" ile başlayabilirsiniz."
                aramaBosMetni: "Aramanıza uygun personel bulunamadı."
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Button {
                id: oncekiButonu
                text: "◀ Önceki"
                enabled: root.sayfaSonucu.mevcutSayfa > 1 && !root.yukleniyor
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa - 1)
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.panel; border.width: 1; border.color: Theme.kenarlik; opacity: oncekiButonu.enabled ? 1.0 : 0.4 }
                contentItem: Text { text: oncekiButonu.text; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: oncekiButonu.enabled ? 1.0 : 0.4 }
            }

            Label {
                text: "Sayfa " + root.sayfaSonucu.mevcutSayfa + " / " + root.sayfaSonucu.toplamSayfa
                color: Theme.metinIkincil
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutNormal
            }

            Button {
                id: sonrakiButonu
                text: "Sonraki ▶"
                enabled: root.sayfaSonucu.mevcutSayfa < root.sayfaSonucu.toplamSayfa && !root.yukleniyor
                onClicked: root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa + 1)
                background: Rectangle { radius: Theme.radiusKucuk; color: Theme.panel; border.width: 1; border.color: Theme.kenarlik; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
                contentItem: Text { text: sonrakiButonu.text; color: Theme.metinBirincil; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutNormal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: sonrakiButonu.enabled ? 1.0 : 0.4 }
            }
        }
    }

    // ---- Ekle / Duzenle dialogu ----
    TemaDialog {
        id: duzenlemeDialogu
        property int kullaniciId: 0
        property string acilisAnlikGoruntusu: ""
        width: 520
        // Baslik dogrudan "baslik" uzerinden verilir -- Musterilerim/Urunlerim
        // ile ayni yol. Eskiden Dialog'un "title" ozelligine yazilip
        // "baslik: title" ile dolayli baglaniyordu.
        onayMetni: "Kaydet"
        onayGorunur: root.duzenleyebilir
        iptalMetni: root.duzenleyebilir ? "İptal" : "Kapat"
        elleKapat: true

        // Tek giris noktasi: ekle ve duzenle ayni fonksiyonu kullanir
        // (eskiden ayni 10 satir iki yerde kopyalanmisti).
        function formuAc(kayit) {
            duzenlemeDialogu.kullaniciId = kayit ? kayit.kullaniciId : 0
            duzenlemeDialogu.baslik = kayit ? "Personel Düzenle" : "Personel Ekle"
            hataMesaji.text = ""
            adSoyadAlani.text = kayit ? kayit.adSoyad : ""
            kullaniciAdiAlani.text = kayit ? kayit.kullaniciAdi : ""
            sifreAlani.text = ""
            sifreTekrarAlani.text = ""
            duzenlemeDialogu.mevcutSifre = ""
            duzenlemeDialogu.mevcutSifreHatasi = ""
            duzenlemeDialogu.sifreGorebilir = kayit !== null && database.sifreGoruntuleyebilirMi()
            telefonAlani.text = kayit ? kayit.telefon : ""
            pozisyonAlani.text = kayit ? kayit.pozisyon : ""
            // Yeni personel varsayilan koyu temayla baslar.
            duzenlemeDialogu.koyuTema = kayit ? kayit.koyuTema !== false : true
            // Secim artik kutularin kendisinden degil, bu listeden okunuyor
            // (bkz. secilenRoller) -- kutular ona BAGLI. Eskiden secim
            // rolCheckboxRepeater.itemAt(i).checked uzerinden okunup
            // yazilıyordu; Repeater.itemAt() yalnizca Item dondurdugu icin bu
            // erisim tip guvenli degildi ve Repeater satiri henuz
            // olusturmadiysa (ör. rol listesi gec geldiyse) sessizce
            // calismiyordu.
            duzenlemeDialogu.secilenRoller = kayit ? kayit.rolIdListesi.slice() : []
            duzenlemeDialogu.acilisAnlikGoruntusu = JSON.stringify(duzenlemeDialogu.formAlani())
            duzenlemeDialogu.open()
        }

        // Secili rol id'leri. Tek dogruluk kaynagi budur.
        property var secilenRoller: []

        // Personelin programi kullanacagi tema; giris yapinca uygulanir.
        property bool koyuTema: true

        // "Göster" ile PIN sorularak sunucudan okunan mevcut sifre. Satir yalnizca
        // sifreleri gorebilen tek kullaniciya gorunur (bkz.
        // Database::sifreGoruntuleyebilirMi / personelSifresiGetir).
        property bool sifreGorebilir: false
        property string mevcutSifre: ""
        property string mevcutSifreHatasi: ""

        function mevcutSifreyiGoster() {
            if (duzenlemeDialogu.mevcutSifre.length > 0) {
                duzenlemeDialogu.mevcutSifre = ""
                return
            }
            pinDialogu.open()
        }

        function roluDegistir(rolId, secili) {
            const liste = duzenlemeDialogu.secilenRoller.slice()
            const yer = liste.indexOf(rolId)
            if (secili && yer === -1)
                liste.push(rolId)
            else if (!secili && yer !== -1)
                liste.splice(yer, 1)
            duzenlemeDialogu.secilenRoller = liste
        }

        function secilenRolIdListesi() {
            // Formu her zaman AYNI sirada temsil et: "degisiklik var mi?"
            // karsilastirmasi (degistiMi) metin bazli oldugu icin, kutulara
            // tiklama sirasi degisikligi gibi gorunmemeli.
            return duzenlemeDialogu.secilenRoller.slice().sort(function(a, b) { return a - b })
        }

        function formAlani() {
            return {
                adSoyad: adSoyadAlani.text.trim(),
                kullaniciAdi: kullaniciAdiAlani.text.trim(),
                sifre: sifreAlani.text,
                telefon: telefonAlani.text.trim(),
                pozisyon: pozisyonAlani.text.trim(),
                koyuTema: duzenlemeDialogu.koyuTema,
                rolIdListesi: secilenRolIdListesi()
            }
        }

        function degistiMi() {
            return JSON.stringify(duzenlemeDialogu.formAlani()) !== duzenlemeDialogu.acilisAnlikGoruntusu
        }

        // Personel/rol/sifre degisikligi yonetici sifresiyle onaylanir: aksi halde
        // bu ekrana erisen herkes kendine "Yönetici" rolu verip yonetici
        // sifresiyle korunan islemleri (ör. teklif silme) acabilirdi.
        // Hicbir sey degismediyse (sadece bakildiysa) sifre sorulmaz.
        onOnaylandi: {
            if (duzenlemeDialogu.kullaniciId > 0 && !duzenlemeDialogu.degistiMi()) {
                duzenlemeDialogu.close()
                return
            }

            // SIFRE TEKRARI: yazim hatasi yapilirsa kullanici giris yapamaz
            // hale gelir ve kendisi duzeltemez -- bu yuzden iki alan birbirini
            // dogrular. Kontrol burada (kaydetmeden ve sifre sormadan once).
            if (sifreAlani.text !== sifreTekrarAlani.text) {
                hataMesaji.text = "Şifre ve şifre tekrarı aynı değil."
                return
            }

            sifreDialogu.iste("Personeli Kaydet", "", "Kaydet", false,
                              function() { duzenlemeDialogu.kaydet() })
        }

        function kaydet() {
            const veri = formAlani()
            const sonuc = duzenlemeDialogu.kullaniciId > 0
                ? database.personelGuncelle(duzenlemeDialogu.kullaniciId, veri)
                : database.personelEkle(veri)
            if (!sonuc.basarili) {
                hataMesaji.text = sonuc.hata
                return
            }
            hataMesaji.text = ""
            duzenlemeDialogu.close()
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
            // Yonetici kendi temasini degistirdiyse beklemeden uygulanir.
            if (duzenlemeDialogu.kullaniciId === database.aktifKullaniciId() && veri.koyuTema !== Theme.koyuMod)
                Theme.degistirmeIstendi()
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label { id: hataMesaji; color: Theme.tehlikeAcik; font.family: Theme.fontAilesi; font.pixelSize: Theme.fontBoyutKucuk; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }

            // Alanlar artik EtiketliAlan: etiket kutunun USTUNDE durur.
            // Eskiden alan adlari yalnizca placeholder'daydi, yani kullanici
            // yazmaya basladigi anda hangi alanda oldugu gorunmez oluyordu.
            EtiketliAlan { id: adSoyadAlani; etiket: "AD SOYAD *" }
            EtiketliAlan { id: kullaniciAdiAlani; etiket: "KULLANICI ADI *" }

            Label {
                visible: duzenlemeDialogu.sifreGorebilir
                text: "MEVCUT ŞİFRE"
                color: Theme.metinSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            RowLayout {
                visible: duzenlemeDialogu.sifreGorebilir
                Layout.fillWidth: true
                spacing: 10
                TextField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi
                    readOnly: true
                    selectByMouse: true
                    text: duzenlemeDialogu.mevcutSifre.length > 0 ? duzenlemeDialogu.mevcutSifre
                        : duzenlemeDialogu.mevcutSifreHatasi.length > 0 ? duzenlemeDialogu.mevcutSifreHatasi
                        : "••••••"
                    color: duzenlemeDialogu.mevcutSifreHatasi.length > 0 ? Theme.uyariAcik : Theme.metinBirincil
                    font.family: Theme.fontAilesi
                    font.pixelSize: duzenlemeDialogu.mevcutSifreHatasi.length > 0 ? Theme.fontBoyutKucuk : Theme.fontBoyutNormal
                    leftPadding: 14
                    background: Rectangle {
                        radius: Theme.radiusKucuk
                        color: Theme.arkaplan
                        border.width: 1
                        border.color: Theme.kenarlik
                    }
                }
                TemaButon {
                    text: duzenlemeDialogu.mevcutSifre.length > 0 ? "Gizle" : "Göster"
                    onClicked: duzenlemeDialogu.mevcutSifreyiGoster()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan {
                    id: sifreAlani

                    etiket: duzenlemeDialogu.kullaniciId > 0
                            ? "YENİ ŞİFRE" : "ŞİFRE *"
                    echoMode: TextInput.Password
                }
                EtiketliAlan {
                    id: sifreTekrarAlani
                    etiket: "ŞİFRE (TEKRAR)"
                    echoMode: TextInput.Password
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                EtiketliAlan { id: telefonAlani; etiket: "TELEFON" }
                EtiketliAlan { id: pozisyonAlani; etiket: "POZİSYON" }
            }

            Label { text: "TEMA"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.topMargin: 4 }

            RowLayout {
                spacing: 8

                Repeater {
                    model: [
                        { ad: "Koyu", ikon: "ay", koyu: true },
                        { ad: "Açık", ikon: "gunes", koyu: false }
                    ]

                    delegate: Rectangle {
                        id: temaSecenegi
                        required property var modelData
                        readonly property bool secili: duzenlemeDialogu.koyuTema === modelData.koyu

                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 36
                        radius: Theme.radiusKucuk
                        color: secili ? Theme.vurguZeminSoluk : (temaSecenegiAlani.containsMouse ? Theme.panelHover : Theme.arkaplan)
                        border.width: 1
                        border.color: secili ? Theme.kenarlikVurgu : Theme.kenarlik

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            ModulIkonu {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                tur: temaSecenegi.modelData.ikon
                                renk: temaSecenegi.secili ? Theme.vurgu : Theme.metinSoluk
                            }
                            Label {
                                text: temaSecenegi.modelData.ad
                                color: temaSecenegi.secili ? Theme.metinBirincil : Theme.metinIkincil
                                font.family: Theme.fontAilesi
                                font.pixelSize: Theme.fontBoyutNormal
                                font.bold: temaSecenegi.secili
                            }
                        }

                        MouseArea {
                            id: temaSecenegiAlani
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.duzenleyebilir
                            cursorShape: Qt.PointingHandCursor
                            onClicked: duzenlemeDialogu.koyuTema = temaSecenegi.modelData.koyu
                        }
                    }
                }
            }

            Label { text: "ROLLER *"; color: Theme.metinSoluk; font.family: Theme.fontAilesi; font.pixelSize: 10; font.letterSpacing: 1; Layout.topMargin: 4 }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    id: rolCheckboxRepeater
                    model: root.rolListesi

                    delegate: TemaOnayKutusu {
                        required property var modelData
                        readonly property int rolId: modelData.rolId
                        text: modelData.rolAdi
                        checked: duzenlemeDialogu.secilenRoller.indexOf(rolId) !== -1
                        onToggled: duzenlemeDialogu.roluDegistir(rolId, checked)
                    }
                }
            }

            // Rolsuz personel giris yapabiliyor ama hicbir modul goremiyor;
            // sunucu da bu durumu reddediyor (bkz. Database::personelEkle).
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.metinCokSoluk
                font.family: Theme.fontAilesi
                font.pixelSize: 10
                text: "En az bir rol seçilmelidir; rolsüz personel giriş yapsa bile hiçbir modülü göremez."
            }
        }
    }

    // Personel ekleme/duzenleme/aktif-pasif yonetici sifresiyle onaylanir.
    SifreOnayDialog { id: sifreDialogu }

    // Personel Duzenle'de "Mevcut Şifre"yi gostermeden once PIN ister.
    TemaDialog {
        id: pinDialogu
        width: 360
        baslik: "Şifreyi Göster"
        onayMetni: "Göster"
        elleKapat: true

        onOpened: {
            pinAlani.text = ""
            pinHatasi.text = ""
            pinAlani.alan.forceActiveFocus()
        }

        onOnaylandi: {
            const sonuc = database.personelSifresiGetir(duzenlemeDialogu.kullaniciId, pinAlani.text)
            if (!sonuc.basarili && sonuc.hata === "PIN yanlış.") {
                pinHatasi.text = sonuc.hata
                pinAlani.alan.selectAll()
                pinAlani.alan.forceActiveFocus()
                return
            }
            duzenlemeDialogu.mevcutSifre = sonuc.basarili ? sonuc.sifre : ""
            duzenlemeDialogu.mevcutSifreHatasi = sonuc.basarili ? "" : sonuc.hata
            pinDialogu.close()
        }

        contentItem: ColumnLayout {
            spacing: 12
            EtiketliAlan {
                id: pinAlani
                etiket: "PIN"
                echoMode: TextInput.Password
                onKabulEdildi: pinDialogu.onaylandi()
            }
            Label {
                id: pinHatasi
                visible: text.length > 0
                Layout.fillWidth: true
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
            }
        }
    }

    function aktifDurumDegistir(kullaniciId, aktif) {
        const sonuc = database.personelAktifDurumDegistir(kullaniciId, aktif)
        if (sonuc.basarili) {
            islemHatasi.text = ""
            root.sayfayiYukle(root.sayfaSonucu.mevcutSayfa)
        } else {
            // Eskiden donen bool hic kontrol edilmiyordu: islem sessizce
            // basarisiz olup liste yenileniyordu ve kullanici neden hicbir
            // seyin degismedigini anlamiyordu.
            islemHatasi.text = sonuc.hata
        }
    }
}
