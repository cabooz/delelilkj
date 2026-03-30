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
    
    // --- STATE YÖNETİMİ ---
    property int activeVdesk: 1
    
    // Overview State
    property bool overviewVisible: false
    property var allWindows: []
    property var windowsByVdesk: ({})  // Pre-computed: {1: [...], 2: [...], ...}
    property string selectedWindowAddress: ""
    property int selectedWindowVdesk: 0
    
    // allWindows değiştiğinde bir kez grupla (O(n) yerine O(n×9))
    onAllWindowsChanged: {
        var grouped = {}
        for (var i = 1; i <= 9; i++) grouped[i] = []
        allWindows.forEach(w => { if (w.vdesk >= 1 && w.vdesk <= 9) grouped[w.vdesk].push(w) })
        windowsByVdesk = grouped
    }
    
    // --- IPC & EVENTS ---
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Vdesk değişimi
            if (event.name === "vdesk") {
                let num = parseInt(event.data)
                if (num >= 1 && num <= 9) root.activeVdesk = num
            }
            // Pencere olayları (Refresh tetikler)
            if (event.name === "openwindow" || event.name === "closewindow" || 
                event.name === "movewindow" || event.name === "workspace") {
                stateTimer.restart()
                if (root.overviewVisible) {
                    allWindowsProcess.start()
                }
            }
            // Özel toggle eventi
            if (event.name === "custom" && event.data === "toggleOverview") {
                root.toggleOverview()
            }
        }
    }
    
    function toggleOverview() {
        root.overviewVisible = !root.overviewVisible
        if (root.overviewVisible) {
            // [FIX] Her açılışta seçimi temizle ki yanlışlıkla taşıma olmasın
            root.selectedWindowAddress = ""
            root.selectedWindowVdesk = 0
            
            allWindowsProcess.start()
            stateProcess.running = true
        }
    }
    
    // Kısayol Tanımı
    GlobalShortcut {
        name: "toggleOverview"
        description: "Toggle Steam Overview"
        onPressed: root.toggleOverview()
    }
    
    // Debounce Timer (Event spam'ini önler)
    Timer {
        id: stateTimer
        interval: 200
        onTriggered: stateProcess.running = true
    }
    
    // --- PROCESSLER ---
    
    // Başlangıçta aktif vdesk'i bul
    Process {
        id: initProcess
        command: ["sh", "-c", "hyprctl printdesk | grep -oP 'desk \\K\\d+' | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                let num = parseInt(data.trim())
                if (num >= 1 && num <= 9) root.activeVdesk = num
            }
        }
    }
    
    // [FIX] Buffer Yönetimi İyileştirilmiş Window Fetcher
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
                    console.log("Parse error:", e)
                    root.allWindows = []
                }
            }
            buffer = ""
        }
        
        function start() {
            buffer = ""  // Process başlamadan önce temizle
            running = true
        }
    }
    
    // Pencere Taşıma İşlemi
    Process {
        id: moveToVdeskProcess
        property string targetAddress: ""
        property int targetVdesk: 1
        command: ["hyprctl", "dispatch", "movetodesksilent", targetVdesk + ",address:" + targetAddress]
        running: false
        onRunningChanged: {
            if (!running) {
                // [FIX] Manuel refresh kaldırıldı (Hyprland event'i zaten yapacak)
                console.log("Move completed: " + targetAddress + " -> " + targetVdesk)
                
                // [FIX] Taşıma bitti, seçimi sıfırla
                root.selectedWindowAddress = ""
                root.selectedWindowVdesk = 0
            }
        }
    }
    
    // Yardımcı Fonksiyonlar
    function moveWindowToVdesk(address, vdesk) {
        moveToVdeskProcess.targetAddress = address
        moveToVdeskProcess.targetVdesk = vdesk
        moveToVdeskProcess.running = true
    }
    
    function isPopulated(vdeskNum) { return (windowsByVdesk[vdeskNum] || []).length > 0 }
    
    
    // ==========================================================
    // UI: OVERVIEW (3x3 GRID) - Modular Component
    // ==========================================================
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
        onVdeskActivated: (vdeskNum) => Hyprland.dispatch("vdesk " + vdeskNum)
        onWindowFocused: (address, vdeskNum) => {
            Hyprland.dispatch("vdesk " + vdeskNum)
            Hyprland.dispatch("focuswindow address:" + address)
        }
    }

    HevControl {}
}
