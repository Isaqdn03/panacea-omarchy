import QtQuick

// Вогнутый угол примыкания к кромке экрана — как у выреза на macOS.
//
// Заливка занимает квадрат r×r, из которого вырезана четверть круга
// с центром в нижнем внешнем углу. Получается плавный переход от
// верхней кромки экрана к боку пилюли, без «ступеньки».
//
// PANACEA-LOCAL: the square is placed by sqX/sqY, and the fill reaches
// `overlap` past it on its two straight sides: under whatever it meets there
// (the pill, the rail, an island, or off the screen's edge). The corner and
// what it meets are separate items, and at a fractional scale (1.25 here)
// their edges land on the same half pixel: each draws that pixel half
// covered, and the wallpaper showed through between them as a hairline.
// flip turns it upside down within its own box (for the bottom edge, or
// below a side pill); shiftY moves it with what it hangs from.
Canvas {
    id: corner

    // "left"  — угол слева от пилюли (выемка смотрит влево-вниз)
    // "right" — зеркально
    property string side: "left"
    property color fill: "#000000"
    property real r: 12
    property real overlap: 2
    property real sqX: 0
    property real sqY: 0
    property bool flip: false
    property real shiftY: 0

    readonly property real reach: r > 0 ? overlap : 0
    width: r > 0 ? r + reach : 0
    height: r > 0 ? r + reach : 0
    x: sqX - (side === "right" ? reach : 0)
    y: sqY - (flip ? 0 : reach)
    transform: [
        Scale { origin.y: corner.height / 2; yScale: corner.flip ? -1 : 1 },
        Translate { y: corner.shiftY }
    ]

    onFillChanged: requestPaint()
    onRChanged: requestPaint()
    onSideChanged: requestPaint()
    onOverlapChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (r <= 0) return;
        var w = width, h = height;
        ctx.fillStyle = corner.fill;
        ctx.beginPath();

        if (side === "left") {
            // центр выреза — в нижнем левом углу: (0, h)
            ctx.moveTo(0, 0);
            ctx.lineTo(w, 0);
            ctx.lineTo(w, h);
            ctx.lineTo(r, h);
            ctx.arc(0, h, r, 0, -Math.PI / 2, true);
        } else {
            // зеркально: центр выреза в (w, h)
            ctx.moveTo(w, 0);
            ctx.lineTo(0, 0);
            ctx.lineTo(0, h);
            ctx.lineTo(w - r, h);
            ctx.arc(w, h, r, Math.PI, -Math.PI / 2, false);
        }

        ctx.closePath();
        ctx.fill();
    }
}
