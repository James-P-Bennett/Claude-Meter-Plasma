import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Latest payload from `claude-usage --json`. Starts in a neutral state.
    property var usage: ({ "status": "init", "windows": [], "max_pct": 0 })

    // Ticks so countdowns and "updated N minutes ago" stay current between polls.
    property real now: Date.now()

    readonly property bool hasData: (usage.status === "ok" || usage.status === "stale")
                                    && usage.windows && usage.windows.length > 0

    // Which readouts the compact (panel) view shows, per the config toggles.
    readonly property var compactItems: {
        if (!hasData) return []
        var cfg = Plasmoid.configuration
        var bars = usage.limits || (usage.weekly ? usage.weekly.bars : [])
        var items = []
        if (cfg.showSession && usage.session)
            items.push({ "pct": usage.session.pct })
        for (var i = 0; i < bars.length; i++) {
            var b = bars[i]
            if (b.key === "seven_day" && cfg.showWeekly)
                items.push({ "pct": b.pct })
            else if (b.group === "weekly" && b.key !== "seven_day" && cfg.showScoped)
                items.push({ "pct": b.pct })
        }
        return items
    }

    function colorFor(pct) {
        if (pct >= 95) return Kirigami.Theme.negativeTextColor
        if (pct >= 80) return Kirigami.Theme.neutralTextColor
        if (pct >= 50) return Kirigami.Theme.highlightColor
        return Kirigami.Theme.positiveTextColor
    }

    function statusColor() {
        if (usage.status === "auth" || usage.status === "error") return Kirigami.Theme.disabledTextColor
        return colorFor(usage.max_pct || 0)
    }

    function command() {
        var c = Plasmoid.configuration.scriptPath + " --json"
        if (Plasmoid.configuration.notify) {
            c += " --notify --thresholds " + Plasmoid.configuration.thresholdWarn
                 + "," + Plasmoid.configuration.thresholdCrit
        }
        return c
    }

    function refresh() {
        execDs.exec(command())
    }

    // Opportunistic refresh (popup/window opening): skip if the reading is
    // fresh, since back-to-back calls trip the endpoint's 429.
    function refreshIfOld() {
        if (!usage.fetched_at || Date.now() - usage.fetched_at * 1000 > 30000) refresh()
    }

    function openWindow() {
        root.expanded = false
        refreshIfOld()
        usageWindow.show()
        usageWindow.raise()
        usageWindow.requestActivate()
    }

    toolTipMainText: i18n("Claude usage")
    toolTipSubText: {
        if (hasData) {
            var parts = []
            for (var i = 0; i < usage.windows.length; i++) {
                var w = usage.windows[i]
                var line = w.label + ": " + Math.round(w.pct) + "%"
                if (w.resets_in) line += "  (resets in " + w.resets_in + ")"
                parts.push(line)
            }
            var s = parts.join("\n")
            if (usage.status === "stale") s += "\n" + i18n("(showing last reading: %1)", usage.stale_reason || "offline")
            return s
        }
        if (usage.status === "auth") return usage.message || i18n("Sign-in needed")
        if (usage.status === "init") return i18n("Loading…")
        return usage.message || i18n("No data")
    }

    preferredRepresentation: compactRepresentation

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Open Usage Window")
            icon.name: "view-fullscreen"
            onTriggered: root.openWindow()
        }
    ]

    P5Support.DataSource {
        id: execDs
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            var out = ("" + (data["stdout"] || "")).trim()
            if (out.length === 0) return
            try {
                root.usage = JSON.parse(out)
            } catch (e) {
                root.usage = { "status": "error", "message": "parse error", "windows": [], "max_pct": 0 }
            }
            root.now = Date.now()
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    Timer {
        interval: Math.max(60, Plasmoid.configuration.refreshSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Connections {
        target: Plasmoid.configuration
        function onNotifyChanged() { root.refresh() }
        function onScriptPathChanged() { root.refresh() }
    }

    // ---- Standalone window -----------------------------------------------
    // A normal top-level window (no transient parent) so KWin treats it like
    // any app window: resizable, snappable, tileable, shows in the task bar.
    Window {
        id: usageWindow
        title: i18n("Claude Usage")
        transientParent: null
        flags: Qt.Window
        visible: false
        width: Plasmoid.configuration.windowWidth
        height: Plasmoid.configuration.windowHeight
        minimumWidth: Kirigami.Units.gridUnit * 20
        minimumHeight: Kirigami.Units.gridUnit * 16

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor

        onClosing: {
            Plasmoid.configuration.windowWidth = width
            Plasmoid.configuration.windowHeight = height
        }

        QQC2.ScrollView {
            id: windowScroll
            anchors.fill: parent
            contentWidth: availableWidth
            contentHeight: windowView.implicitHeight + Kirigami.Units.gridUnit * 3

            UsageView {
                id: windowView
                readonly property real margin: Kirigami.Units.gridUnit * 1.5
                width: Math.min(windowScroll.availableWidth - margin * 2, Kirigami.Units.gridUnit * 56)
                x: (windowScroll.availableWidth - width) / 2
                y: margin
                detailed: true
                usage: root.usage
                now: root.now
                onRefreshRequested: root.refresh()
            }
        }

        Shortcut {
            sequences: [StandardKey.Close, "Escape"]
            onActivated: usageWindow.close()
        }
        Shortcut {
            sequences: [StandardKey.Refresh]
            onActivated: root.refresh()
        }
    }

    // ---- Compact (panel) representation ----------------------------------
    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.openWindow()
                return
            }
            // Opening the popup pulls a fresh reading; closing doesn't need one.
            if (!root.expanded) root.refreshIfOld()
            root.expanded = !root.expanded
        }

        Layout.minimumWidth: contentLoader.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth

        Loader {
            id: contentLoader
            anchors.centerIn: parent
            sourceComponent: (root.hasData && root.compactItems.length > 0) ? readout : placeholder
        }

        Component {
            id: placeholder
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    width: Kirigami.Units.iconSizes.small * 0.5
                    height: width
                    radius: width / 2
                    color: root.statusColor()
                }
                PlasmaComponents.Label {
                    text: root.usage.status === "auth" ? i18n("auth")
                          : root.usage.status === "init" ? "…" : "—"
                    color: Kirigami.Theme.disabledTextColor
                }
            }
        }

        Component {
            id: readout
            RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: root.compactItems
                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        opacity: root.usage.status === "stale" ? 0.55 : 1.0
                        text: Math.round(modelData.pct) + "%"
                        font.bold: true
                        color: root.colorFor(modelData.pct)
                    }
                }
            }
        }
    }

    // ---- Full (popup) representation -------------------------------------
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: popupView.implicitHeight + Kirigami.Units.largeSpacing * 2

        UsageView {
            id: popupView
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            usage: root.usage
            now: root.now
            showExpand: true
            onRefreshRequested: root.refresh()
            onExpandRequested: root.openWindow()
        }
    }
}
