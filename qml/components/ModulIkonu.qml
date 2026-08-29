import QtQuick

// Modul kartlarinda kullanilan sade, tek renkli cizgi ikonlar (emoji yerine).
// "tur" ile hangi sekil cizilecegi secilir: belge, sepet, kutu, cuzdan, disli.
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
        }
    }

    onRenkChanged: requestPaint()
    onTurChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
