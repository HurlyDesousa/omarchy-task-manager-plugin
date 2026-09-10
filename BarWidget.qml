import QtQuick
import qs.Commons
import qs.Ui

// Weather bar-widget pattern: Loader → Panel.qml, injectPanel, togglePanel.
// Hit area constrained to icon slot (no anchors.fill on BarIconButton).
// Panel is created on first open so the shell does not compile it at login.
BarWidget {
    id: root
    moduleName: "sw.art.task-manager"

    property string pendingPanelAction: ""

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    function runPanelAction(action) {
        if (!action)
            return
        if (!panelLoader.item) {
            root.pendingPanelAction = action
            panelLoader.active = true
            return
        }
        var item = panelLoader.item
        if (action === "toggle" && item.toggle) item.toggle()
        else if (action === "open" && item.openFromHotkey) item.openFromHotkey()
        else if (action === "close" && item.close) item.close()
        else if (action === "closeForPopoutSwitch" && item.closeForPopoutSwitch)
            item.closeForPopoutSwitch()
    }

    function togglePanel() {
        root.runPanelAction("toggle")
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root, direction)
        return false
    }

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() {
        root.runPanelAction("open")
    }

    function close() {
        if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
    }

    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    width: button.implicitWidth
    height: button.implicitHeight
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            var action = root.pendingPanelAction
            root.pendingPanelAction = ""
            if (action)
                Qt.callLater(function() { root.runPanelAction(action) })
        }
    }

    BarIconButton {
        id: button
        bar: root.bar
        text: "󰓅"
        tooltipText: "Task Manager"
        onPressed: function(b) {
            if (b !== Qt.RightButton) {
                if (root.opened && panelLoader.item) panelLoader.item.showSettings = false
                root.togglePanel()
            }
        }
    }
}
