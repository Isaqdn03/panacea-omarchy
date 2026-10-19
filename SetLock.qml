import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Idle & Lock. Omarchy owns the lock screen (omarchy.lock), the screensaver
// and the idle timer, so this page drives those instead of a lock of its own:
// timings live in ~/.config/omarchy/shell.json (idle.screensaver / idle.lock)
// and "stay awake" is Omarchy's `omarchy toggle idle`.
ColumnLayout {
    id: page

    property var sys
    // { screensaver, lock, stayAwake } -- seconds
    property var idle: ({ screensaver: 150, lock: 300, stayAwake: false })
    property int draftSaver: 150
    property int draftLock: 300

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: pGet.running = true

    Process {
        id: pGet
        command: ["sh", "-c", page.sys.scriptDir + "/omarchy-idle.sh get"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    page.idle = JSON.parse(line);
                    page.draftSaver = page.idle.screensaver;
                    page.draftLock = page.idle.lock;
                } catch (e) {}
            }
        }
    }
    Process {
        id: pSet
        onExited: { pGet.running = false; pGet.running = true; }
    }
    // One write when the handle stops, not one per pixel of drag.
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: {
            pSet.command = ["sh", "-c", page.sys.scriptDir + "/omarchy-idle.sh set "
                            + page.draftSaver + " " + page.draftLock];
            pSet.running = true;
        }
    }

    function minutes(s) {
        return s < 60 ? s + " s" : (s % 60 === 0 ? (s / 60) + " min" : (s / 60).toFixed(1) + " min");
    }

    SetCard {
        sys: page.sys

        SetToggle {
            sys: page.sys
            label: "Stay awake"
            sub: page.sys.keepAwake
                 ? "On: the screensaver and the idle lock never start. Same switch as Coffee mode and `omarchy toggle idle`."
                 : "Keep the screen on and unlocked while idle. Same switch as Coffee mode and `omarchy toggle idle`."
            on: page.sys.keepAwake
            onToggled: v => page.sys.setKeepAwake(v)
        }
    }

    SetCard {
        sys: page.sys
        opacity: page.sys.keepAwake ? 0.5 : 1

        SetLabel { sys: page.sys; text: "When idle" }

        SetSlider {
            sys: page.sys
            label: "Screensaver after"
            from: 30; to: 3600; step: 30
            value: page.draftSaver
            valueText: page.minutes(page.draftSaver)
            onMoved: v => { page.draftSaver = Math.round(v); saveTimer.restart(); }
        }

        SetSlider {
            sys: page.sys
            label: "Lock after"
            from: 60; to: 7200; step: 60
            value: page.draftLock
            valueText: page.minutes(page.draftLock)
            onMoved: v => { page.draftLock = Math.round(v); saveTimer.restart(); }
        }

        Text {
            Layout.fillWidth: true
            text: "Counted from the start of idle, so the lock can come before or after the screensaver. Saved in ~/.config/omarchy/shell.json."
            color: page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }
    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: "Lock screen" }

        Text {
            Layout.fillWidth: true
            text: "Omarchy's lock screen, with fingerprint support when it is set up (`omarchy setup security fingerprint`)."
            color: page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }

        SetButton {
            sys: page.sys
            text: "Lock now"
            onClicked: page.sys.runDetached("omarchy-system-lock")
        }
    }
}
