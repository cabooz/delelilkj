// ─── Overview Panel ───────────────────────────────────────────────────────────
// 3×3 virtual-desktop grid overlay.
// All colors sourced from Theme.qml — no hardcoded hex values.
//
// Properties (set by shell.qml):
//   activeVdesk           : int         — currently active vdesk (1–9)
//   windowsByVdesk        : var         — { 1: [{vdesk,address,title,class,x,y,width,height},...], ... }
//   selectedWindowAddress : string      — currently selected window address
//   selectedWindowVdesk   : int         — vdesk of selected window
//
// Signals emitted to shell.qml:
//   toggleRequested()                         — close the overview
//   windowSelected(address, vdeskNum)          — thumbnail clicked once
//   windowDeselected()                         — selection cleared
//   windowMoveRequested(address, targetVdesk)  — cross-vdesk drop
//   vdeskActivated(vdeskNum)                   — empty cell or header clicked
//   windowFocused(address, vdeskNum)           — thumbnail double-clicked / Enter
// ─────────────────────────────────────────────────────────────────────────────
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../"   // Theme singleton (quickshell/qmldir)

PanelWindow {
    id: root

    // ── Public properties ─────────────────────────────────────────────────────
    property int activeVdesk: 1
    property var windowsByVdesk: ({})
    property string selectedWindowAddress: ""
    property int selectedWindowVdesk: 0

    // ── Public signals ────────────────────────────────────────────────────────
    signal toggleRequested()
    signal windowSelected(string address, int vdeskNum)
    signal windowDeselected()
    signal windowMoveRequested(string address, int targetVdesk)
    signal vdeskActivated(int vdeskNum)
    signal windowFocused(string address, int vdeskNum)

    // ── Panel setup ───────────────────────────────────────────────────────────
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    color: "transparent"

    // ── Layout constants ──────────────────────────────────────────────────────
    readonly property real _gap: 10          // gap between cells (px)
    readonly property real _headerH: 24      // cell header height (px)
    readonly property real _cellW: (root.width  - 4 * _gap) / 3
    readonly property real _cellH: (root.height - 4 * _gap) / 3
    // Scale factor: overview-cell-width / real-monitor-width
    readonly property real _scale: _cellW / Math.max(root.width, 1)
    // Minimum thumbnail dimensions (overview-cell pixels)
    readonly property int _minThumbW: 20
    readonly property int _minThumbH: 14

    // ── Drag state ────────────────────────────────────────────────────────────
    property string  _dragAddr: ""
    property int     _dragSrcVdesk: 0
    property int     _dragDstVdesk: 0     // 0 = not over any cell
    property bool    _dragging: false
    property real    _ghostX: 0
    property real    _ghostY: 0
    property real    _ghostW: 80
    property real    _ghostH: 50

    // ── Keyboard focus index ──────────────────────────────────────────────────
    property int _focusedDesk: root.activeVdesk   // 1-9

    // ── Process: move window to pixel position ────────────────────────────────
    Process {
        id: _movePixelProc
        property string addr: ""
        property int px: 0
        property int py: 0
        command: ["hyprctl", "dispatch", "movewindowpixel",
                  "exact " + px + "," + py + ",address:" + addr]
        running: false
    }

    // ── Process: resize window ────────────────────────────────────────────────
    Process {
        id: _resizePixelProc
        property string addr: ""
        property int pw: 100
        property int ph: 100
        command: ["hyprctl", "dispatch", "resizewindowpixel",
                  "exact " + pw + "," + ph + ",address:" + addr]
        running: false
    }

    // ── Keyboard handler ──────────────────────────────────────────────────────
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Escape) {
            root.toggleRequested(); ev.accepted = true
        } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            // Focus the selected window (or activate focused desk)
            if (root.selectedWindowAddress !== "") {
                root.windowFocused(root.selectedWindowAddress, root.selectedWindowVdesk)
                root.toggleRequested()
            } else {
                root.vdeskActivated(root._focusedDesk)
                root.toggleRequested()
            }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Tab) {
            // Cycle focus through desks
            root._focusedDesk = (root._focusedDesk % 9) + 1
            ev.accepted = true
        } else if (ev.key === Qt.Key_Left) {
            if (ev.modifiers & Qt.ShiftModifier) {
                // Shift+Left: move selected window to adjacent vdesk
                if (root.selectedWindowAddress !== "") {
                    let target = _adjDesk(root.selectedWindowVdesk, -1, 0)
                    if (target >= 1 && target <= 9)
                        root.windowMoveRequested(root.selectedWindowAddress, target)
                }
            } else {
                root._focusedDesk = _adjDesk(root._focusedDesk, -1, 0)
            }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Right) {
            if (ev.modifiers & Qt.ShiftModifier) {
                if (root.selectedWindowAddress !== "") {
                    let target = _adjDesk(root.selectedWindowVdesk, 1, 0)
                    if (target >= 1 && target <= 9)
                        root.windowMoveRequested(root.selectedWindowAddress, target)
                }
            } else {
                root._focusedDesk = _adjDesk(root._focusedDesk, 1, 0)
            }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Up) {
            if (ev.modifiers & Qt.ShiftModifier) {
                if (root.selectedWindowAddress !== "") {
                    let target = _adjDesk(root.selectedWindowVdesk, 0, -1)
                    if (target >= 1 && target <= 9)
                        root.windowMoveRequested(root.selectedWindowAddress, target)
                }
            } else {
                root._focusedDesk = _adjDesk(root._focusedDesk, 0, -1)
            }
            ev.accepted = true
        } else if (ev.key === Qt.Key_Down) {
            if (ev.modifiers & Qt.ShiftModifier) {
                if (root.selectedWindowAddress !== "") {
                    let target = _adjDesk(root.selectedWindowVdesk, 0, 1)
                    if (target >= 1 && target <= 9)
                        root.windowMoveRequested(root.selectedWindowAddress, target)
                }
            } else {
                root._focusedDesk = _adjDesk(root._focusedDesk, 0, 1)
            }
            ev.accepted = true
        }
    }

    // Navigate the 3×3 grid: deskId 1-9, dx/dy in {-1,0,1}
    function _adjDesk(deskId, dx, dy) {
        let col = (deskId - 1) % 3
        let row = Math.floor((deskId - 1) / 3)
        let nc = col + dx
        let nr = row + dy
        if (nc < 0 || nc > 2 || nr < 0 || nr > 2) return deskId  // stay at edge
        return nr * 3 + nc + 1
    }

    // ── Background + grid ─────────────────────────────────────────────────────
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(Theme.background.r, Theme.background.g,
                       Theme.background.b, 0.88)

        // Click outside any cell → close
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.windowDeselected()
                root.toggleRequested()
            }
        }

        // ── 3×3 grid ──────────────────────────────────────────────────────────
        GridLayout {
            id: desksGrid
            anchors { fill: parent; margins: root._gap }
            columns: 3
            columnSpacing: root._gap
            rowSpacing: root._gap

            Repeater {
                model: 9

                // ── Workspace Cell ────────────────────────────────────────────
                delegate: Item {
                    id: cellItem
                    readonly property int deskId: index + 1
                    readonly property bool isActive:  deskId === root.activeVdesk
                    readonly property bool isFocused: deskId === root._focusedDesk
                    readonly property bool isDragTarget: deskId === root._dragDstVdesk

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Cell background
                    Rectangle {
                        id: cellBg
                        anchors.fill: parent
                        radius: Theme.radiusMedium
                        color: cellItem.isDragTarget ? Theme.hoverBackground
                             : cellItem.isActive     ? Qt.rgba(Theme.accent.r,
                                                               Theme.accent.g,
                                                               Theme.accent.b, 0.18)
                             : Theme.cellBackground
                        border.width: cellItem.isFocused ? 2 : 1
                        border.color: cellItem.isFocused  ? Theme.accent
                                    : cellItem.isActive   ? Theme.borderActive
                                    : Theme.cellBorder

                        Behavior on color        { ColorAnimation { duration: Theme.animFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                    }

                    // Desk number label
                    Text {
                        id: deskLabel
                        anchors { top: parent.top; left: parent.left
                                  topMargin: 4; leftMargin: 6 }
                        text: cellItem.deskId
                        color: cellItem.isActive ? Theme.accent : Theme.textSecondary
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.bold: cellItem.isActive
                    }

                    // Click on empty area of cell → activate that vdesk
                    MouseArea {
                        anchors.fill: parent
                        z: 0
                        onClicked: {
                            root.windowDeselected()
                            root.vdeskActivated(cellItem.deskId)
                            root.toggleRequested()
                        }
                    }

                    // ── Drop area for cross-vdesk window drag ─────────────────
                    DropArea {
                        anchors.fill: parent
                        keys: ["windowDrag"]
                        onEntered: root._dragDstVdesk = cellItem.deskId
                        onExited:  if (root._dragDstVdesk === cellItem.deskId)
                                       root._dragDstVdesk = 0
                        onDropped: drop => {
                            let srcVdesk = parseInt(drop.getDataAsString("sourceVdesk"))
                            let addr     = drop.getDataAsString("address")
                            if (srcVdesk !== cellItem.deskId && addr !== "") {
                                root.windowMoveRequested(addr, cellItem.deskId)
                            } else if (srcVdesk === cellItem.deskId && addr !== "") {
                                // Same-workspace fine-position move
                                let relX = drop.x
                                let relY = drop.y - root._headerH
                                let realX = Math.round(relX / root._scale)
                                let realY = Math.round(relY / root._scale)
                                _movePixelProc.addr = addr
                                _movePixelProc.px = realX
                                _movePixelProc.py = realY
                                _movePixelProc.running = true
                            }
                            root._dragging = false
                            root._dragDstVdesk = 0
                        }
                    }

                    // ── Window thumbnails (clipped to cell body) ──────────────
                    Item {
                        id: thumbArea
                        anchors {
                            top: deskLabel.bottom; topMargin: 2
                            left: parent.left; right: parent.right
                            bottom: parent.bottom
                            margins: 4
                        }
                        clip: true

                        Repeater {
                            model: root.windowsByVdesk[cellItem.deskId] || []

                            // ── Window Thumbnail ──────────────────────────────
                            delegate: Item {
                                id: thumb
                                readonly property var win: modelData
                                readonly property bool isSelected:
                                    win.address === root.selectedWindowAddress

                                // Proportional position & size inside cell
                                // win.x/y/width/height are real pixel coords;
                                // _scale maps them to overview-cell coords.
                                // Fallback: tile windows in a row if position
                                // data is absent (legacy script output).
                                x: (win.x !== undefined)
                                   ? win.x * root._scale
                                   : (index % 3) * (thumbArea.width / 3)
                                y: (win.y !== undefined)
                                   ? win.y * root._scale
                                   : Math.floor(index / 3) * (thumbArea.height / 3)
                                width:  (win.width  !== undefined)
                                        ? Math.max(win.width  * root._scale, root._minThumbW)
                                        : (thumbArea.width  * 0.7)
                                height: (win.height !== undefined)
                                        ? Math.max(win.height * root._scale, root._minThumbH)
                                        : (thumbArea.height * 0.7)
                                z: isSelected ? 10 : 1

                                // ── Drag support (Drag attached property) ─────
                                Drag.active:  thumbMouseArea.drag.active
                                Drag.keys:    ["windowDrag"]
                                Drag.mimeData: ({
                                    "address":     win.address,
                                    "sourceVdesk": cellItem.deskId.toString()
                                })
                                Drag.hotSpot.x: width  / 2
                                Drag.hotSpot.y: height / 2
                                Drag.dragType: Drag.Automatic

                                states: State {
                                    when: thumb.Drag.active
                                    PropertyChanges {
                                        target: thumb
                                        opacity: 0.4
                                    }
                                }

                                // Window colored rectangle
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusSmall
                                    color: thumb.isSelected
                                         ? Qt.rgba(Theme.accent.r, Theme.accent.g,
                                                   Theme.accent.b, 0.30)
                                         : Theme.backgroundAlt
                                    border.width: thumb.isSelected ? 2 : 1
                                    border.color: thumb.isSelected ? Theme.borderActive
                                                                   : Theme.borderNormal

                                    // Window title
                                    Text {
                                        anchors {
                                            left: parent.left; right: resizeHandle.left
                                            top: parent.top
                                            margins: 3
                                        }
                                        text: win.title || win.class || ""
                                        color: thumb.isSelected ? Theme.activeText
                                                                : Theme.textSecondary
                                        font.family: Theme.fontUI
                                        font.pixelSize: 7
                                        elide: Text.ElideRight
                                        clip: true
                                    }

                                    // ── Resize handle (bottom-right corner) ───
                                    Rectangle {
                                        id: resizeHandle
                                        width: 8; height: 8
                                        anchors { right: parent.right; bottom: parent.bottom }
                                        color: Theme.accent
                                        radius: 1
                                        z: 20

                                        MouseArea {
                                            id: resizeDragArea
                                            anchors.fill: parent
                                            cursorShape: Qt.SizeFDiagCursor
                                            drag.target: resizeHandle
                                            drag.axis:   Drag.XAndYAxis
                                            drag.minimumX: -thumb.width  + root._minThumbW
                                            drag.minimumY: -thumb.height + root._minThumbH
                                            drag.maximumX: thumbArea.width  - thumb.x - thumb.width
                                            drag.maximumY: thumbArea.height - thumb.y - thumb.height

                                            onReleased: {
                                                let newW = Math.max(root._minThumbW, thumb.width  + resizeHandle.x)
                                                let newH = Math.max(root._minThumbH, thumb.height + resizeHandle.y)
                                                let realW = Math.round(newW / root._scale)
                                                let realH = Math.round(newH / root._scale)
                                                _resizePixelProc.addr = win.address
                                                _resizePixelProc.pw   = realW
                                                _resizePixelProc.ph   = realH
                                                _resizePixelProc.running = true
                                                // Reset handle back to corner
                                                resizeHandle.x = 0
                                                resizeHandle.y = 0
                                            }
                                        }
                                    }
                                }

                                // ── Main interaction area ──────────────────────
                                MouseArea {
                                    id: thumbMouseArea
                                    anchors.fill: parent
                                    z: 10
                                    // Leave resize handle accessible
                                    drag.target: thumb
                                    drag.threshold: 6

                                    onClicked: {
                                        if (thumb.isSelected) {
                                            root.windowDeselected()
                                        } else {
                                            root.windowSelected(win.address, cellItem.deskId)
                                        }
                                    }
                                    onDoubleClicked: {
                                        root.windowFocused(win.address, cellItem.deskId)
                                        root.toggleRequested()
                                    }
                                    onPressed: {
                                        root._dragAddr     = win.address
                                        root._dragSrcVdesk = cellItem.deskId
                                    }
                                    onReleased: {
                                        // Drag.Automatic handles drop delivery automatically
                                        root._dragging = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
