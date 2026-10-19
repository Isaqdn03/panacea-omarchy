import QtQuick
import QtQuick.Layouts

// Windows: gaps, borders, corners, dimming and animations. Saved into
// ~/.config/hypr/looknfeel.lua, the file Omarchy keeps for these, next to
// whatever is already there (see sys.hyprSet / scripts/hyprconf.py).
//
// Blur is not here on purpose: Glass mode (Control Center, SUPER+SHIFT+T)
// owns it, together with the terminals' transparency.
ColumnLayout {
    id: page

    property var sys
    readonly property var live: page.sys.hyprLive

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: page.sys.refreshHyprLive()

    function num(key, fallback) {
        var v = page.live[key];
        return v === undefined || v === null ? fallback : Number(v);
    }
    function set(path, lua) { page.sys.hyprSet("looknfeel", path, lua); }

    Text {
        Layout.fillWidth: true
        visible: page.sys.hyprError.length > 0
        text: page.sys.hyprError
        color: page.sys.colCrit
        wrapMode: Text.WordWrap
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Spacing" }

        SetSlider {
            sys: page.sys
            label: "Gap between windows"
            from: 0; to: 30; step: 1
            suffix: "px"
            value: page.num("general:gaps_in", 5)
            onMoved: v => page.set("general.gaps_in", String(Math.round(v)))
        }

        SetSlider {
            sys: page.sys
            label: "Gap to screen edges"
            from: 0; to: 40; step: 1
            suffix: "px"
            value: page.num("general:gaps_out", 10)
            onMoved: v => page.set("general.gaps_out", String(Math.round(v)))
        }
    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Frames" }

        SetSlider {
            sys: page.sys
            label: "Border width"
            from: 0; to: 6; step: 1
            suffix: "px"
            value: page.num("general:border_size", 2)
            onMoved: v => page.set("general.border_size", String(Math.round(v)))
        }

        SetSlider {
            sys: page.sys
            label: "Corner rounding"
            from: 0; to: 24; step: 1
            suffix: "px"
            value: page.num("decoration:rounding", 0)
            onMoved: v => page.set("decoration.rounding", String(Math.round(v)))
        }

        SetToggle {
            sys: page.sys
            label: "Dim inactive windows"
            on: page.live["decoration:dim_inactive"] === true
            onToggled: v => page.set("decoration.dim_inactive", v ? "true" : null)
        }

        SetSlider {
            sys: page.sys
            visible: page.live["decoration:dim_inactive"] === true
            label: "Dim strength"
            from: 0.05; to: 0.6; step: 0.05
            decimals: 2
            value: page.num("decoration:dim_strength", 0.5)
            onMoved: v => page.set("decoration.dim_strength", v.toFixed(2))
        }
    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Motion" }

        SetToggle {
            sys: page.sys
            label: "Window animations"
            sub: "Hyprland's own animations. The curves and speeds stay as looknfeel.lua defines them."
            on: page.live["animations:enabled"] !== false
            onToggled: v => page.set("animations.enabled", v ? "true" : "false")
        }
    }
}
