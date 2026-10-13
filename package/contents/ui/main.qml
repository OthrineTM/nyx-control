import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.private.brightnesscontrolplugin as Brightness
import org.kde.notificationmanager as NotificationManager
import org.kde.ksysguard.sensors as Sensors
import org.kde.kirigami as Kirigami
import org.kde.bluezqt as BluezQt
import org.kde.kdeconnect as KDEConnect
import org.kde.plasma.private.clipboard as Clip

PlasmoidItem {
    id: root

    // colors come from the active KDE theme
    readonly property color cAccent: Kirigami.Theme.highlightColor
    readonly property color cText: Kirigami.Theme.textColor
    readonly property color cWarn: Kirigami.Theme.neutralTextColor
    readonly property color cHot: Kirigami.Theme.negativeTextColor

    Plasmoid.icon: Plasmoid.configuration.panelIcon
    toolTipMainText: "Control Center"
    toolTipSubText: notifs.count > 0 ? notifs.count + " notifications" : "No notifications"

    // ---- shell commands (volume, power profile) -----------------------
    property real volume: 0
    property bool muted: false
    property string rootDisk: "disk/all/usedPercent"   // replaced by the / partition once known
    Component.onCompleted: exec.run("findmnt -no UUID /")
    property string profile: ""

    P5Support.DataSource {
        id: exec
        engine: "executable"
        function run(cmd) { connectSource(cmd) }
        onNewData: function (source, data) {
            disconnectSource(source)
            var out = (data["stdout"] || "").trim()
            if (source === root.cmdGetVolume) {
                var m = out.match(/Volume:\s*([\d.]+)/)
                if (m && !volumeSlider.pressed) root.volume = parseFloat(m[1])
                root.muted = out.indexOf("MUTED") !== -1
            } else if (source === "findmnt -no UUID /") {
                if (out.length > 0) root.rootDisk = "disk/" + out + "/usedPercent"
            } else if (source === root.cmdGetNight) {
                root.nightLight = out === "true"
            } else if (source === root.cmdGetProfile) {
                root.profile = out
            }
        }
    }
    readonly property string cmdGetVolume: "wpctl get-volume @DEFAULT_AUDIO_SINK@"
    readonly property string cmdGetProfile: "powerprofilesctl get"
    readonly property string cmdGetNight: "qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.freedesktop.DBus.Properties.Get org.kde.KWin.NightLight enabled"
    property bool nightLight: false
    function setNightLight(on) {
        root.nightLight = on
        // never configured -> "always on" mode, otherwise keep the user's schedule
        // --notify makes KWin pick the change up immediately
        exec.run("kreadconfig6 --file kwinrc --group NightColor --key Mode | grep -q . || kwriteconfig6 --notify --file kwinrc --group NightColor --key Mode Constant; "
               + "kwriteconfig6 --notify --file kwinrc --group NightColor --key Active " + on)
    }

    // bluetooth, same logic as Plasma's bluetooth applet
    readonly property bool btOn: BluezQt.Manager.bluetoothOperational
    property int btTick: 0   // re-evaluates the bindings below while the popup is open
    Timer { interval: 2000; repeat: true; running: root.expanded; onTriggered: root.btTick++ }
    readonly property var btConnected: {
        root.btTick; root.expanded
        return BluezQt.Manager.devices.filter(d => d.connected).map(d => d.name)
    }
    // first connected headset / headphones / speaker
    readonly property var btAudio: {
        root.btTick; root.expanded
        const audio = [BluezQt.Device.Headset, BluezQt.Device.Headphones, BluezQt.Device.AudioVideo]
        return BluezQt.Manager.devices.find(d => d.connected && audio.includes(d.type)) ?? null
    }
    readonly property int btAudioBattery: { root.btTick; return btAudio?.battery?.percentage ?? -1 }
    function toggleBluetooth() {
        const enable = !root.btOn
        BluezQt.Manager.bluetoothBlocked = !enable
        BluezQt.Manager.adapters.forEach(a => a.powered = enable)
    }

    KDEConnect.DevicesModel {
        id: phones
        displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable
    }

    Clip.HistoryModel { id: clipModel }
    property Item volumeSlider: Item { property bool pressed: false }

    function refresh() {
        exec.run(cmdGetVolume)
        exec.run(cmdGetProfile)
        exec.run(cmdGetNight)
    }
    function setVolume(v) {
        root.volume = v
        exec.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + v.toFixed(2))
    }
    function setProfile(p) {
        root.profile = p
        exec.run("powerprofilesctl set " + p)
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 2000
        repeat: true
        running: root.expanded
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ---- data sources -------------------------------------------------
    Sessions.SessionManagement { id: session }
    Brightness.ScreenBrightnessControl { id: brightness; isSilent: false }

    NotificationManager.Settings { id: notifSettings; live: true }
    readonly property bool dnd: notifSettings.notificationsInhibitedUntil > new Date()
    function toggleDnd() {
        // "until turned off" = far future, the same trick Plasma's own applet uses
        notifSettings.notificationsInhibitedUntil = dnd ? new Date(0) : new Date(Date.now() + 100 * 365 * 24 * 3600 * 1000)
        notifSettings.save()
    }

    NotificationManager.Notifications {
        id: notifs
        showExpired: true
        showDismissed: true
        showAddedDuringInhibition: true
        showJobs: false
        showNotifications: true
        groupMode: NotificationManager.Notifications.GroupDisabled
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
    }
    function closeRow(row) { notifs.close(notifs.index(row, 0)) }
    function closeApp(appName) {
        for (var i = notifs.count - 1; i >= 0; i--) {
            if (notifs.data(notifs.index(i, 0), NotificationManager.Notifications.ApplicationNameRole) === appName)
                closeRow(i)
        }
    }
    function clearAll() {
        for (var i = notifs.count - 1; i >= 0; i--) closeRow(i)
    }

    // laptop battery, same data engine Plasma's battery applet used to read
    P5Support.DataSource {
        id: pmSource
        engine: "powermanagement"
        connectedSources: ["Battery", "AC Adapter"]
        interval: 30000
    }
    readonly property bool hasBattery: pmSource.data["Battery"]?.["Has Battery"] ?? false
    readonly property int batteryPercent: pmSource.data["Battery"]?.["Percent"] ?? 0
    readonly property bool pluggedIn: pmSource.data["AC Adapter"]?.["Plugged in"] ?? false
    readonly property string batteryState: pmSource.data["Battery"]?.["State"] ?? ""

    Sensors.Sensor { id: sCpu; sensorId: "cpu/all/usage"; enabled: root.expanded; updateRateLimit: 1500 }
    Sensors.Sensor { id: sMem; sensorId: "memory/physical/usedPercent"; enabled: root.expanded; updateRateLimit: 1500 }
    Sensors.Sensor { id: sDisk; sensorId: root.rootDisk; enabled: root.expanded; updateRateLimit: 10000 }
    Sensors.Sensor { id: sTemp; sensorId: "cpu/all/maximumTemperature"; enabled: root.expanded; updateRateLimit: 1500 }
    Sensors.Sensor { id: sUptime; sensorId: "os/system/uptime"; enabled: root.expanded; updateRateLimit: 30000 }

    // ---- reusable bits ------------------------------------------------
    component Card: Rectangle {
        radius: Kirigami.Units.cornerRadius * 2
        color: Qt.alpha(root.cText, 0.05)
        border.color: Qt.alpha(root.cText, 0.08)
    }

    component Gauge: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 6
        Layout.minimumHeight: Kirigami.Units.gridUnit * 6
        property alias value: dial.value
        property alias valueText: dial.valueText
        property alias label: dial.label
        property alias icon: dial.icon
        property alias color: dial.color
        GaugeDial {
            id: dial
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
        }
    }

    component GaugeDial: Item {
        id: g
        property real value: 0          // 0..100
        property string valueText
        property string label
        property string icon
        property color color: root.cAccent
        readonly property real thickness: Math.max(6, width * 0.07)
        Behavior on value { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - g.thickness * 2 - 8
            height: width
            radius: width / 2
            color: Qt.alpha(root.cText, 0.04)
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(root.cText, 0.10)
                strokeWidth: g.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: g.width / 2; centerY: g.height / 2
                    radiusX: g.width / 2 - g.thickness / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: 270
                }
            }
            ShapePath {
                strokeColor: g.color
                strokeWidth: g.thickness
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: g.width / 2; centerY: g.height / 2
                    radiusX: g.width / 2 - g.thickness / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: Math.max(0.5, 270 * Math.min(100, Math.max(0, g.value)) / 100)
                }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                Kirigami.Icon {
                    source: g.icon
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PC3.Label {
                    text: g.valueText
                    font.pixelSize: g.width * 0.17
                    font.bold: true
                    font.features: { "tnum": 1 }
                }
            }
            PC3.Label {
                Layout.alignment: Qt.AlignHCenter
                text: g.label
                font.pixelSize: Math.max(9, g.width * 0.075)
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                opacity: 0.7
            }
        }
    }

    component TimeBox: Card {
        property alias value: v.text
        property alias unit: u.text
        implicitWidth: Kirigami.Units.gridUnit * 3
        implicitHeight: Kirigami.Units.gridUnit * 3
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            PC3.Label {
                id: v
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Kirigami.Units.gridUnit * 1.1
                font.bold: true
                font.features: { "tnum": 1 }
                color: root.cAccent
            }
            PC3.Label {
                id: u
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Kirigami.Units.gridUnit * 0.5
                opacity: 0.6
            }
        }
    }

    component Tile: PC3.AbstractButton {
        id: tile
        property string iconName
        property string title
        property string subtitle
        property bool active: false
        property string iconTip: ""          // set to make the icon its own button
        signal iconClicked()
        property string actionIcon: ""       // optional small button at the right edge
        property string actionTip: ""
        signal actionClicked()
        HoverHandler { id: tileHover }       // children don't steal this one
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3.4
        hoverEnabled: true
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: actionButton.visible ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        background: Rectangle {
            radius: Kirigami.Units.cornerRadius * 2
            color: tile.active ? Qt.alpha(root.cAccent, tile.hovered ? 0.55 : 0.42)
                               : Qt.alpha(root.cText, tile.hovered ? 0.10 : 0.05)
            border.color: tile.active ? Qt.alpha(root.cAccent, 0.9) : Qt.alpha(root.cText, 0.08)
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        }
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium + 14
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium + 14
                radius: height / 2
                color: Qt.alpha(root.cText, iconMa.containsMouse ? 0.20 : 0.08)
                border.color: iconMa.enabled ? Qt.alpha(root.cText, iconMa.containsMouse ? 0.40 : 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: tile.iconName
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                }
                MouseArea {
                    id: iconMa
                    anchors.fill: parent
                    enabled: tile.iconTip.length > 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.iconClicked()
                }
                PC3.ToolTip.text: tile.iconTip
                PC3.ToolTip.visible: iconMa.containsMouse
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PC3.Label {
                    Layout.fillWidth: true
                    text: tile.title
                    font.bold: true
                    elide: Text.ElideRight
                }
                PC3.Label {
                    Layout.fillWidth: true
                    text: tile.subtitle
                    font: Kirigami.Theme.smallFont
                    opacity: 0.75
                    elide: Text.ElideRight
                }
            }
            PC3.ToolButton {
                id: actionButton
                // shown on hover so long names have room the rest of the time
                visible: tile.actionIcon.length > 0 && tileHover.hovered
                icon.name: tile.actionIcon
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                Layout.preferredWidth: Kirigami.Units.iconSizes.small + 10
                Layout.preferredHeight: Kirigami.Units.iconSizes.small + 10
                Layout.leftMargin: -Kirigami.Units.smallSpacing
                onClicked: tile.actionClicked()
                PC3.ToolTip.text: tile.actionTip
                PC3.ToolTip.visible: hovered
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    component BigButton: PC3.AbstractButton {
        id: bb
        property string tip
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3.5
        hoverEnabled: true
        background: Rectangle {
            radius: Kirigami.Units.cornerRadius * 2
            color: bb.pressed ? Qt.alpha(root.cAccent, 0.42) : Qt.alpha(root.cText, bb.hovered ? 0.10 : 0.05)
            border.color: Qt.alpha(bb.hovered ? root.cAccent : root.cText, bb.hovered ? 0.6 : 0.08)
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        }
        contentItem: Item {
            Kirigami.Icon {
                anchors.centerIn: parent
                source: bb.icon.name
                width: Kirigami.Units.iconSizes.medium
                height: width
            }
        }
        PC3.ToolTip.text: bb.tip
        PC3.ToolTip.visible: bb.hovered
        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // ---- popup ---------------------------------------------------------
    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 46
        Layout.minimumWidth: Kirigami.Units.gridUnit * 40
        Layout.preferredHeight: Kirigami.Units.gridUnit * 40
        Layout.minimumHeight: Kirigami.Units.gridUnit * 34

        RowLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing * 2

            // ===== notifications =====
            ColumnLayout {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 17
                Layout.maximumWidth: Kirigami.Units.gridUnit * 17
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PC3.TabBar {
                        id: leftTabs
                        Layout.fillWidth: true
                        PC3.TabButton { text: "Notifications" + (notifs.count > 0 ? " (" + notifs.count + ")" : "") }
                        PC3.TabButton { text: "Clipboard" }
                    }
                    PC3.ToolButton {
                        icon.name: "edit-clear-all"
                        visible: leftTabs.currentIndex === 0 ? notifs.count > 0 : clipModel.count > 0
                        onClicked: leftTabs.currentIndex === 0 ? root.clearAll() : clipModel.clearHistory()
                        PC3.ToolTip.text: leftTabs.currentIndex === 0 ? "Clear all notifications" : "Clear clipboard history"
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    PC3.ToolButton {
                        visible: leftTabs.currentIndex === 0
                        icon.name: root.dnd ? "notifications-disabled" : "notifications"
                        checkable: true
                        checked: root.dnd
                        onClicked: root.toggleDnd()
                        PC3.ToolTip.text: root.dnd ? "Do not disturb is on" : "Turn on do not disturb"
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: leftTabs.currentIndex
                    PC3.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

                        ListView {
                            id: notifList
                            model: notifs
                            spacing: Kirigami.Units.smallSpacing
                            clip: true
                            reuseItems: true

                            section.property: "applicationName"
                            section.delegate: RowLayout {
                                required property string section
                                width: ListView.view.width
                                Kirigami.Icon {
                                    source: "arrow-down"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    opacity: 0.6
                                }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    text: section
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    elide: Text.ElideRight
                                }
                                PC3.ToolButton {
                                    icon.name: "window-close"
                                    icon.width: Kirigami.Units.iconSizes.small
                                    icon.height: Kirigami.Units.iconSizes.small
                                    onClicked: root.closeApp(section)
                                }
                            }

                            delegate: Card {
                                id: card
                                required property int index
                                required property string summary
                                required property string body
                                required property bool hasDefaultAction
                                required property bool closable
                                required property var created
                                width: ListView.view.width
                                implicitHeight: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2

                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: 3
                                    radius: 1.5
                                    color: root.cAccent
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: card.hasDefaultAction
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: notifs.invokeDefaultAction(notifs.index(card.index, 0))
                                }
                                ColumnLayout {
                                    id: cardCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    anchors.leftMargin: Kirigami.Units.largeSpacing + 3
                                    anchors.rightMargin: Kirigami.Units.smallSpacing
                                    anchors.topMargin: Kirigami.Units.largeSpacing
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        PC3.Label {
                                            Layout.fillWidth: true
                                            text: card.summary
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        PC3.Label {
                                            text: Qt.formatTime(card.created, "hh:mm")
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.5
                                        }
                                        PC3.ToolButton {
                                            visible: card.closable
                                            icon.name: "window-close"
                                            icon.width: Kirigami.Units.iconSizes.small
                                            icon.height: Kirigami.Units.iconSizes.small
                                            Layout.preferredWidth: Kirigami.Units.iconSizes.small + 8
                                            Layout.preferredHeight: Kirigami.Units.iconSizes.small + 8
                                            onClicked: root.closeRow(card.index)
                                        }
                                    }
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        visible: card.body.length > 0
                                        text: card.body
                                        textFormat: Text.StyledText
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        opacity: 0.8
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                            }

                            Kirigami.PlaceholderMessage {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 2
                                visible: notifList.count === 0
                                icon.name: root.dnd ? "notifications-disabled" : "checkmark"
                                text: root.dnd ? "Do not disturb" : "All caught up"
                            }
                        }
                    }

                    PC3.ScrollView {
                        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff
                        ListView {
                            id: clipList
                            model: clipModel
                            spacing: Kirigami.Units.smallSpacing
                            clip: true
                            reuseItems: true

                            delegate: Card {
                                id: clipCard
                                required property int index
                                required property string display
                                required property var decoration
                                required property size imageSize
                                required property var uuid
                                readonly property bool isImage: imageSize.width > 0 && imageSize.height > 0
                                width: ListView.view.width
                                implicitHeight: (isImage ? Kirigami.Units.gridUnit * 4 : clipText.implicitHeight)
                                                + Kirigami.Units.largeSpacing * 2
                                color: clipMa.containsMouse ? Qt.alpha(root.cAccent, 0.18) : Qt.alpha(root.cText, 0.05)

                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: 3
                                    radius: 1.5
                                    color: root.cAccent
                                    visible: clipCard.index === 0   // current clipboard content
                                }
                                MouseArea {
                                    id: clipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: clipModel.moveToTop(clipCard.uuid)
                                }
                                PC3.Label {
                                    id: clipText
                                    visible: !clipCard.isImage
                                    anchors { left: parent.left; right: clipDel.left; verticalCenter: parent.verticalCenter }
                                    anchors.leftMargin: Kirigami.Units.largeSpacing + 3
                                    text: clipCard.display.trim().slice(0, 300)
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    font: Kirigami.Theme.smallFont
                                }
                                Image {
                                    visible: clipCard.isImage
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    anchors.leftMargin: Kirigami.Units.largeSpacing + 3
                                    height: Kirigami.Units.gridUnit * 4
                                    width: Math.min(clipCard.width - Kirigami.Units.gridUnit * 4, height * clipCard.imageSize.width / Math.max(1, clipCard.imageSize.height))
                                    fillMode: Image.PreserveAspectFit
                                    horizontalAlignment: Image.AlignLeft
                                    source: clipCard.isImage ? clipCard.decoration : ""
                                    sourceSize.height: height
                                }
                                PC3.ToolButton {
                                    id: clipDel
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Kirigami.Units.smallSpacing }
                                    icon.name: "edit-delete-remove"
                                    icon.width: Kirigami.Units.iconSizes.small
                                    icon.height: Kirigami.Units.iconSizes.small
                                    opacity: clipMa.containsMouse || hovered ? 1 : 0.4
                                    onClicked: clipModel.remove(clipCard.uuid)
                                }
                            }

                            Kirigami.PlaceholderMessage {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 2
                                visible: clipList.count === 0
                                icon.name: "edit-paste"
                                text: "Clipboard is empty"
                            }
                        }
                    }
                }
            }

            // ===== system =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    readonly property int up: sUptime.value || 0
                    TimeBox {
                        visible: parent.up >= 86400
                        value: Math.floor(parent.up / 86400)
                        unit: "DAY"
                    }
                    TimeBox {
                        value: String(Math.floor(parent.up % 86400 / 3600)).padStart(2, "0")
                        unit: "HR"
                    }
                    PC3.Label { text: ":"; font.bold: true; opacity: 0.5 }
                    TimeBox {
                        value: String(Math.floor(parent.up % 3600 / 60)).padStart(2, "0")
                        unit: "MIN"
                    }
                    PC3.Label {
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        text: "uptime"
                        opacity: 0.5
                    }
                    Item { Layout.fillWidth: true }
                    PC3.ToolButton {
                        icon.name: "system-log-out"
                        opacity: hovered ? 1 : 0.5   // quieter until you point at it
                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                        onClicked: session.requestLogout()
                        PC3.ToolTip.text: "Log out"
                        PC3.ToolTip.visible: hovered
                        PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    Card {
                        visible: root.hasBattery
                        readonly property bool low: root.batteryPercent <= 20 && !root.pluggedIn
                        implicitWidth: battRow.implicitWidth + Kirigami.Units.largeSpacing * 2
                        implicitHeight: Kirigami.Units.gridUnit * 3
                        RowLayout {
                            id: battRow
                            anchors.centerIn: parent
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "battery-" + String(Math.round(root.batteryPercent / 10) * 10).padStart(3, "0")
                                        + (root.batteryState === "Charging" ? "-charging" : "")
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                isMask: true
                                color: parent.parent.low ? root.cHot : root.cText
                            }
                            ColumnLayout {
                                spacing: 0
                                PC3.Label {
                                    text: root.batteryPercent + "%"
                                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                                    font.bold: true
                                    font.features: { "tnum": 1 }
                                    color: parent.parent.parent.low ? root.cHot : root.cAccent
                                }
                                PC3.Label {
                                    text: root.batteryState === "Charging" ? "CHARGING"
                                        : root.pluggedIn ? "PLUGGED IN" : "ON BATTERY"
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.5
                                    opacity: 0.6
                                }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    rowSpacing: Kirigami.Units.largeSpacing
                    columnSpacing: Kirigami.Units.largeSpacing
                
                    Gauge {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        icon: "cpu"
                        value: sCpu.value || 0
                        valueText: Math.round(sCpu.value || 0) + "%"
                        label: "CPU load"
                    }
                    Gauge {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        icon: "memory"
                        value: sMem.value || 0
                        valueText: Math.round(sMem.value || 0) + "%"
                        label: "Memory"
                    }
                    Gauge {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        icon: "drive-harddisk"
                        value: sDisk.value || 0
                        valueText: Math.round(sDisk.value || 0) + "%"
                        label: "Storage"
                    }
                    Gauge {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        readonly property real t: sTemp.value || 0
                        icon: "temperature-normal"
                        value: t
                        color: t >= 90 ? root.cHot : (t >= 75 ? root.cWarn : root.cAccent)
                        valueText: Math.round(t) + "°"
                        label: "CPU temp"
                    }
                }

                Card {
                    Layout.fillWidth: true
                    implicitHeight: sliders.implicitHeight + Kirigami.Units.largeSpacing * 2
                    ColumnLayout {
                        id: sliders
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: brightness.displays
                            RowLayout {
                                required property var model
                                Layout.fillWidth: true
                                // same box and monochrome style as the volume button next row
                                Item {
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium + 8
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium + 8
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: "brightness-high-symbolic"
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        isMask: true
                                        color: root.cText
                                    }
                                }
                                PC3.Slider {
                                    id: bSlider
                                    Layout.fillWidth: true
                                    from: 1
                                    to: model.maxBrightness
                                    value: model.brightness
                                    onMoved: brightness.setBrightness(model.displayName, value)
                                }
                                PC3.Label {
                                    text: Math.round(100 * bSlider.value / Math.max(1, bSlider.to)) + "%"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                    horizontalAlignment: Text.AlignRight
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.ToolButton {
                                icon.name: root.muted ? "audio-volume-muted" : (root.volume > 0.66 ? "audio-volume-high" : root.volume > 0.33 ? "audio-volume-medium" : "audio-volume-low")
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium + 8
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium + 8
                                onClicked: {
                                    root.muted = !root.muted
                                    exec.run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
                                }
                            }
                            PC3.Slider {
                                id: vSlider
                                Layout.fillWidth: true
                                from: 0; to: 1
                                stepSize: 0.01
                                value: root.volume
                                opacity: root.muted ? 0.5 : 1
                                onMoved: root.setVolume(value)
                                Component.onCompleted: root.volumeSlider = vSlider
                            }
                            PC3.Label {
                                text: Math.round(root.volume * 100) + "%"
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                horizontalAlignment: Text.AlignRight
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: Kirigami.Units.largeSpacing
                    columnSpacing: Kirigami.Units.largeSpacing

                    Tile {
                        // a connected headset/speaker takes over the tile
                        iconName: root.btAudio ? (root.btAudio.icon || "audio-headphones")
                                : (root.btOn ? "network-bluetooth" : "network-bluetooth-inactive")
                        title: root.btAudio ? root.btAudio.name : "Bluetooth"
                        subtitle: root.btAudio
                                ? (root.btAudioBattery > -1 ? "Battery " + root.btAudioBattery + "%" : "Connected")
                                : (!root.btOn ? "Off" : (root.btConnected.length > 0 ? root.btConnected.join(", ") : "On"))
                        active: root.btOn
                        onClicked: root.toggleBluetooth()
                        iconTip: "Bluetooth settings"
                        onIconClicked: {
                            root.expanded = false
                            exec.run("kcmshell6 kcm_bluetooth")
                        }
                    }
                    Tile {
                        iconName: root.nightLight ? "redshift-status-on" : "redshift-status-off"
                        title: "Night Light"
                        subtitle: root.nightLight ? "On" : "Off"
                        active: root.nightLight
                        onClicked: root.setNightLight(!root.nightLight)
                        iconTip: "Night Light settings"
                        onIconClicked: {
                            root.expanded = false
                            exec.run("kcmshell6 kcm_nightlight")
                        }
                    }
                    Tile {
                        visible: phones.count === 0
                        iconName: "kdeconnect"
                        title: "KDE Connect"
                        subtitle: "No phone"
                        onClicked: exec.run("kdeconnect-app")
                    }
                    Repeater {
                        model: phones
                        Tile {
                            id: phoneTile
                            required property string deviceId
                            required property string name
                            readonly property var device: KDEConnect.DeviceDbusInterfaceFactory.create(deviceId)
                            readonly property var battery: batteryCheck.available ? KDEConnect.DeviceBatteryDbusInterfaceFactory.create(deviceId) : null
                            KDEConnect.PluginChecker { id: batteryCheck; pluginName: "battery"; device: phoneTile.device }
                            KDEConnect.PluginChecker { id: ringCheck; pluginName: "findmyphone"; device: phoneTile.device }

                            iconName: "smartphone"
                            title: name
                            subtitle: battery && battery.charge > -1
                                ? battery.charge + "%" + (battery.isCharging ? " · charging" : "")
                                : "Connected"
                            active: true
                            onClicked: exec.run("kdeconnect-app")
                            actionIcon: ringCheck.available ? "irc-voice" : ""
                            actionTip: "Ring phone"
                            onActionClicked: KDEConnect.FindMyPhoneDbusInterfaceFactory.create(phoneTile.deviceId).ring()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    BigButton { icon.name: "system-lock-screen"; tip: "Lock"; onClicked: session.lock() }
                    BigButton { icon.name: "system-suspend"; tip: "Sleep"; onClicked: session.suspend() }
                    BigButton { icon.name: "system-reboot"; tip: "Restart"; onClicked: session.requestReboot() }
                    BigButton { icon.name: "system-shutdown"; tip: "Shut down"; onClicked: session.requestShutdown() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: [
                            { id: "performance", label: "Performance", icon: "power-profile-performance-symbolic" },
                            { id: "balanced", label: "Balanced", icon: "power-profile-balanced-symbolic" },
                            { id: "power-saver", label: "Power Saver", icon: "power-profile-power-saver-symbolic" }
                        ]
                        PC3.AbstractButton {
                            id: seg
                            required property var modelData
                            readonly property bool current: root.profile === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
                            hoverEnabled: true
                            leftPadding: Kirigami.Units.largeSpacing
                            rightPadding: Kirigami.Units.largeSpacing
                            onClicked: root.setProfile(modelData.id)
                            background: Rectangle {
                                radius: Kirigami.Units.cornerRadius * 2
                                color: seg.current ? Qt.alpha(root.cAccent, seg.hovered ? 0.55 : 0.42)
                                                   : Qt.alpha(root.cText, seg.hovered ? 0.10 : 0.05)
                                border.color: seg.current ? Qt.alpha(root.cAccent, 0.9) : Qt.alpha(root.cText, 0.08)
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                            }
                            contentItem: Item {
                                RowLayout {
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width)
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.Icon {
                                        source: seg.modelData.icon
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        text: seg.modelData.label
                                        font.bold: seg.current
                                        elide: Text.ElideRight
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
