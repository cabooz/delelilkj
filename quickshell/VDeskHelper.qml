// ─── Virtual Desktop Helper ──────────────────────────────────────────────────
// Wraps ALL hyprland-virtual-desktops plugin dispatches.
// If the plugin is replaced, only this file needs updating — nothing else breaks.
//
// Public API:
//   switchToDesk(id)           → hyprctl dispatch vdesk {id}
//   moveWindowToDesk(addr, id) → hyprctl dispatch movetodesksilent {id},address:{addr}
//   getCurrentDesk()           → parses hyprctl printdesk → emits currentDeskResult(id)
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root

    // Emitted once the current desk ID is known
    signal currentDeskResult(id: int)

    // ── switchToDesk(id) ─────────────────────────────────────────────────────
    function switchToDesk(id) {
        Hyprland.dispatch("vdesk " + id)
    }

    // ── moveWindowToDesk(addr, id) ───────────────────────────────────────────
    function moveWindowToDesk(addr, id) {
        Hyprland.dispatch("movetodesksilent " + id + ",address:" + addr)
    }

    // ── getCurrentDesk() — async, result via currentDeskResult signal ────────
    function getCurrentDesk() {
        _printdeskProc.running = true
    }

    // ── Internal: parse hyprctl printdesk output ─────────────────────────────
    Process {
        id: _printdeskProc
        // "hyprctl printdesk" outputs e.g. "Virtual desk 3 (Grid-3)"
        command: ["sh", "-c",
                  "hyprctl printdesk 2>/dev/null | grep -oP 'desk \\K\\d+' | head -1"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                let num = parseInt(data.trim())
                if (num >= 1 && num <= 9) root.currentDeskResult(num)
            }
        }
    }
}
