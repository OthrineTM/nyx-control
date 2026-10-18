# Nyx Control

A control center for the KDE Plasma 6 panel. Notifications, clipboard, system gauges, quick toggles and power controls all live in one popup.

By default all colors come from your active Plasma theme, so it matches whatever theme you use. The **Style** page switches it to one of the shared Nyx looks, the same ones [Nyx Clock](https://github.com/OthrineTM/nyx-clock) and [Nyx Player](https://github.com/OthrineTM/nyx-player) use; with sharing on, a look applied in one widget is used by all of them.

![Nyx Control popup with notifications, system gauges, sliders, quick tiles and power profiles](screenshots/control.png)

## Features

- **Notifications tab:** history grouped by app, dismiss one or clear all. The bell toggles Do Not Disturb.
- **Clipboard tab:** your clipboard history.
- **Gauges:** ring meters for CPU load, memory, storage (the `/` partition) and CPU temperature, plus uptime and battery level.
- **Sliders:** screen brightness and volume (click the speaker to mute).
- **Quick tiles:**
  - **Bluetooth:** shows the connected audio device
  - **Night Light**
  - **KDE Connect:** shows your phone's battery and has a ring-my-phone button
- **Power profile:** Performance / Balanced / Power Saver.
- **Session buttons:** lock, sleep, log out, restart, shut down.
- **Layouts:** notifications on the left or right, or a compact system-only panel. Each section (gauges, sliders, tiles, session buttons, power profiles) can be hidden.
- **Gauge styles:** rings, bars or big numbers with memory in GB. Switch in the settings or with **Next Gauge Style** in the right-click menu.
- **Styles:** the shared Nyx looks (Glass, Frost, Smoke, Solid, Light, Neon, Clear, Theme) with sliders for every detail and your own saved presets. The default Theme look matches your Plasma theme. On the desktop the control center draws its own styled panel.
- **Settings:** a configurable panel icon.

## Requirements

- KDE Plasma 6 (tested on 6.7.5)
- `ksystemstats` for the gauges, which Plasma already includes
- `power-profiles-daemon` for the power profile buttons
- WirePlumber (`wpctl`) for volume
- Optional: `bluez-qt` + Bluetooth, and KDE Connect for those tiles

## Install

**From the KDE Store:** right-click your panel → **Add or Manage Widgets…** → **Get New Widgets…** → **Download New Plasma Widgets…**, search for **Nyx Control** and click **Install**. Or download it from its [KDE Store page](https://store.kde.org/p/2378514).

**From GitHub:**

```bash
git clone https://github.com/OthrineTM/nyx-control.git
kpackagetool6 --type Plasma/Applet --install nyx-control/package
```

Then right-click your panel → **Add or Manage Widgets…**, search for **Nyx Control**, and drag it onto the panel.

**Update:** `git pull`, then `kpackagetool6 --type Plasma/Applet --upgrade nyx-control/package`, then `systemctl --user restart plasma-plasmashell`.

**Remove:** `kpackagetool6 --type Plasma/Applet --remove io.github.othrinetm.nyxcontrol`

## Notes

The widget uses some of Plasma's private QML modules (sessions, brightness, clipboard), the same ones the built-in widgets use. A big Plasma update could break them.

## See also

- [Nyx Player](https://github.com/OthrineTM/nyx-player): panel music player with a spinning vinyl cover and an Easy Effects preset switcher
- [Nyx Clock](https://github.com/OthrineTM/nyx-clock): customizable desktop clock with weekday, date and weather

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
