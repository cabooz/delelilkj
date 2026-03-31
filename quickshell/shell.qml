import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "components/overview"
import "components/control_centre"
import "."

ShellRoot {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property int activeVdesk: 1

    // Overview state
    property bool overviewVisible: false
    property var allWindows: []
    property var windowsByVdesk: ({})   // Pre-computed: {1: [...], 2: [...], ...}
    property string selectedWindowAddress: ""
    property int selectedWindowVdesk: 0

    // Group windows by vdesk whenever allWindows changes (O(n) single pass)
    onAllWindowsChanged: {
        var grouped = {}
        for (var i = 1; i <= 9; i++) grouped[i] = []
        allWindows.forEach(w => { if (w.vdesk >= 1 && w.vdesk <= 9) grouped[w.vdesk].push(w) })
        windowsByVdesk = grouped
    }

    // ── Virtual Desktop Helper — single abstraction for all vdesk dispatches ─
    VDeskHelper {
        id: vdesk
        onCurrentDeskResult: num => root.activeVdesk = num
    }

    // ── IPC Events (socket2) ─────────────────────────────────────────────────
    // Subscribes to Hyprland socket2 via Quickshell.Hyprland.
    // Re-renders overview on workspace/window events; syncs activeVdesk.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // workspace event: re-query active vdesk (plugin may not emit "vdesk")
            if (event.name === "workspace") {
                vdesk.getCurrentDesk()
            }
            // Window events: debounce-refresh window list and re-query vdesk
            if (event.name === "openwindow" || event.name === "closewindow" ||
                event.name === "movewindow" || event.name === "workspace") {
                stateTimer.restart()
                if (root.overviewVisible) {
                    allWindowsProcess.start()
                }
            }
            // Global shortcut fallback (in case Hyprland fires a custom event)
            if (event.name === "custom" && event.data === "toggleOverview") {
                root.toggleOverview()
            }
        }
    }

    function toggleOverview() {
        root.overviewVisible = !root.overviewVisible
        if (root.overviewVisible) {
            root.selectedWindowAddress = ""
            root.selectedWindowVdesk = 0
            allWindowsProcess.start()
            vdesk.getCurrentDesk()
        } else {
            root.selectedWindowAddress = ""
            root.selectedWindowVdesk = 0
        }
    }

    // Shortcut definition
    GlobalShortcut {
        name: "toggleOverview"
        description: "Toggle Overview"
        onPressed: root.toggleOverview()
    }

    // Debounce timer — prevents flooding on rapid events
    Timer {
        id: stateTimer
        interval: 200
        onTriggered: vdesk.getCurrentDesk()
    }

    // ── Processes ────────────────────────────────────────────────────────────

    // Query active vdesk on startup
    Process {
        id: initProcess
        command: ["sh", "-c",
                  "hyprctl printdesk 2>/dev/null | grep -oP 'desk \\K\\d+' | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                let num = parseInt(data.trim())
                if (num >= 1 && num <= 9) root.activeVdesk = num
            }
        }
    }

    // Window list fetcher — buffers full JSON before parsing
    Process {
        id: allWindowsProcess
        command: ["/home/rakman/.config/quickshell/scripts/get_all_windows.sh"]
        running: false
        property string buffer: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => allWindowsProcess.buffer += data
        }

        onExited: {
            if (buffer.length > 0) {
                try {
                    root.allWindows = JSON.parse(buffer.trim())
                } catch(e) {
                    console.log("Overview: window parse error:", e)
                    root.allWindows = []
                }
            }
            buffer = ""
        }

        function start() {
            buffer = ""
            running = true
        }
    }

    // ── Helper functions ─────────────────────────────────────────────────────

    // Move a window to another vdesk (routes through VDeskHelper)
    function moveWindowToVdesk(address, vdeskNum) {
        vdesk.moveWindowToDesk(address, vdeskNum)
        root.selectedWindowAddress = ""
        root.selectedWindowVdesk = 0
    }

    function isPopulated(vdeskNum) { return (windowsByVdesk[vdeskNum] || []).length > 0 }

    // ── UI ───────────────────────────────────────────────────────────────────

    OverviewPanel {
        visible: root.overviewVisible
        activeVdesk: root.activeVdesk
        windowsByVdesk: root.windowsByVdesk
        selectedWindowAddress: root.selectedWindowAddress
        selectedWindowVdesk: root.selectedWindowVdesk

        onToggleRequested: root.toggleOverview()
        onWindowSelected: (address, vdeskNum) => {
            root.selectedWindowAddress = address
            root.selectedWindowVdesk = vdeskNum
        }
        onWindowDeselected: {
            root.selectedWindowAddress = ""
            root.selectedWindowVdesk = 0
        }
        onWindowMoveRequested: (address, targetVdesk) => root.moveWindowToVdesk(address, targetVdesk)
        onVdeskActivated: (vdeskNum) => vdesk.switchToDesk(vdeskNum)
        onWindowFocused: (address, vdeskNum) => {
            vdesk.switchToDesk(vdeskNum)
            Hyprland.dispatch("focuswindow address:" + address)
        }
    }

    HevControl {}
}
