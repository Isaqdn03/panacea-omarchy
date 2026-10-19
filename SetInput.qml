import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Mouse, keyboard and touchpad. These are libinput settings that Hyprland
// owns, so the page reads them from Hyprland (sys.hyprLive) and saves them
// into ~/.config/hypr/input.lua, the file Omarchy keeps for your input
// overrides (see sys.hyprSet / scripts/hyprconf.py). Turning something back
// to its default removes the line, so Omarchy's own default applies again.
ColumnLayout {
    id: page

    property var sys
    property bool hasTouchpad: false
    property bool confirmReset: false

    readonly property var live: page.sys.hyprLive

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: {
        page.sys.refreshHyprLive();
        pTouchpad.running = true;
    }

    Process {
        id: pTouchpad
        command: ["omarchy-hw-touchpad"]
        onExited: code => page.hasTouchpad = code === 0
    }

    function num(key, fallback) {
        var v = page.live[key];
        return v === undefined || v === null ? fallback : Number(v);
    }
    function flag(key) { return page.live[key] === true; }
    function set(path, lua) { page.sys.hyprSet("input", path, lua); }

    // kb_options can hold more than the layout-switch key (compose, caps
    // remaps...): only the grp: entry is replaced, the rest is kept.
    function layoutSwitch() {
        var opts = String(page.live["input:kb_options"] || "").split(",");
        for (var i = 0; i < opts.length; i++)
            if (opts[i].indexOf("grp:") === 0) return opts[i];
        return "";
    }
    function setLayoutSwitch(id) {
        var opts = String(page.live["input:kb_options"] || "").split(",")
            .filter(o => o.length > 0 && o.indexOf("grp:") !== 0);
        if (id.length) opts.push(id);
        page.set("input.kb_options", opts.length ? "\"" + opts.join(",") + "\"" : null);
    }

    Text {
        Layout.fillWidth: true
        visible: page.sys.hyprError.length > 0
        text: page.sys.hyprError
        color: page.sys.colCrit
        wrapMode: Text.WordWrap
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
    }

    // ----------------------------------------------------------- pointer
    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Mouse" }

        // libinput's scale: -1 slowest, 0 as the mouse reports it, 1 fastest.
        // It shifts the curve rather than multiplying, hence the fine step.
        SetSlider {
            sys: page.sys
            label: "Pointer speed"
            from: -1; to: 1; step: 0.05
            decimals: 2
            value: page.num("input:sensitivity", 0)
            onMoved: v => page.set("input.sensitivity", v.toFixed(2))
        }

        SetToggle {
            sys: page.sys
            label: "Raw input"
            sub: "No acceleration: the same movement on the desk always moves the pointer the same distance. The flat profile games want."
            on: page.live["input:accel_profile"] === "flat"
            onToggled: v => page.set("input.accel_profile", v ? "\"flat\"" : null)
        }

        SetSlider {
            sys: page.sys
            label: "Scroll speed"
            from: 0.25; to: 3; step: 0.05
            decimals: 2
            suffix: "×"
            value: page.num("input:scroll_factor", 1)
            onMoved: v => page.set("input.scroll_factor", Math.abs(v - 1) < 0.001 ? null : v.toFixed(2))
        }

        SetToggle {
            sys: page.sys
            label: "Natural scrolling"
            sub: "Content follows the wheel, like a touchscreen."
            on: page.flag("input:natural_scroll")
            onToggled: v => page.set("input.natural_scroll", v ? "true" : null)
        }

        SetToggle {
            sys: page.sys
            label: "Left-handed buttons"
            on: page.flag("input:left_handed")
            onToggled: v => page.set("input.left_handed", v ? "true" : null)
        }

        SetSelect {
            sys: page.sys
            label: "Window focus"
            options: [
                { id: "1", text: "Follows mouse" },
                { id: "2", text: "Loose" },
                { id: "0", text: "On click" }
            ]
            value: String(page.num("input:follow_mouse", 1))
            onPicked: id => page.set("input.follow_mouse", id)
        }
    }

    // ---------------------------------------------------------- keyboard
    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Keyboard" }

        SetSlider {
            sys: page.sys
            label: "Repeat rate"
            from: 10; to: 80; step: 1
            suffix: "/s"
            value: page.num("input:repeat_rate", 40)
            onMoved: v => page.set("input.repeat_rate", String(Math.round(v)))
        }

        SetSlider {
            sys: page.sys
            label: "Repeat delay"
            from: 150; to: 1000; step: 25
            suffix: "ms"
            value: page.num("input:repeat_delay", 250)
            onMoved: v => page.set("input.repeat_delay", String(Math.round(v)))
        }

        SetToggle {
            sys: page.sys
            label: "Num Lock on at login"
            on: page.flag("input:numlock_by_default")
            onToggled: v => page.set("input.numlock_by_default", v ? "true" : "false")
        }

        Text {
            text: "Layouts"
            color: page.sys.colFg
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 2 }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 10
            color: Qt.rgba(page.sys.colFg.r, page.sys.colFg.g, page.sys.colFg.b, 0.07)

            TextInput {
                id: layoutInput
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                color: page.sys.colFg
                clip: true
                selectByMouse: true
                text: String(page.live["input:kb_layout"] || "")
                validator: RegularExpressionValidator { regularExpression: /[a-z0-9_,()-]*/ }
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 2 }
                onEditingFinished: {
                    var v = text.trim().replace(/\s+/g, "");
                    if (v === String(page.live["input:kb_layout"] || "")) return;
                    page.set("input.kb_layout", v.length ? "\"" + v + "\"" : null);
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: layoutInput.text.length === 0
                    text: "us,ru"
                    color: page.sys.colMuted
                    font: layoutInput.font
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "XKB layout codes, comma separated. Leave empty to use the system layout from /etc/vconsole.conf, which is Omarchy's default."
            color: page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }

        SetSelect {
            sys: page.sys
            visible: String(page.live["input:kb_layout"] || "").indexOf(",") >= 0
            label: "Switch layouts with"
            options: [
                { id: "grp:alt_shift_toggle",  text: "Alt + Shift" },
                { id: "grp:ctrl_shift_toggle", text: "Ctrl + Shift" },
                { id: "grp:caps_toggle",       text: "Caps Lock" },
                { id: "",                      text: "Nothing" }
            ]
            value: page.layoutSwitch()
            onPicked: id => page.setLayoutSwitch(id)
        }
    }

    // ---------------------------------------------------------- touchpad
    SetCard {
        sys: page.sys
        visible: page.hasTouchpad

        SetLabel { sys: page.sys; text: "Touchpad" }

        SetToggle {
            sys: page.sys
            label: "Natural scrolling"
            on: page.flag("input:touchpad:natural_scroll")
            onToggled: v => page.set("input.touchpad.natural_scroll", v ? "true" : "false")
        }

        SetToggle {
            sys: page.sys
            label: "Tap to click"
            on: page.flag("input:touchpad:tap-to-click")
            onToggled: v => page.set("input.touchpad.tap_to_click", v ? "true" : "false")
        }

        SetToggle {
            sys: page.sys
            label: "Ignore while typing"
            on: page.flag("input:touchpad:disable_while_typing")
            onToggled: v => page.set("input.touchpad.disable_while_typing", v ? "true" : "false")
        }

        SetToggle {
            sys: page.sys
            label: "Two-finger right click"
            sub: "Off: click the lower-right corner instead."
            on: page.flag("input:touchpad:clickfinger_behavior")
            onToggled: v => page.set("input.touchpad.clickfinger_behavior", v ? "true" : "false")
        }

        SetSlider {
            sys: page.sys
            label: "Scroll speed"
            from: 0.1; to: 2; step: 0.05
            decimals: 2
            suffix: "×"
            value: page.num("input:touchpad:scroll_factor", 1)
            onMoved: v => page.set("input.touchpad.scroll_factor", v.toFixed(2))
        }
    }

    // ------------------------------------------------------------- reset
    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Defaults" }

        Text {
            Layout.fillWidth: true
            text: page.confirmReset
                  ? "This removes the mouse and keyboard lines this page manages from input.lua, including ones you wrote by hand. Click again to confirm."
                  : "Remove this page's settings from input.lua and go back to Omarchy's defaults."
            color: page.confirmReset ? page.sys.colCrit : page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }

        SetButton {
            sys: page.sys
            text: page.confirmReset ? "Yes, reset" : "Restore Omarchy defaults"
            onClicked: {
                if (!page.confirmReset) { page.confirmReset = true; return; }
                page.confirmReset = false;
                ["input.sensitivity", "input.accel_profile", "input.scroll_factor",
                 "input.natural_scroll", "input.left_handed", "input.follow_mouse",
                 "input.repeat_rate", "input.repeat_delay", "input.numlock_by_default"]
                    .forEach(p => page.sys.hyprRun(["unset", "input", p]));
            }
        }
    }
}
