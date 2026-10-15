// Plasmarchy animated wallpaper. Colors, effect and logo are written by "plasmarchy" on every theme switch.
// The animation pauses while a maximized or fullscreen window covers this screen (saves battery and GPU).
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager

WallpaperItem {
    id: wallpaper
    readonly property var cfg: wallpaper.configuration

    // --- Is the wallpaper covered? -----------------------------------------------------------------
    TaskManager.VirtualDesktopInfo { id: desktops }
    TaskManager.ActivityInfo { id: activities }
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        screenGeometry: wallpaper.parent ? wallpaper.parent.screenGeometry : Qt.rect(0, 0, 0, 0)
        virtualDesktop: desktops.currentDesktop
        activity: activities.currentActivity
        filterByScreen: true
        filterByVirtualDesktop: true
        filterByActivity: true
        filterMinimized: true
    }
    property int covering: 0
    Repeater {
        model: tasks
        delegate: Item {
            readonly property bool covers: model.IsMaximized || model.IsFullScreen
            onCoversChanged: wallpaper.covering += covers ? 1 : -1
            Component.onCompleted: if (covers) wallpaper.covering += 1
            Component.onDestruction: if (covers) wallpaper.covering -= 1
        }
    }

    Scene {
        anchors.fill: parent
        effect: wallpaper.cfg.effect
        background: wallpaper.cfg.background
        darkBackground: wallpaper.cfg.darkBackground
        foreground: wallpaper.cfg.foreground
        accent: wallpaper.cfg.accent
        colorList: String(wallpaper.cfg.palette).split(",").filter(x => x)
        // the version parameter makes Qt reload the image after the logo changed
        logo: wallpaper.cfg.logo ? "file://" + wallpaper.cfg.logo + "?v=" + wallpaper.cfg.logoVersion : ""
        showLogo: wallpaper.cfg.showLogo && wallpaper.cfg.logo !== ""
        speed: wallpaper.cfg.speed
        running: !(wallpaper.cfg.pauseWhenCovered && wallpaper.covering > 0)
    }
}
