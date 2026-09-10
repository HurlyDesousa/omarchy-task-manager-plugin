// Task Manager panel — Weather KeyboardPanel pattern (no scrim, Color.popups.border).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "sw.art.task-manager"
    ipcTarget: "sw.art.task-manager"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    property bool showSettings: false
    property bool expanded: false
    property string filterText: ""
    property int selectedPid: -1
    property var snapshot: ({})
    property var prefs: ({})
    property var processModel: []
    property bool pendingExpandApply: false

    readonly property string pluginDir: {
        var s = String(Qt.resolvedUrl("."))
        if (s.indexOf("file://") === 0)
            s = decodeURIComponent(s.slice(7))
        if (s.length > 1 && s.charAt(s.length - 1) === "/")
            s = s.slice(0, s.length - 1)
        return s
    }
    readonly property string homeBin: Quickshell.env("HOME") + "/.local/bin/omarchy-task-manager"
    property string taskManagerBin: homeBin
    readonly property string emDash: "\u2014"
    readonly property int refreshMs: {
        var ms = Number(prefs.refresh_ms)
        return (ms >= 500 && ms <= 10000) ? ms : 1000
    }

    function open() {
        root.controller.show()
        root.pendingExpandApply = true
        loadPrefs()
    }

    function openFromHotkey() {
        root.open()
    }

    function close() {
        if (root.expanded && root.prefs.remember_expand === true)
            savePref("last_compact", false)
        else if (!root.expanded && root.prefs.remember_expand === true)
            savePref("last_compact", true)
        root.showSettings = false
        root.controller.hide()
    }

    function toggle() {
        if (root.opened) root.close()
        else root.openFromHotkey()
    }

    function refresh() {
        statsProc.running = true
    }

    function loadPrefs() {
        prefsProc.running = true
    }

    function applyStartupExpand() {
        var startCompact = prefs.start_compact === true
        var remember = prefs.remember_expand !== false
        var lastCompact = prefs.last_compact !== false
        root.expanded = !(startCompact || (remember && lastCompact))
    }

    function savePref(key, value) {
        var v = value
        if (typeof value === "boolean") v = value ? "true" : "false"
        savePrefProc.command = [root.taskManagerBin, "prefs-set", key, String(v)]
        savePrefProc.running = true
    }

    function rebuildProcessModel() {
        var rows = snapshot.processes || []
        var needle = filterText.trim().toLowerCase()
        if (!needle) {
            processModel = rows
            return
        }
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            var name = String(row.name || "").toLowerCase()
            var pid = String(row.pid || "")
            if (name.indexOf(needle) >= 0 || pid.indexOf(needle) >= 0)
                out.push(row)
        }
        processModel = out
    }

    onSnapshotChanged: rebuildProcessModel()
    onFilterTextChanged: rebuildProcessModel()
    onExpandedChanged: if (root.opened) root.refresh()

    function statText(value, suffix) {
        if (value === null || value === undefined) return root.emDash
        return String(value) + (suffix || "")
    }

    function pctFraction(value) {
        var n = Number(value)
        if (!isFinite(n)) return 0
        return Math.max(0, Math.min(1, n / 100))
    }

    FileView {
        path: root.pluginDir + "/omarchy-task-manager"
        printErrors: false
        onLoaded: root.taskManagerBin = path
    }

    Process {
        id: statsProc
        stdout: SplitParser {
            onRead: function(line) {
                var l = line.trim()
                if (!l) return
                try { root.snapshot = JSON.parse(l) } catch (e) {}
            }
        }
        command: [root.taskManagerBin, "snapshot"].concat(root.expanded ? [] : ["--no-processes"])
    }

    Process {
        id: prefsProc
        stdout: SplitParser {
            onRead: function(line) {
                var l = line.trim()
                if (!l) return
                try { root.prefs = JSON.parse(l) } catch (e) { return }
                if (root.pendingExpandApply) {
                    root.pendingExpandApply = false
                    root.applyStartupExpand()
                }
            }
        }
        command: [root.taskManagerBin, "prefs-get"]
    }

    Process {
        id: savePrefProc
        onRunningChanged: if (!running) prefsProc.running = true
    }

    Process {
        id: killProc
        onRunningChanged: if (!running) refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: root.refreshMs
        repeat: true
        running: root.opened
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onRefreshMsChanged: if (root.opened) refreshTimer.restart()

    IpcHandler {
        target: root.ipcTarget
        function open(): void { root.openFromHotkey() }
        function close(): void { root.close() }
        function show(): void { root.openFromHotkey() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }
        function opened(): string { return root.opened ? "true" : "false" }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(520))
        contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(560))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: searchField.activeFocus
            onCloseRequested: root.close()
            onTabRequested: function(direction) {
                if (root.hostWidget && root.hostWidget.switchPanel)
                    root.hostWidget.switchPanel(direction)
                else if (typeof root.switchPanel === "function")
                    root.switchPanel(direction)
            }

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: width
                contentHeight: mainColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: mainColumn
                    width: flick.width
                    spacing: Style.space(10)

                    // Header
                    RowLayout {
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        spacing: Style.space(8)

                        Label {
                            text: "Task Manager"
                            font.pixelSize: Style.font.title
                            font.bold: true
                            color: root.bar.foreground
                            font.family: root.bar.fontFamily
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 26; height: 26; radius: Style.cornerRadius
                            color: root.showSettings
                                ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                            Label {
                                anchors.centerIn: parent
                                text: "󰒓"
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                                color: root.showSettings
                                    ? Style.hoverStateColor(root.bar.foreground, Color.accent)
                                    : Qt.darker(root.bar.foreground, 1.4)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showSettings = !root.showSettings
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Style.spacing.hairline
                        color: root.bar.foreground
                        opacity: 0.12
                    }

                    // Settings view
                    Column {
                        visible: root.showSettings
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        spacing: Style.space(10)

                        Label {
                            text: "Startup"
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            font.letterSpacing: 1
                        }

                        Toggle {
                            width: parent.width
                            label: "Start compact"
                            checked: root.prefs.start_compact === true
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onClicked: root.savePref("start_compact", root.prefs.start_compact !== true)
                        }
                        Toggle {
                            width: parent.width
                            label: "Remember last state"
                            checked: root.prefs.remember_expand !== false
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onClicked: root.savePref("remember_expand", root.prefs.remember_expand === false)
                        }

                        Label {
                            text: "Refresh"
                            color: Qt.darker(root.bar.foreground, 1.4)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                            font.letterSpacing: 1
                            Layout.topMargin: Style.space(4)
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Style.space(8)
                            Label {
                                text: "Interval"
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.body
                                Layout.fillWidth: true
                            }
                            ComboBox {
                                id: refreshBox
                                model: ["500 ms", "1 s", "2 s", "5 s"]
                                currentIndex: {
                                    var ms = root.refreshMs
                                    if (ms <= 500) return 0
                                    if (ms <= 1000) return 1
                                    if (ms <= 2000) return 2
                                    return 3
                                }
                                onActivated: function(idx) {
                                    var vals = [500, 1000, 2000, 5000]
                                    root.savePref("refresh_ms", vals[idx])
                                }
                            }
                        }

                        Label {
                            text: "Version 0.5.5-43"
                            color: Qt.darker(root.bar.foreground, 1.5)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }
                    }

                    // Main stats view
                    Column {
                        visible: !root.showSettings
                        width: parent.width - Style.space(32)
                        x: Style.space(16)
                        spacing: Style.space(8)

                        StatRow {
                            label: "CPU"
                            valueText: statText(root.snapshot.cpu ? root.snapshot.cpu.pct : null, "%")
                            fraction: pctFraction(root.snapshot.cpu ? root.snapshot.cpu.pct : 0)
                            detailText: statText(root.snapshot.cpu ? root.snapshot.cpu.temp : null, "\u00b0C")
                            bar: root.bar
                        }
                        StatRow {
                            label: "GPU"
                            valueText: statText(root.snapshot.gpu ? root.snapshot.gpu.pct : null, "%")
                            fraction: pctFraction(root.snapshot.gpu ? root.snapshot.gpu.pct : 0)
                            detailText: statText(root.snapshot.gpu ? root.snapshot.gpu.temp : null, "\u00b0C")
                            bar: root.bar
                        }
                        RamStatRow {
                            label: "RAM"
                            valueText: statText(root.snapshot.ram ? root.snapshot.ram.pct : null, "%")
                            fraction: pctFraction(root.snapshot.ram ? root.snapshot.ram.pct : 0)
                            detailText: root.snapshot.ram ? root.snapshot.ram.detail : root.emDash
                            bar: root.bar
                        }

                        Flow {
                            width: parent.width
                            spacing: Style.space(6)
                            Repeater {
                                model: root.snapshot.cpu ? (root.snapshot.cpu.cores || []) : []
                                delegate: Row {
                                    required property var modelData
                                    spacing: Style.space(4)
                                    Label {
                                        text: String(modelData.id)
                                        width: Style.space(18)
                                        horizontalAlignment: Text.AlignRight
                                        color: Qt.darker(root.bar.foreground, 1.4)
                                        font.family: root.bar.fontFamily
                                        font.pixelSize: Style.font.caption
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    MeterBar {
                                        width: Style.space(44)
                                        fraction: pctFraction(modelData.pct)
                                        bar: root.bar
                                    }
                                }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Style.space(10)
                            FanMeter {
                                side: "Fan L"
                                fan: root.snapshot.fans ? root.snapshot.fans.left : null
                                bar: root.bar
                                Layout.fillWidth: true
                            }
                            FanMeter {
                                side: "Fan R"
                                fan: root.snapshot.fans ? root.snapshot.fans.right : null
                                bar: root.bar
                                Layout.fillWidth: true
                            }
                            Row {
                                spacing: Style.space(4)
                                Label {
                                    text: "Uptime"
                                    color: Qt.darker(root.bar.foreground, 1.4)
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                }
                                Label {
                                    text: root.snapshot.uptime || root.emDash
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: Style.space(8)
                            Rectangle {
                                Layout.preferredWidth: Style.space(110)
                                Layout.preferredHeight: Style.space(28)
                                radius: Style.cornerRadius
                                color: Style.hoverFillFor(root.bar.foreground, Color.accent)
                                Label {
                                    anchors.centerIn: parent
                                    text: root.expanded ? "Processes \u25b4" : "Processes \u25be"
                                    color: root.bar.foreground
                                    font.family: root.bar.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.expanded = !root.expanded
                                }
                            }
                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Filter by name or PID"
                                text: root.filterText
                                color: root.bar.foreground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                onTextChanged: root.filterText = text
                                background: Rectangle {
                                    color: Color.popups.background
                                    border.color: Color.popups.border
                                    border.width: 1
                                    radius: Style.cornerRadius
                                }
                            }
                        }

                        Rectangle {
                            visible: root.expanded
                            width: parent.width
                            height: Style.space(220)
                            color: "transparent"
                            border.color: Color.popups.border
                            border.width: 1
                            radius: Style.cornerRadius
                            clip: true

                            Column {
                                anchors.fill: parent
                                anchors.margins: Style.space(4)
                                spacing: 0

                                Row {
                                    width: parent.width
                                    spacing: Style.space(4)
                                    Repeater {
                                        model: ["Name", "PID", "CPU %", "Memory"]
                                        delegate: Label {
                                            required property string modelData
                                            required property int index
                                            width: index === 0 ? parent.width * 0.42
                                                : index === 1 ? parent.width * 0.14
                                                : index === 2 ? parent.width * 0.18
                                                : parent.width * 0.22
                                            text: modelData
                                            color: Qt.darker(root.bar.foreground, 1.3)
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.caption
                                            font.bold: true
                                        }
                                    }
                                }

                                ListView {
                                    id: procList
                                    width: parent.width
                                    height: parent.height - Style.space(36)
                                    clip: true
                                    model: root.processModel
                                    currentIndex: -1
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: procList.width
                                        height: Style.space(26)
                                        color: procList.currentIndex === index
                                            ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: Style.space(2)
                                            spacing: Style.space(4)
                                            Label {
                                                width: parent.width * 0.42
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                            }
                                            Label {
                                                width: parent.width * 0.14
                                                text: String(modelData.pid)
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                            }
                                            Label {
                                                width: parent.width * 0.18
                                                text: modelData.cpu_txt
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                            }
                                            Label {
                                                width: parent.width * 0.22
                                                text: modelData.rss_txt
                                                color: root.bar.foreground
                                                font.family: root.bar.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                procList.currentIndex = index
                                                root.selectedPid = modelData.pid
                                            }
                                            onDoubleClicked: {
                                                procList.currentIndex = index
                                                root.selectedPid = modelData.pid
                                            }
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: Style.space(28)
                                    layoutDirection: Qt.RightToLeft
                                    spacing: Style.space(8)
                                    Rectangle {
                                        width: Style.space(100)
                                        height: parent.height
                                        radius: Style.cornerRadius
                                        opacity: root.selectedPid > 0 ? 1.0 : 0.45
                                        color: Style.hoverFillFor(root.bar.foreground, Color.urgent)
                                        Label {
                                            anchors.centerIn: parent
                                            text: "End process"
                                            color: root.bar.foreground
                                            font.family: root.bar.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: root.selectedPid > 0
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                killProc.command = [root.taskManagerBin, "kill", String(root.selectedPid)]
                                                killProc.running = true
                                                root.selectedPid = -1
                                                procList.currentIndex = -1
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
    }

    component MeterBar: Item {
        property real fraction: 0
        property var bar
        height: Style.space(6)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.darker(bar.foreground, 2.2)
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, fraction))
                radius: parent.radius
                color: Color.accent
            }
        }
    }

    component StatRow: RowLayout {
        property string label
        property string valueText
        property real fraction
        property string detailText
        property var bar
        width: parent.width
        spacing: Style.space(8)
        Label {
            text: label
            Layout.preferredWidth: Style.space(36)
            color: Qt.darker(bar.foreground, 1.4)
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        Label {
            text: valueText
            Layout.preferredWidth: Style.space(44)
            Layout.maximumWidth: Style.space(44)
            horizontalAlignment: Text.AlignRight
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        MeterBar {
            Layout.fillWidth: true
            fraction: parent.fraction
            bar: parent.bar
        }
        Label {
            text: detailText
            Layout.preferredWidth: Style.space(72)
            horizontalAlignment: Text.AlignRight
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
    }

    component RamStatRow: RowLayout {
        property string label
        property string valueText
        property real fraction
        property string detailText
        property var bar
        width: parent.width
        spacing: Style.space(6)
        Label {
            text: label
            Layout.preferredWidth: Style.space(36)
            Layout.maximumWidth: Style.space(36)
            color: Qt.darker(bar.foreground, 1.4)
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        Label {
            text: valueText
            Layout.preferredWidth: Style.space(44)
            Layout.maximumWidth: Style.space(44)
            Layout.leftMargin: Style.space(2)
            horizontalAlignment: Text.AlignRight
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        MeterBar {
            Layout.fillWidth: true
            Layout.minimumWidth: Style.space(48)
            fraction: parent.fraction
            bar: parent.bar
        }
        Label {
            text: detailText
            Layout.preferredWidth: Style.space(104)
            Layout.minimumWidth: Style.space(104)
            Layout.maximumWidth: Style.space(104)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
    }

    component FanMeter: RowLayout {
        property string side
        property var fan
        property var bar
        spacing: Style.space(4)
        Label {
            text: side
            color: Qt.darker(bar.foreground, 1.4)
            font.family: bar.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        MeterBar {
            Layout.fillWidth: true
            fraction: fan ? fan.fraction : 0
            bar: parent.bar
        }
        Label {
            text: fan ? fan.text : "\u2014"
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.caption
        }
    }

}
