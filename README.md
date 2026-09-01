# Omarchy Mouse

A native [Omarchy](https://omarchy.org) shell plugin for controlling every
aspect of mouse and pointer configuration from one bar panel.

## Features

**Pointer**
- Scroll speed (mouse wheel) — slider, ×0.1 to ×5.0
- Sensitivity — slider, −1.0 to 1.0
- Acceleration profile — adaptive / flat (no acceleration)
- Focus follows mouse — disabled / full / loose / on-border
- Natural scroll, left-handed mode, middle-click paste, emulate discrete scroll

**Touchpad**
- Scroll speed, natural scroll, tap-to-click, disable-while-typing, drag lock

**Devices**
- Per-device scroll-factor slider for every detected pointer (each mouse,
  the touchpad, etc.)

All changes apply instantly via `hyprctl eval` (Omarchy uses Lua Hyprland
config, so the plugin drives `hl.config` / `hl.device` rather than the
disabled `hyprctl keyword`). Changes are session-only — to make a value
permanent, set it in `~/.config/hypr/input.lua`.

## Install

```bash
omarchy plugin add https://github.com/alenNumberOneAI/omarchy-mouse-config-gui.git --enable
```

The installer clones into
`~/.config/omarchy/plugins/io.github.alennumberoneai.mouse` and prompts for a
bar section (left / center / right).

## Update

```bash
omarchy plugin update io.github.alennumberoneai.mouse
```

## Remove

```bash
omarchy plugin remove io.github.alennumberoneai.mouse
```

## Usage

Click the 󰍽 icon in the bar to open the panel. Drag a slider or flip a
toggle — the change takes effect immediately. Right-click the bar icon to
re-read current values from Hyprland.

## License

MIT — see [LICENSE](LICENSE).
