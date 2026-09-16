import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_scriptPath: scriptPathField.text
    property alias cfg_refreshSeconds: refreshSpin.value
    property alias cfg_notify: notifyCheck.checked
    property alias cfg_thresholdWarn: warnSpin.value
    property alias cfg_thresholdCrit: critSpin.value
    property alias cfg_showSession: sessionCheck.checked
    property alias cfg_showWeekly: weeklyCheck.checked
    property alias cfg_showScoped: scopedCheck.checked
    property alias cfg_watchStatus: statusCheck.checked

    Kirigami.FormLayout {
        QQC2.TextField {
            id: scriptPathField
            Kirigami.FormData.label: i18n("Script path:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 60
            to: 3600
            stepSize: 30
            textFromValue: function(value) { return value + " s" }
            valueFromText: function(text) { return parseInt(text) }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: sessionCheck
            Kirigami.FormData.label: i18n("Show in panel:")
            text: i18n("Current session (5h)")
        }
        QQC2.CheckBox {
            id: weeklyCheck
            text: i18n("This week (all models)")
        }
        QQC2.CheckBox {
            id: scopedCheck
            text: i18n("Separate weekly limits (e.g. Fable)")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: statusCheck
            Kirigami.FormData.label: i18n("Claude status:")
            text: i18n("Warn about outages and elevated errors")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: notifyCheck
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Alert when approaching a limit")
        }

        QQC2.SpinBox {
            id: warnSpin
            Kirigami.FormData.label: i18n("Warning at:")
            enabled: notifyCheck.checked
            from: 1
            to: 100
            textFromValue: function(value) { return value + " %" }
            valueFromText: function(text) { return parseInt(text) }
        }

        QQC2.SpinBox {
            id: critSpin
            Kirigami.FormData.label: i18n("Critical at:")
            enabled: notifyCheck.checked
            from: 1
            to: 100
            textFromValue: function(value) { return value + " %" }
            valueFromText: function(text) { return parseInt(text) }
        }
    }
}
