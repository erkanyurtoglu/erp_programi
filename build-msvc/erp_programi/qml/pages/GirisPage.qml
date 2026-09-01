import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import erp_programi


Rectangle {
    id: kok
    color: Theme.arkaplan

    property bool sifreGorunur: false

    signal girisBasarili(var sonuc)

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#15121a" }
        GradientStop { position: 0.55; color: "#0c0b0e" }
        GradientStop { position: 1.0; color: Theme.arkaplan }
    }

    // Kartin arkasinda hafif bir mavi hale, sade zemine derinlik katmak icin.
    Rectangle {
        anchors.centerIn: kart
        width: 640
        height: 640
        radius: width / 2
        opacity: 0.10
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.vurgu }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // Kartin cevresinde katmanli golge halkalari (dis -> ic, giderek koyulasan).
    Rectangle {
        anchors.centerIn: kart
        width: kart.width + 48
        height: kart.height + 48
        radius: 28
        color: "#18000000"
    }

    Rectangle {
        anchors.centerIn: kart
        width: kart.width + 32
        height: kart.height + 32
        radius: 24
        color: "#25000000"
    }

    Rectangle {
        anchors.centerIn: kart
        width: kart.width + 18
        height: kart.height + 18
        radius: 20
        color: "#35000000"
    }

    Rectangle {
        anchors.centerIn: kart
        width: kart.width + 8
        height: kart.height + 8
        radius: 18
        color: "#45000000"
    }

    Rectangle {
        id: kart
        anchors.centerIn: parent
        width: 400
        height: kolon.implicitHeight + 64
        radius: Theme.radiusBuyuk
        color: Theme.panel
        border.color: Theme.kenarlik
        border.width: 1

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: -1
            height: 3
            radius: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.5; color: Theme.vurgu }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        ColumnLayout {
            id: kolon
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 32
            width: parent.width - 48
            spacing: 20

            ColumnLayout {
                spacing: 4
                Layout.alignment: Qt.AlignHCenter

                Label {
                    text: "LIYA"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBuyukBaslik
                    font.bold: true
                    font.letterSpacing: 2
                    color: Theme.metinBirincil
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "ERP"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutNormal
                    font.letterSpacing: 4
                    color: Theme.vurgu
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Rectangle { width: 50; height: 1; color: Theme.kenarlik }
                Rectangle { width: 5; height: 5; rotation: 45; color: Theme.vurgu }
                Rectangle { width: 50; height: 1; color: Theme.kenarlik }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "Sisteme Giriş"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutBaslik
                    font.letterSpacing: 0.5
                    font.bold: true
                    color: Theme.metinBirincil
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: "Yetkili hesabınızla devam edin"
                    font.family: Theme.fontAilesi
                    font.pixelSize: Theme.fontBoyutKucuk
                    color: Theme.metinSoluk
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: "KULLANICI ADI"
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: Theme.metinSoluk
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 2
                    radius: Theme.radiusKucuk
                    color: Theme.arkaplan
                    border.width: 1
                    border.color: kullaniciAdiAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

                    TextField {
                        id: kullaniciAdiAlani
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        background: null
                        color: Theme.metinBirincil
                        placeholderTextColor: Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        placeholderText: "kullanici.adi"
                        verticalAlignment: TextInput.AlignVCenter
                        onAccepted: sifreAlani.forceActiveFocus()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: "ŞİFRE"
                    font.family: Theme.fontAilesi
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: Theme.metinSoluk
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.girdiYuksekligi + 2
                    radius: Theme.radiusKucuk
                    color: Theme.arkaplan
                    border.width: 1
                    border.color: sifreAlani.activeFocus ? Theme.kenarlikVurgu : Theme.kenarlik

                    TextField {
                        id: sifreAlani
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 48
                        background: null
                        color: Theme.metinBirincil
                        placeholderTextColor: Theme.metinCokSoluk
                        font.family: Theme.fontAilesi
                        font.pixelSize: Theme.fontBoyutNormal
                        echoMode: kok.sifreGorunur ? TextInput.Normal : TextInput.Password
                        placeholderText: "••••••••"
                        verticalAlignment: TextInput.AlignVCenter
                        onAccepted: girisButonu.clicked()
                    }

                    Rectangle {
                        id: sifreGosterButonu
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 8
                        width: 28
                        height: 28
                        radius: 6
                        color: sifreGosterMouse.pressed ? Theme.panelHover : (sifreGosterMouse.containsMouse ? Theme.panelVurgu : "transparent")
                        border.color: kok.sifreGorunur ? Theme.kenarlik : "transparent"
                        border.width: 1

                        property color ikonRengi: sifreGosterMouse.containsMouse || kok.sifreGorunur ? Theme.metinBirincil : Theme.metinSoluk

                        Canvas {
                            id: sifreIkonu
                            anchors.centerIn: parent
                            width: 18
                            height: 18

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.lineWidth = 1.7
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.strokeStyle = sifreGosterButonu.ikonRengi

                                ctx.beginPath()
                                ctx.moveTo(1.5, 9)
                                ctx.bezierCurveTo(4.2, 4.8, 7.0, 3.8, 9, 3.8)
                                ctx.bezierCurveTo(11.0, 3.8, 13.8, 4.8, 16.5, 9)
                                ctx.bezierCurveTo(13.8, 13.2, 11.0, 14.2, 9, 14.2)
                                ctx.bezierCurveTo(7.0, 14.2, 4.2, 13.2, 1.5, 9)
                                ctx.stroke()

                                ctx.beginPath()
                                ctx.arc(9, 9, 2.5, 0, Math.PI * 2, false)
                                ctx.stroke()

                                if (kok.sifreGorunur) {
                                    ctx.beginPath()
                                    ctx.moveTo(3, 15)
                                    ctx.lineTo(15, 3)
                                    ctx.stroke()
                                }
                            }

                            Connections {
                                target: kok
                                function onSifreGorunurChanged() {
                                    sifreIkonu.requestPaint()
                                }
                            }

                            Connections {
                                target: sifreGosterButonu
                                function onIkonRengiChanged() {
                                    sifreIkonu.requestPaint()
                                }
                            }
                        }

                        MouseArea {
                            id: sifreGosterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: kok.sifreGorunur = !kok.sifreGorunur
                        }
                    }
                }
            }

            Label {
                id: hataMesaji
                Layout.fillWidth: true
                color: Theme.tehlikeAcik
                font.family: Theme.fontAilesi
                font.pixelSize: Theme.fontBoyutKucuk
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            Button {
                id: girisButonu
                text: "Giriş Yap"
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 4

                background: Rectangle {
                    radius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: girisButonu.pressed ? "#1d4ed8" : (girisButonu.hovered ? Theme.vurguAcik : Theme.vurgu) }
                        GradientStop { position: 1.0; color: girisButonu.pressed ? "#1e3a8a" : (girisButonu.hovered ? Theme.vurguHover : "#1d4ed8") }
                    }
                }
                contentItem: Text {
                    text: girisButonu.text
                    color: "#1e2a3f"
                    font.family: Theme.fontAilesi
                    font.bold: true
                    font.pixelSize: Theme.fontBoyutNormal
                    font.letterSpacing: 0.5
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    hataMesaji.text = "";

                    if (!database.baglantiHazir) {
                        hataMesaji.text = "Veritabanına bağlanılamadı. Sunucu ve ağ bağlantınızı kontrol edin.";
                        return;
                    }

                    const sonuc = database.girisYap(kullaniciAdiAlani.text, sifreAlani.text);
                    if (sonuc.basarili) {
                        sifreAlani.text = "";
                        kok.girisBasarili(sonuc);
                    } else {
                        hataMesaji.text = sonuc.hata;
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.kenarlik
            }
        }
    }
}
