import QtQuick

// Modul kartlarinda kullanilan sade, tek renkli cizgi ikonlar (emoji yerine).
// "tur" ile hangi sekil cizilecegi secilir: belge, sepet, kutu, cuzdan, disli;
// tema anahtari icin gunes ve ay; yan menu icin ev, kalem, gonder, onay, bayrak,
// kisiler.
Canvas {
    id: ikon
    property string tur: "belge"
    property color renk: "#ffffff"

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.lineWidth = Math.max(1.4, width * 0.07);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.strokeStyle = renk;
        ctx.fillStyle = renk;

        var w = width, h = height;

        switch (tur) {
        case "belge":
            ctx.beginPath();
            ctx.moveTo(w * 0.28, h * 0.06);
            ctx.lineTo(w * 0.62, h * 0.06);
            ctx.lineTo(w * 0.82, h * 0.26);
            ctx.lineTo(w * 0.82, h * 0.94);
            ctx.lineTo(w * 0.28, h * 0.94);
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(w * 0.62, h * 0.06);
            ctx.lineTo(w * 0.62, h * 0.26);
            ctx.lineTo(w * 0.82, h * 0.26);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(w * 0.40, h * 0.54);
            ctx.lineTo(w * 0.70, h * 0.54);
            ctx.moveTo(w * 0.40, h * 0.70);
            ctx.lineTo(w * 0.70, h * 0.70);
            ctx.stroke();
            break;

        case "sepet":
            ctx.beginPath();
            ctx.moveTo(w * 0.10, h * 0.20);
            ctx.lineTo(w * 0.24, h * 0.20);
            ctx.lineTo(w * 0.36, h * 0.70);
            ctx.lineTo(w * 0.82, h * 0.70);
            ctx.lineTo(w * 0.92, h * 0.34);
            ctx.lineTo(w * 0.30, h * 0.34);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(w * 0.44, h * 0.86, h * 0.055, 0, Math.PI * 2);
            ctx.fill();
            ctx.beginPath();
            ctx.arc(w * 0.76, h * 0.86, h * 0.055, 0, Math.PI * 2);
            ctx.fill();
            break;

        case "kutu":
            ctx.beginPath();
            ctx.moveTo(w * 0.5, h * 0.05);
            ctx.lineTo(w * 0.91, h * 0.27);
            ctx.lineTo(w * 0.91, h * 0.73);
            ctx.lineTo(w * 0.5, h * 0.95);
            ctx.lineTo(w * 0.09, h * 0.73);
            ctx.lineTo(w * 0.09, h * 0.27);
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(w * 0.09, h * 0.27);
            ctx.lineTo(w * 0.5, h * 0.49);
            ctx.lineTo(w * 0.91, h * 0.27);
            ctx.moveTo(w * 0.5, h * 0.49);
            ctx.lineTo(w * 0.5, h * 0.95);
            ctx.stroke();
            break;

        case "cuzdan":
            ctx.beginPath();
            ctx.moveTo(w * 0.5, h * 0.08);
            ctx.bezierCurveTo(w * 0.20, h * 0.08, w * 0.06, h * 0.30, w * 0.06, h * 0.54);
            ctx.bezierCurveTo(w * 0.06, h * 0.80, w * 0.26, h * 0.93, w * 0.5, h * 0.93);
            ctx.bezierCurveTo(w * 0.74, h * 0.93, w * 0.94, h * 0.80, w * 0.94, h * 0.54);
            ctx.bezierCurveTo(w * 0.94, h * 0.30, w * 0.80, h * 0.08, w * 0.5, h * 0.08);
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(w * 0.5, h * 0.08);
            ctx.lineTo(w * 0.5, h * 0.93);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(w * 0.5, h * 0.505, h * 0.10, 0, Math.PI * 2);
            ctx.stroke();
            break;

        case "disli":
            var cx = w * 0.5, cy = h * 0.5, rOuter = w * 0.42, rInner = rOuter * 0.76, teeth = 8;
            ctx.beginPath();
            for (var i = 0; i < teeth * 2; i++) {
                var ang = i * Math.PI / teeth;
                var r = (i % 2 === 0) ? rOuter : rInner;
                var x = cx + r * Math.cos(ang);
                var y = cy + r * Math.sin(ang);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter * 0.42, 0, Math.PI * 2);
            ctx.stroke();
            break;

        case "gunes":
            ctx.beginPath();
            ctx.arc(w * 0.5, h * 0.5, w * 0.18, 0, Math.PI * 2);
            ctx.stroke();
            ctx.beginPath();
            for (var n = 0; n < 8; n++) {
                var aci = n * Math.PI / 4;
                ctx.moveTo(w * (0.5 + 0.31 * Math.cos(aci)), h * (0.5 + 0.31 * Math.sin(aci)));
                ctx.lineTo(w * (0.5 + 0.43 * Math.cos(aci)), h * (0.5 + 0.43 * Math.sin(aci)));
            }
            ctx.stroke();
            break;

        case "ay":
            // Hilal: dis cemberin uzun yayi + sag ustten "isirik" yapan esit
            // yaricapli ikinci cemberin dis cember icinde kalan yayi.
            var R = w * 0.36, d = w * 0.30, yon = -Math.PI / 4;
            var alfa = Math.acos(d / 2 / R);
            var mx = w * 0.5, my = h * 0.5;
            ctx.beginPath();
            ctx.arc(mx, my, R, yon + alfa, yon - alfa + Math.PI * 2, false);
            ctx.arc(mx + d * Math.cos(yon), my + d * Math.sin(yon), R, yon + Math.PI + alfa, yon + Math.PI - alfa, true);
            ctx.closePath();
            ctx.stroke();
            break;

        case "ev":
            ctx.beginPath();
            ctx.moveTo(w * 0.10, h * 0.50);
            ctx.lineTo(w * 0.50, h * 0.12);
            ctx.lineTo(w * 0.90, h * 0.50);
            ctx.moveTo(w * 0.22, h * 0.40);
            ctx.lineTo(w * 0.22, h * 0.88);
            ctx.lineTo(w * 0.78, h * 0.88);
            ctx.lineTo(w * 0.78, h * 0.40);
            ctx.moveTo(w * 0.42, h * 0.88);
            ctx.lineTo(w * 0.42, h * 0.64);
            ctx.lineTo(w * 0.58, h * 0.64);
            ctx.lineTo(w * 0.58, h * 0.88);
            ctx.stroke();
            break;

        case "kalem":
            ctx.beginPath();
            ctx.moveTo(w * 0.16, h * 0.84);
            ctx.lineTo(w * 0.21, h * 0.62);
            ctx.lineTo(w * 0.66, h * 0.17);
            ctx.lineTo(w * 0.83, h * 0.34);
            ctx.lineTo(w * 0.38, h * 0.79);
            ctx.closePath();
            ctx.moveTo(w * 0.55, h * 0.28);
            ctx.lineTo(w * 0.72, h * 0.45);
            ctx.stroke();
            break;

        case "gonder":
            ctx.beginPath();
            ctx.moveTo(w * 0.08, h * 0.46);
            ctx.lineTo(w * 0.92, h * 0.10);
            ctx.lineTo(w * 0.64, h * 0.90);
            ctx.lineTo(w * 0.46, h * 0.56);
            ctx.closePath();
            ctx.moveTo(w * 0.46, h * 0.56);
            ctx.lineTo(w * 0.92, h * 0.10);
            ctx.stroke();
            break;

        case "onay":
            ctx.beginPath();
            ctx.arc(w * 0.5, h * 0.5, w * 0.40, 0, Math.PI * 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(w * 0.31, h * 0.52);
            ctx.lineTo(w * 0.45, h * 0.66);
            ctx.lineTo(w * 0.70, h * 0.38);
            ctx.stroke();
            break;

        case "bayrak":
            ctx.beginPath();
            ctx.moveTo(w * 0.22, h * 0.92);
            ctx.lineTo(w * 0.22, h * 0.10);
            ctx.moveTo(w * 0.22, h * 0.14);
            ctx.lineTo(w * 0.82, h * 0.14);
            ctx.lineTo(w * 0.66, h * 0.34);
            ctx.lineTo(w * 0.82, h * 0.54);
            ctx.lineTo(w * 0.22, h * 0.54);
            ctx.stroke();
            break;

        case "kisiler":
            ctx.beginPath();
            ctx.arc(w * 0.38, h * 0.34, w * 0.15, 0, Math.PI * 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(w * 0.38, h * 0.92, w * 0.28, Math.PI, Math.PI * 2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(w * 0.70, h * 0.36, w * 0.12, -Math.PI * 0.6, Math.PI * 0.6);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(w * 0.72, h * 0.90, w * 0.22, Math.PI * 1.45, Math.PI * 2);
            ctx.stroke();
            break;
        }
    }

    onRenkChanged: requestPaint()
    onTurChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
