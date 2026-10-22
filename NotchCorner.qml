import QtQuick
import QtQuick.Shapes

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
//
// A Shape, drawn as curves straight into the scene, not a Canvas: a Canvas
// paints into a texture, and once the box was 14 px (17.5 physical) the
// texture's outer row and column smeared into a faint line along the
// corner's far sides.
Shape {
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
    readonly property bool onLeft: side === "left"
    width: r > 0 ? r + reach : 0
    height: r > 0 ? r + reach : 0
    x: sqX - (onLeft ? 0 : reach)
    y: sqY - (flip ? 0 : reach)
    visible: r > 0
    preferredRendererType: Shape.CurveRenderer
    transform: [
        Scale { origin.y: corner.height / 2; yScale: corner.flip ? -1 : 1 },
        Translate { y: corner.shiftY }
    ]

    // The box less a quarter circle centred on its bottom outer corner:
    // (0, h) for "left", (w, h) for "right".
    ShapePath {
        fillColor: corner.fill
        strokeWidth: -1

        startX: corner.onLeft ? 0 : corner.width
        startY: 0
        PathLine { x: corner.onLeft ? corner.width : 0; y: 0 }
        PathLine { x: corner.onLeft ? corner.width : 0; y: corner.height }
        PathLine { x: corner.onLeft ? corner.r : corner.width - corner.r; y: corner.height }
        PathArc {
            x: corner.onLeft ? 0 : corner.width
            y: corner.height - corner.r
            radiusX: corner.r
            radiusY: corner.r
            direction: corner.onLeft ? PathArc.Counterclockwise : PathArc.Clockwise
        }
        PathLine { x: corner.onLeft ? 0 : corner.width; y: 0 }
    }
}
