import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore

// Icon picker modelled on Kickoff's "Icon:" button
KCM.SimpleKCM {
    property string cfg_panelIcon
    property string cfg_panelIconDefault

    Kirigami.FormLayout {
        QQC2.Button {
            id: iconButton
            Kirigami.FormData.label: "Panel icon:"

            implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
            implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2
            hoverEnabled: true

            QQC2.ToolTip.text: "Click to change the icon"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

            KIconThemes.IconDialog {
                id: iconDialog
                onIconNameChanged: if (iconName) cfg_panelIcon = iconName
            }

            // panel-looking frame so the preview matches what the panel shows
            KSvg.FrameSvgItem {
                id: previewFrame
                anchors.centerIn: parent
                imagePath: "widgets/panel-background"
                width: Kirigami.Units.iconSizes.large + fixedMargins.left + fixedMargins.right
                height: Kirigami.Units.iconSizes.large + fixedMargins.top + fixedMargins.bottom

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.large
                    height: width
                    source: cfg_panelIcon
                }
            }

            QQC2.Menu {
                id: iconMenu
                y: parent.height

                QQC2.MenuItem {
                    text: "Choose…"
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                QQC2.MenuItem {
                    text: "Reset to default icon"
                    icon.name: "edit-clear"
                    enabled: cfg_panelIcon !== cfg_panelIconDefault
                    onClicked: cfg_panelIcon = cfg_panelIconDefault
                }
            }
        }
    }
}
