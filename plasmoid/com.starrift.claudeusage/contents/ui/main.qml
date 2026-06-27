import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Latest payload from `claude-usage --json`. Starts in a neutral state.
    property var usage: ({ "status": "init", "windows": [], "max_pct": 0 })

    readonly property bool hasData: (usage.status === "ok" || usage.status === "stale")
                                    && usage.windows && usage.windows.length > 0

    // Which readouts the compact (panel) view shows, per the config toggles.
    // Each item is { label, pct }. Weekly model bars are looked up by key.
    readonly property var compactItems: {
        if (!hasData) return []
        var cfg = Plasmoid.configuration
        var items = []
        function weeklyBar(key) {
            if (!usage.weekly || !usage.weekly.bars) return null
            for (var i = 0; i < usage.weekly.bars.length; i++)
                if (usage.weekly.bars[i].key === key) return usage.weekly.bars[i]
            return null
        }
        if (cfg.showSession && usage.session)
            items.push({ "label": hoursLeftLabel(usage.session.resets_at), "pct": usage.session.pct })
        var picks = [["showWeekly", "seven_day", "Week"],
                     ["showSonnet", "seven_day_sonnet", "Son"],
                     ["showOpus", "seven_day_opus", "Opus"]]
        for (var p = 0; p < picks.length; p++) {
            if (!cfg[picks[p][0]]) continue
            var b = weeklyBar(picks[p][1])
            if (b) items.push({ "label": picks[p][2], "pct": b.pct })
        }
        return items
    }

    // Time until the 5h session window resets, e.g. "2h23m". Falls back to
    // "5h" if resets_at is missing or unparseable.
    function hoursLeftLabel(resetsAt) {
        if (!resetsAt) return "5h"
        var reset = new Date(resetsAt).getTime()
        if (isNaN(reset)) return "5h"
        var mins = Math.floor((reset - Date.now()) / 60000)
        if (mins < 0) mins = 0
        var h = Math.floor(mins / 60)
        var m = mins % 60
        if (h === 0) return m + "m"
        return h + "h" + (m < 10 ? "0" + m : m) + "m"
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

    function planLabel() {
        var p = usage.plan ? String(usage.plan) : ""
        if (!p) return ""
        var name = p.charAt(0).toUpperCase() + p.slice(1)
        var t = usage.tier ? String(usage.tier) : ""
        if (t.indexOf("20x") !== -1) return name + " 20×"
        if (t.indexOf("5x") !== -1) return name + " 5×"
        return name
    }

    function updatedLabel() {
        if (!usage.fetched_at) return ""
        var d = new Date(usage.fetched_at * 1000)
        return d.toLocaleTimeString(Qt.locale(), "hh:mm")
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

    toolTipMainText: i18n("Claude usage") + (planLabel() ? " — " + planLabel() : "")
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
            if (usage.status === "stale") s += "\n" + i18n("(showing last reading — %1)", usage.stale_reason || "offline")
            return s
        }
        if (usage.status === "auth") return usage.message || i18n("Sign-in needed")
        if (usage.status === "init") return i18n("Loading…")
        return usage.message || i18n("No data")
    }

    preferredRepresentation: compactRepresentation

    // A label + percentage + reset countdown above a coloured progress bar.
    component LabeledBar: ColumnLayout {
        property string barLabel: ""
        property real pct: 0
        property string resets: ""
        property bool dim: false
        Layout.fillWidth: true
        spacing: Math.round(Kirigami.Units.smallSpacing / 2)

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label { text: barLabel }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                visible: resets.length > 0
                text: i18n("resets in %1", resets)
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents.Label {
                text: Math.round(pct) + "%"
                font.bold: true
                color: root.colorFor(pct)
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: Math.round(Kirigami.Units.gridUnit * 0.5)
            radius: height / 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.12)
            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(1, pct / 100))
                color: root.colorFor(pct)
                opacity: dim ? 0.6 : 1.0
                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            }
        }
    }

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

    Connections {
        target: Plasmoid.configuration
        function onNotifyChanged() { root.refresh() }
        function onScriptPathChanged() { root.refresh() }
    }

    // ---- Compact (panel) representation ----------------------------------
    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        onClicked: {
            // Opening the popup pulls a fresh reading; closing doesn't need one.
            if (!root.expanded) root.refresh()
            root.expanded = !root.expanded
        }

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

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
                    text: usage.status === "auth" ? i18n("auth")
                          : usage.status === "init" ? "…" : "—"
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
                    delegate: RowLayout {
                        spacing: Kirigami.Units.smallSpacing / 2
                        opacity: root.usage.status === "stale" ? 0.55 : 1.0
                        PlasmaComponents.Label {
                            text: modelData.label
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        PlasmaComponents.Label {
                            text: Math.round(modelData.pct) + "%"
                            font.bold: true
                            color: root.colorFor(modelData.pct)
                        }
                    }
                }
            }
        }
    }

    // ---- Full (popup) representation -------------------------------------
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 19
        Layout.preferredHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Rectangle {
                    width: Kirigami.Units.iconSizes.small * 0.6
                    height: width
                    radius: width / 2
                    color: root.statusColor()
                    Layout.alignment: Qt.AlignVCenter
                }
                Kirigami.Heading {
                    level: 3
                    text: i18n("Claude usage")
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: root.planLabel()
                    opacity: 0.7
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    PlasmaComponents.ToolTip.text: i18n("Refresh now")
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: root.refresh()
                }
            }

            // Status / message banner (auth, error, stale, loading)
            PlasmaComponents.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !root.hasData || root.usage.status === "stale"
                opacity: 0.8
                text: {
                    if (root.usage.status === "auth")
                        return i18n("Token expired — run `claude` once in a terminal to refresh it.")
                    if (root.usage.status === "init")
                        return i18n("Loading…")
                    if (root.usage.status === "stale")
                        return i18n("Showing last reading (%1).", root.usage.stale_reason || "offline")
                    if (!root.hasData)
                        return root.usage.message || i18n("No data available.")
                    return ""
                }
            }

            // ---- Current session (5-hour rolling window) --------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasData && root.usage.session
                spacing: Math.round(Kirigami.Units.smallSpacing / 2)
                PlasmaComponents.Label {
                    text: i18n("Current session")
                    font.bold: true
                    opacity: 0.85
                }
                LabeledBar {
                    barLabel: i18n("5-hour window")
                    pct: root.usage.session ? root.usage.session.pct : 0
                    resets: root.usage.session ? (root.usage.session.resets_in || "") : ""
                    dim: root.usage.status === "stale"
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.hasData && root.usage.weekly
            }

            // ---- Weekly limits (per-model sub-bars) -------------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasData && root.usage.weekly
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: i18n("Weekly limits")
                        font.bold: true
                        opacity: 0.85
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        visible: root.usage.weekly && root.usage.weekly.resets_in
                        text: root.usage.weekly ? i18n("resets in %1", root.usage.weekly.resets_in || "") : ""
                        opacity: 0.6
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
                Repeater {
                    model: root.usage.weekly ? root.usage.weekly.bars : []
                    delegate: LabeledBar {
                        barLabel: modelData.label
                        pct: modelData.pct
                        dim: root.usage.status === "stale"
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.hasData && root.usage.credits && root.usage.credits.enabled
            }

            // ---- Usage credits (pay-as-you-go) ------------------------
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasData && root.usage.credits && root.usage.credits.enabled
                spacing: Math.round(Kirigami.Units.smallSpacing / 2)
                PlasmaComponents.Label {
                    text: i18n("Usage credits")
                    font.bold: true
                    opacity: 0.85
                }
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: i18n("Spent"); opacity: 0.8 }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        font.bold: true
                        text: {
                            var c = root.usage.credits || {}
                            if (c.spent_cents === undefined || c.spent_cents === null) return "—"
                            return "$" + (Number(c.spent_cents) / 100).toLocaleString(Qt.locale(), "f", 2)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: i18n("Monthly limit"); opacity: 0.8 }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        opacity: 0.8
                        text: {
                            var c = root.usage.credits || {}
                            if (c.monthly_limit_cents === undefined || c.monthly_limit_cents === null)
                                return i18n("Unlimited")
                            return "$" + (Number(c.monthly_limit_cents) / 100).toLocaleString(Qt.locale(), "f", 2)
                        }
                    }
                }
            }

            // Footer
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.updatedLabel().length > 0
                horizontalAlignment: Text.AlignRight
                text: i18n("updated %1", root.updatedLabel())
                opacity: 0.5
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
