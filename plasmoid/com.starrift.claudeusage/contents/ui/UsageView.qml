import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Everything `claude-usage --json` reports. Shared by the panel popup
// (detailed: false, essentials only) and the standalone window (detailed: true).
ColumnLayout {
    id: view

    property var usage: ({ "status": "init" })
    property real now: Date.now()
    property bool detailed: false
    property bool showExpand: false

    signal refreshRequested()
    signal expandRequested()

    // Label column beside the bar when there's room; stacked above it otherwise.
    readonly property bool wide: width >= Kirigami.Units.gridUnit * 30
    readonly property bool stale: usage.status === "stale"
    readonly property var limitBars: {
        if (usage.limits) return usage.limits
        // Cache written before `limits` existed.
        var bars = usage.session ? [usage.session] : []
        return usage.weekly && usage.weekly.bars ? bars.concat(usage.weekly.bars) : bars
    }
    readonly property bool hasData: (usage.status === "ok" || stale) && limitBars.length > 0
    readonly property var weekBar: {
        for (var i = 0; i < limitBars.length; i++)
            if (limitBars[i].key === "seven_day") return limitBars[i]
        return null
    }
    readonly property var credits: usage.credits || null
    // Claude status page (status.claude.com), folded in by the CLI as `service`.
    readonly property var service: usage.service || null
    readonly property string serviceSeverity: service && service.severity ? service.severity : "none"
    readonly property bool serviceAlert: serviceSeverity !== "none"
    readonly property bool serviceFlashing: serviceSeverity === "warn" || serviceSeverity === "outage"
    readonly property var breakdownRows: usage.breakdown && usage.breakdown.rows ? usage.breakdown.rows : []
    // Current billing period, estimated by the CLI from the subscription start.
    readonly property var subscription: usage.subscription || null
    readonly property real periodStartMs: subscription ? new Date(subscription.period_start).getTime() : NaN
    readonly property real periodEndMs: subscription ? new Date(subscription.period_end).getTime() : NaN
    readonly property bool hasPeriod: periodEndMs > periodStartMs

    spacing: Kirigami.Units.largeSpacing

    // ---- Formatting ------------------------------------------------------
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

    // Yellow for elevated errors / degraded service, red for an outage of
    // something we depend on, plain for in-progress maintenance.
    function serviceColor() {
        if (serviceSeverity === "outage") return Kirigami.Theme.negativeTextColor
        if (serviceSeverity === "warn") return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.textColor
    }

    function serviceHeadline() {
        if (!service) return ""
        var head = service.headline || service.description || ""
        if (serviceSeverity === "outage") return i18n("Service outage: %1", head)
        if (serviceSeverity === "warn") return i18n("Service issue: %1", head)
        if (serviceSeverity === "maintenance") return i18n("Maintenance: %1", head)
        return head
    }

    function serviceComponentText() {
        if (!service || !service.components) return ""
        var parts = []
        for (var i = 0; i < service.components.length; i++) {
            var c = service.components[i]
            if (c.status !== "operational")
                parts.push(c.name + ": " + String(c.status).replace(/_/g, " "))
        }
        return parts.join("\n")
    }

    function serviceTooltip() {
        if (!service) return ""
        var parts = [serviceHeadline()]
        var comps = serviceComponentText()
        if (comps) parts.push(comps)
        if (service.incidents) {
            for (var i = 0; i < service.incidents.length; i++) {
                var inc = service.incidents[i]
                if (inc.status) parts.push(inc.name + " (" + inc.status + ")")
            }
        }
        if (service.stale) parts.push(i18n("Status page unreachable; last known state."))
        parts.push(i18n("Click to open status.claude.com"))
        return parts.join("\n")
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

    function duration(ms) {
        var mins = Math.max(0, Math.floor(ms / 60000))
        var d = Math.floor(mins / 1440)
        var h = Math.floor(mins / 60) % 24
        var m = mins % 60
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    function msUntil(iso) {
        if (!iso) return NaN
        return new Date(iso).getTime() - now
    }

    function countdown(iso) {
        var ms = msUntil(iso)
        if (isNaN(ms)) return ""
        return ms <= 0 ? i18n("now") : duration(ms)
    }

    // "Resets at 9:00 AM" today, "Resets Monday 2:00 AM" otherwise.
    function resetText(iso) {
        if (!iso) return ""
        var d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        var time = d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        if (d.toDateString() === new Date(now).toDateString())
            return i18n("Resets at %1", time)
        if (d.getTime() - now < 7 * 86400000)
            return i18n("Resets %1 %2", d.toLocaleDateString(Qt.locale(), "dddd"), time)
        return i18n("Resets %1", d.toLocaleString(Qt.locale(), Locale.ShortFormat))
    }

    function windowMs(group) {
        return group === "session" ? 5 * 3600000 : group === "weekly" ? 7 * 86400000 : 0
    }

    // Straight-line projection from usage so far in the window. Skipped for the
    // first tenth of the window, where a few messages would project nonsense.
    function paceText(bar) {
        var len = windowMs(bar.group)
        var left = msUntil(bar.resets_at)
        if (!len || isNaN(left) || left <= 0 || bar.pct <= 0 || bar.pct >= 100) return ""
        var elapsed = len - left
        if (elapsed < len * 0.1) return ""
        var rate = bar.pct / elapsed
        var toLimit = (100 - bar.pct) / rate
        if (toLimit < left) return i18n("at this pace, limit in %1", duration(toLimit))
        return i18n("on pace for %1%", Math.round(bar.pct + rate * left))
    }

    function paceHot(bar) {
        var left = msUntil(bar.resets_at)
        var elapsed = windowMs(bar.group) - left
        return elapsed > 0 && bar.pct > 0 && (100 - bar.pct) / (bar.pct / elapsed) < left
    }

    function limitDetail(bar) {
        var parts = []
        if (detailed) {
            if (bar.detail) parts.push(bar.detail)
            var r = resetText(bar.resets_at)
            if (r) parts.push(r)
            var c = countdown(bar.resets_at)
            if (c) parts.push(i18n("in %1", c))
        } else {
            var cd = countdown(bar.resets_at)
            if (cd) parts.push(i18n("resets in %1", cd))
        }
        return parts.join(" · ")
    }

    function headline() {
        var w = weekBar
        if (!w) return ""
        var pct = Math.round(w.pct)
        if (w.pct >= 100) return i18n("Weekly limit reached.")
        var left = msUntil(w.resets_at)
        var lead = ""
        if (!isNaN(left)) {
            var day = Math.floor((windowMs("weekly") - left) / 86400000) + 1
            lead = day <= 1 ? i18n("Fresh week.") : i18n("Day %1 of 7.", Math.min(7, day))
        }
        return (lead ? lead + " " : "") + i18n("%1% of your weekly limit used.", pct)
    }

    function periodPct() {
        return 100 * (now - periodStartMs) / (periodEndMs - periodStartMs)
    }

    function periodLeftText() {
        var ms = periodEndMs - now
        return ms <= 0 ? i18n("renewing") : i18n("%1 left", duration(ms))
    }

    function periodDetail() {
        var d = new Date(periodEndMs)
        if (!detailed)
            return i18n("period ends %1", d.toLocaleDateString(Qt.locale(), "MMM d"))
        var when = d.toLocaleDateString(Qt.locale(), Locale.LongFormat) + " "
                   + d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        return i18n("Period ends %1 · estimated from your billing date", when)
    }

    function money(cents) {
        if (cents === undefined || cents === null) return "—"
        var cur = credits && credits.currency ? credits.currency : "USD"
        var amount = (Number(cents) / 100).toLocaleString(Qt.locale(), "f", 2)
        return cur === "USD" ? "$" + amount : amount + " " + cur
    }

    function reasonText(reason) {
        if (!reason) return ""
        var s = String(reason).replace(/_/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function creditsState() {
        if (!credits) return ""
        if (credits.enabled) return i18n("On")
        var why = reasonText(credits.disabled_reason)
        return why ? i18n("Off · %1", why) : i18n("Off")
    }

    function spendSummary() {
        if (!credits) return ""
        var parts = [i18n("%1 this month", money(credits.spent_cents))]
        parts.push(credits.monthly_limit_cents === null || credits.monthly_limit_cents === undefined
                   ? i18n("No spend limit")
                   : i18n("%1 limit", money(credits.monthly_limit_cents)))
        parts.push(credits.auto_reload ? i18n("Auto-reload on") : i18n("Auto-reload off"))
        return parts.join(" · ")
    }

    function updatedText() {
        if (!usage.fetched_at) return ""
        var ago = Math.floor((now - usage.fetched_at * 1000) / 60000)
        if (ago < 1) return i18n("Updated just now")
        if (ago < 60) return i18np("Updated 1 minute ago", "Updated %1 minutes ago", ago)
        return i18n("Updated %1", new Date(usage.fetched_at * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
    }

    // ---- Building blocks -------------------------------------------------
    component Bar: Rectangle {
        property real pct: 0
        property color fill: Kirigami.Theme.highlightColor
        Layout.fillWidth: true
        implicitHeight: Math.round(Kirigami.Units.gridUnit * (view.detailed ? 0.35 : 0.5))
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.12)
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: parent.width * Math.max(0, Math.min(1, parent.pct / 100))
            color: parent.fill
            opacity: view.stale ? 0.6 : 1.0
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }
    }

    // Title + detail, bar, percentage. One row when wide, stacked when narrow.
    component MeterRow: GridLayout {
        id: meter
        property string title: ""
        property string detail: ""
        property string extra: ""
        property bool extraHot: false
        property real pct: 0
        property string pctText: ""
        property color fill: Kirigami.Theme.highlightColor
        property color pctColor: Kirigami.Theme.textColor
        property bool compactRow: false

        Layout.fillWidth: true
        columns: view.wide ? 3 : 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)

        ColumnLayout {
            Layout.row: 0
            Layout.column: 0
            Layout.fillWidth: !view.wide
            Layout.preferredWidth: view.wide ? Kirigami.Units.gridUnit * 13 : -1
            Layout.maximumWidth: view.wide ? Kirigami.Units.gridUnit * 13 : -1
            spacing: 0
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: meter.title
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: meter.detail
                wrapMode: Text.WordWrap
                opacity: 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: meter.extra
                wrapMode: Text.WordWrap
                color: meter.extraHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                opacity: meter.extraHot ? 1.0 : 0.6
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
        Bar {
            Layout.row: view.wide ? 0 : 1
            Layout.column: view.wide ? 1 : 0
            Layout.columnSpan: view.wide ? 1 : 2
            Layout.alignment: Qt.AlignVCenter
            pct: meter.pct
            fill: meter.fill
        }
        PlasmaComponents.Label {
            Layout.row: 0
            Layout.column: view.wide ? 2 : 1
            Layout.alignment: Qt.AlignRight | (view.wide ? Qt.AlignVCenter : Qt.AlignTop)
            Layout.minimumWidth: view.wide ? Kirigami.Units.gridUnit * 4 : 0
            horizontalAlignment: Text.AlignRight
            text: meter.pctText
            font.bold: !meter.compactRow
            color: meter.pctColor
        }
    }

    component SectionTitle: PlasmaComponents.Label {
        Layout.fillWidth: true
        font.bold: true
        opacity: 0.85
    }

    // ---- Header ----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            width: Kirigami.Units.iconSizes.small * 0.6
            height: width
            radius: width / 2
            color: view.statusColor()
            Layout.alignment: Qt.AlignVCenter
        }
        Kirigami.Heading {
            level: view.detailed ? 2 : 3
            text: view.detailed ? i18n("Your usage") : i18n("Claude usage")
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents.Label {
            text: view.planLabel()
            opacity: 0.7
        }
        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Refresh now")
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: view.refreshRequested()
        }
        // Claude service health. Flashes while there's a live issue; red once
        // something we depend on is actually out.
        PlasmaComponents.ToolButton {
            id: statusBadge
            visible: view.serviceAlert
            text: view.serviceHeadline()
            implicitWidth: Kirigami.Units.gridUnit * 1.5
            contentItem: PlasmaComponents.Label {
                text: "!"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: view.serviceColor()
            }
            PlasmaComponents.ToolTip.text: view.serviceTooltip()
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: Qt.openUrlExternally(view.service && view.service.url
                                            ? view.service.url : "https://status.claude.com")

            // alwaysRunToEnd so it settles back at full opacity when it stops.
            SequentialAnimation on opacity {
                running: statusBadge.visible && view.serviceFlashing
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1.0; to: 0.2; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.2; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }
        }
        PlasmaComponents.ToolButton {
            visible: view.showExpand
            icon.name: "view-fullscreen"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Open in window")
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: view.expandRequested()
        }
    }

    // Status banner (auth, error, stale, loading)
    PlasmaComponents.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: !view.hasData || view.stale
        opacity: 0.8
        text: {
            if (view.usage.status === "auth")
                return i18n("Token expired. Run `claude` once in a terminal to refresh it.")
            if (view.usage.status === "init")
                return i18n("Loading…")
            if (view.stale)
                return i18n("Showing last reading (%1).", view.usage.stale_reason || "offline")
            return view.usage.message || i18n("No data available.")
        }
    }

    // Service-health banner: the badge is a glance, this says what's wrong.
    ColumnLayout {
        Layout.fillWidth: true
        visible: view.serviceAlert
        spacing: 0

        PlasmaComponents.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.bold: true
            color: view.serviceColor()
            text: view.serviceHeadline()
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: view.detailed && text.length > 0
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: view.serviceComponentText()
        }
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        visible: view.detailed && view.hasData && text.length > 0
        level: 1
        wrapMode: Text.WordWrap
        text: view.headline()
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        visible: view.detailed && view.hasData
    }

    // ---- Plan limits -----------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        visible: view.hasData
        spacing: view.detailed ? Kirigami.Units.gridUnit : Kirigami.Units.largeSpacing

        Repeater {
            model: view.limitBars
            delegate: MeterRow {
                required property var modelData
                title: modelData.label
                detail: view.limitDetail(modelData)
                extra: view.detailed ? view.paceText(modelData) : ""
                extraHot: view.detailed && view.paceHot(modelData)
                pct: modelData.pct
                pctText: Math.round(modelData.pct) + "%" + (view.wide ? " " + i18n("used") : "")
                fill: view.colorFor(modelData.pct)
                pctColor: view.colorFor(modelData.pct)
            }
        }
    }

    // ---- Subscription period ---------------------------------------------
    // Local data (Claude Code's cached profile), so it shows even when the
    // usage call itself is failing.
    Kirigami.Separator {
        Layout.fillWidth: true
        visible: view.hasPeriod
    }

    MeterRow {
        visible: view.hasPeriod
        title: i18n("Subscription")
        detail: view.hasPeriod ? view.periodDetail() : ""
        pct: view.hasPeriod ? view.periodPct() : 0
        pctText: view.hasPeriod ? view.periodLeftText() : ""
    }

    // ---- Usage by product (window only) ----------------------------------
    Kirigami.Separator {
        Layout.fillWidth: true
        visible: view.detailed && view.hasData && view.breakdownRows.length > 0
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: view.detailed && view.hasData && view.breakdownRows.length > 0
        spacing: Kirigami.Units.largeSpacing

        SectionTitle { text: i18n("This week's usage by product") }
        Repeater {
            model: view.breakdownRows
            delegate: MeterRow {
                required property var modelData
                title: modelData.label
                pct: modelData.pct
                pctText: Math.round(modelData.pct) + "%"
                compactRow: true
            }
        }
    }

    // ---- Usage credits ---------------------------------------------------
    Kirigami.Separator {
        Layout.fillWidth: true
        visible: creditsBlock.visible
    }

    ColumnLayout {
        id: creditsBlock
        Layout.fillWidth: true
        // Popup only surfaces credits while they're switched on.
        visible: view.hasData && view.credits !== null && (view.detailed || view.credits.enabled)
        spacing: Math.round(Kirigami.Units.smallSpacing / 2)

        RowLayout {
            Layout.fillWidth: true
            SectionTitle {
                text: i18n("Usage credits")
                Layout.fillWidth: false
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                visible: view.detailed && view.credits && view.credits.balance_cents !== null
                         && view.credits.balance_cents !== undefined
                font.bold: true
                text: view.credits ? view.money(view.credits.balance_cents) : ""
            }
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: view.detailed
            text: view.creditsState()
            color: view.credits && view.credits.enabled ? Kirigami.Theme.positiveTextColor
                                                        : Kirigami.Theme.textColor
            opacity: view.credits && view.credits.enabled ? 1.0 : 0.7
        }

        SectionTitle {
            visible: view.detailed
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Monthly spend")
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: view.detailed ? view.spendSummary()
                                : (view.credits ? i18n("%1 spent this month", view.money(view.credits.spent_cents)) : "")
        }
        Bar {
            visible: view.detailed && view.credits && view.credits.monthly_limit_cents > 0
            Layout.topMargin: Kirigami.Units.smallSpacing
            readonly property real spentPct: view.credits && view.credits.monthly_limit_cents > 0
                                             ? 100 * view.credits.spent_cents / view.credits.monthly_limit_cents : 0
            pct: spentPct
            fill: view.colorFor(spentPct)
        }
    }

    // ---- Footer ----------------------------------------------------------
    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: text.length > 0
        horizontalAlignment: view.detailed ? Text.AlignLeft : Text.AlignRight
        text: view.updatedText()
        opacity: 0.5
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }
}
