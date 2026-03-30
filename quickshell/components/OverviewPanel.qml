import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."

// ═══════════════════════════════════════════════════════════
// OVERVIEW PANEL - 3x3 Virtual Desktop Grid with window management
// ═══════════════════════════════════════════════════════════

Variants {
    id: overviewRoot
    // Multi-monitor: show centred on every connected screen
    model: Quickshell.screens
    
    // Required bindings from parent
    required property bool visible
    required property int activeVdesk
    required property var windowsByVdesk
    required property string selectedWindowAddress
    required property int selectedWindowVdesk
    
    // Signals to parent
    signal toggleRequested()
    signal windowSelected(string address, int vdeskNum)
    signal windowDeselected()
    signal windowMoveRequested(string address, int targetVdesk)
    signal vdeskActivated(int vdeskNum)
    signal windowFocused(string address, int vdeskNum)
    
    PanelWindow {
        id: overviewPanel
        property var modelData
        screen: modelData
        
        // Keyboard navigation state
        property int selectedVdeskIndex: -1
        
        visible: overviewRoot.visible
        exclusionMode: ExclusionMode.Ignore
        
        anchors { top: true; left: true }
        margins { 
            top: (screen.height - implicitHeight) / 2
            left: (screen.width - implicitWidth) / 2 
        }
        
        implicitWidth: overviewGrid.width + 56
        implicitHeight: overviewGrid.height + 80
        color: "transparent"
        
        // Reset keyboard selection when opened
        onVisibleChanged: {
            if (visible) {
                selectedVdeskIndex = -1
                overviewPanel.forceActiveFocus()
            }
        }
        
        // Dışarı tıklayınca kapat
        MouseArea {
            anchors.fill: parent
            onClicked: overviewRoot.toggleRequested()
        }
        
        // ═══ KEYBOARD NAVIGATION ═══
        Keys.onPressed: (event) => {
            // Number keys 1-9: Direct VDESK jump
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                let vdesk = event.key - Qt.Key_0
                overviewRoot.vdeskActivated(vdesk)
                overviewRoot.toggleRequested()
                event.accepted = true
                return
            }
            
            // HJKL / Arrow navigation
            let col = selectedVdeskIndex % 3
            let row = Math.floor(selectedVdeskIndex / 3)
            
            if (selectedVdeskIndex < 0) {
                // First navigation, start from active vdesk
                selectedVdeskIndex = overviewRoot.activeVdesk - 1
                event.accepted = true
                return
            }
            
            switch (event.key) {
                case Qt.Key_H:
                case Qt.Key_Left:
                    col = (col + 2) % 3
                    break
                case Qt.Key_L:
                case Qt.Key_Right:
                    col = (col + 1) % 3
                    break
                case Qt.Key_K:
                case Qt.Key_Up:
                    row = (row + 2) % 3
                    break
                case Qt.Key_J:
                case Qt.Key_Down:
                    row = (row + 1) % 3
                    break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (selectedVdeskIndex >= 0) {
                        overviewRoot.vdeskActivated(selectedVdeskIndex + 1)
                        overviewRoot.toggleRequested()
                    }
                    event.accepted = true
                    return
            }
            
            selectedVdeskIndex = row * 3 + col
            event.accepted = true
        }
        
        // ═══ OUTER METALLIC FRAME ═══
        MetallicFrame {
            id: outerFrame
            anchors.fill: parent
            radius: 12
            showScrews: true
            screwSize: 8
            screwMargin: 10
            
            // ▓▓▓ INNER DISPLAY AREA ▓▓▓
            DisplayArea {
                id: innerDisplay
                anchors.fill: parent
                anchors.margins: 6
                radius: 8
                
                // ═══ HEADER BAR ═══
                HeaderBar {
                    id: overviewHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 44
                    radius: parent.radius
                    
                    title: "SYSTEM OVERVIEW"
                    subtitle: "VIRTUAL DESKTOP GRID"
                    iconSize: 22
                }
                
                // ═══ 3x3 GRID ═══
                Grid {
                    id: overviewGrid
                    anchors.top: overviewHeader.bottom
                    anchors.topMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    spacing: 10
                    
                    Repeater {
                        model: 9
                        
                        Rectangle {
                            id: vdeskCell
                            required property int index
                            readonly property int vdeskNum: index + 1
                            readonly property bool isActive: vdeskNum === overviewRoot.activeVdesk
                            readonly property bool isKeyboardSelected: index === overviewPanel.selectedVdeskIndex
                            readonly property var cellWindows: {
                                var vd = vdeskNum;
                                return (vd >= 1 && vd <= 9) ? (overviewRoot.windowsByVdesk[vd] || []) : [];
                            }
                            
                            width: 200
                            height: 140
                            radius: 6
                            
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: isActive ? Theme.lambdaDark : Theme.cellBackground }
                                GradientStop { position: 0.5; color: isActive ? Theme.lambda : Theme.backgroundPanel }
                                GradientStop { position: 1.0; color: isActive ? Theme.lambdaDark : Theme.background }
                            }
                            
                            // Keyboard selection highlight
                            border.width: isKeyboardSelected ? 3 : (isActive ? 2 : 1)
                            border.color: isKeyboardSelected ? Theme.lambdaLight : (isActive ? Theme.lambda : Theme.cellBorder)
                            
                            // Cell Header - CLICKABLE
                            Rectangle {
                                id: cellHeader
                                anchors.top: parent.top
                                width: parent.width
                                height: 26
                                radius: parent.radius
                                
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: vdeskCell.isActive ? Theme.lambdaDark : (headerMa.containsMouse ? Theme.hoverBackground : Theme.backgroundPanel) }
                                    GradientStop { position: 1.0; color: vdeskCell.isActive ? Theme.lambdaMid : (headerMa.containsMouse ? Theme.cellBackground : Theme.background) }
                                }
                                
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.radius
                                    color: vdeskCell.isActive ? Theme.lambdaMid : (headerMa.containsMouse ? Theme.cellBackground : Theme.background)
                                }
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "VDESK " + vdeskCell.vdeskNum + " [" + vdeskCell.cellWindows.length + "]"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: vdeskCell.isActive ? Theme.accentText : (headerMa.containsMouse ? Theme.lambda : Theme.textSecondary)
                                }
                                
                                // Header click - ALWAYS go to VDESK (navigation only)
                                MouseArea {
                                    id: headerMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    
                                    onClicked: {
                                        // Always navigate to this VDESK
                                        overviewRoot.vdeskActivated(vdeskCell.vdeskNum)
                                        overviewRoot.toggleRequested()
                                    }
                                }
                            }
                            
                            // ═══ WINDOW LIST AREA ═══
                            Rectangle {
                                id: windowListArea
                                anchors.top: cellHeader.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                color: "transparent"
                                
                                // Drop zone highlight
                                MouseArea {
                                    id: dropZone
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        radius: 4
                                        color: (overviewRoot.selectedWindowAddress && 
                                               overviewRoot.selectedWindowVdesk !== vdeskCell.vdeskNum && 
                                               dropZone.containsMouse) ? Theme.hoverBackground : "transparent"
                                        opacity: 0.5
                                    }
                                    
                                    onClicked: {
                                        if (overviewRoot.selectedWindowAddress && overviewRoot.selectedWindowVdesk !== vdeskCell.vdeskNum) {
                                            overviewRoot.windowMoveRequested(overviewRoot.selectedWindowAddress, vdeskCell.vdeskNum)
                                        }
                                    }
                                }
                                
                                // Scrollable window list
                                Flickable {
                                    id: windowFlickable
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    
                                    contentHeight: windowColumn.height
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: false
                                    
                                    Column {
                                        id: windowColumn
                                        width: windowFlickable.width
                                        spacing: 2
                                        
                                        Repeater {
                                            model: vdeskCell.cellWindows
                                            
                                            Rectangle {
                                                id: winItem
                                                required property var modelData
                                                required property int index
                                                property bool isSelected: overviewRoot.selectedWindowAddress === modelData.address
                                                
                                                width: windowColumn.width
                                                height: 20
                                                radius: 3
                                                
                                                color: isSelected ? Theme.lambda : (winMa.containsMouse ? Theme.hoverBackground : "transparent")
                                                border.width: isSelected ? 1 : 0
                                                border.color: Theme.lambdaLight
                                                
                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6
                                                    anchors.rightMargin: 4
                                                    spacing: 6
                                                    
                                                    Text {
                                                        text: (modelData.class || "?").toLowerCase()
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: winItem.isSelected ? Theme.accentText : (vdeskCell.isActive ? Theme.lambda : Theme.text)
                                                        width: 55
                                                        elide: Text.ElideRight
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    
                                                    Text {
                                                        text: (modelData.title || "Untitled")
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 9
                                                        color: winItem.isSelected ? Theme.accentText : (vdeskCell.isActive ? Theme.lambdaDark : Theme.textSecondary)
                                                        width: parent.width - 65
                                                        elide: Text.ElideRight
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                                
                                                MouseArea {
                                                    id: winMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    
                                                    onClicked: {
                                                        if (overviewRoot.selectedWindowAddress === modelData.address) {
                                                            overviewRoot.windowDeselected()
                                                        } else {
                                                            overviewRoot.windowSelected(modelData.address, vdeskCell.vdeskNum)
                                                        }
                                                    }
                                                    
                                                    onDoubleClicked: {
                                                        overviewRoot.windowFocused(modelData.address, vdeskCell.vdeskNum)
                                                        overviewRoot.toggleRequested()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Scroll indicator
                                    Rectangle {
                                        visible: windowFlickable.contentHeight > windowFlickable.height
                                        anchors.right: parent.right
                                        anchors.rightMargin: -2
                                        y: windowFlickable.contentY / windowFlickable.contentHeight * (windowFlickable.height - height)
                                        width: 3
                                        height: Math.max(20, windowFlickable.height * (windowFlickable.height / windowFlickable.contentHeight))
                                        radius: 1.5
                                        color: vdeskCell.isActive ? Theme.lambda : Theme.lambdaDark
                                        opacity: 0.6
                                    }
                                }
                                
                                // Scroll wheel handler
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    
                                    onWheel: (wheel) => {
                                        windowFlickable.contentY = Math.max(0, 
                                            Math.min(windowFlickable.contentHeight - windowFlickable.height,
                                                windowFlickable.contentY - wheel.angleDelta.y * 0.5))
                                        wheel.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }
                
                // ═══ FOOTER ═══
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Theme.tagline
                    font.family: Theme.fontMono
                    font.pixelSize: 7
                    font.letterSpacing: 1
                    color: Theme.textMuted
                }
            }
        }
        
        // ═══ KEYBOARD SHORTCUTS ═══
        Shortcut { sequence: "Escape"; onActivated: overviewRoot.toggleRequested() }
    }
}
