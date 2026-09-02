# Running NinjaTrader 8 on Omarchy

A working setup for NinjaTrader 8 under Wine on Omarchy (Arch + Hyprland),
including the window-management work needed to make its charts behave.

Verified on: Omarchy / Hyprland 0.56.2, Wine 11.16, NT8 8.1.8.2, DXVK 3.1,
NVIDIA RTX 2080 SUPER (proprietary driver), single 2560x1440 display.

> **Scope.** NinjaTrader does not support Linux. Charting, order entry and
> market replay work; see [Limitations](#limitations) for what does not. Do your
> own risk assessment before trading real money through it.

---

## What's in this repo

| Path | |
|---|---|
| `hypr/window-rules.lua` | The two static rules: make charts tile, make the mouse work |
| `hypr/ninjatrader.lua` | Optional handler routing charts to workspaces by instrument |
| `omarchy/` | The two bar workspace widgets, with setup notes |

---

## 1. Install Wine and dependencies

```bash
sudo pacman -S wine winetricks p7zip
yay -S dxvk-bin        # d3d9 -> Vulkan; WPF renders through Direct3D 9
```

## 2. Create a dedicated prefix

Keep NT8 in its own prefix so nothing else can disturb it.

```bash
export WINEPREFIX=~/.wine-nt8
winecfg                 # set Windows version to Windows 10
```

## 3. Install .NET Framework 4.8

NT8 targets **.NET Framework 4.8**, which is Windows-only and unrelated to
modern cross-platform .NET. Wine-Mono is not sufficient — install the real
thing:

```bash
WINEPREFIX=~/.wine-nt8 winetricks -q dotnet48 corefonts
```

The installer refuses to run below release `528040`; `winetricks dotnet48`
satisfies this.

## 4. Install DXVK into the prefix

```bash
cd /path/to/dxvk
./setup_dxvk.sh install --symlink --wineprefix ~/.wine-nt8
```

## 5. Install NT8 — skipping the WebView2 bootstrapper

**A plain install fails.** The MSI runs a custom action `InstallWV2` that
bootstraps the Microsoft Edge WebView2 runtime. That bootstrapper needs a
privileged COM "elevator" service that does not exist under Wine, so it dies and
takes the whole install with it:

```
err:msi:execute_script Execution of script 0 halted; action L"InstallWV2" returned 1627
err:msi:ITERATE_Actions Execution halted, action L"InstallFinalize" returned 1627
```

The action is gated on a condition:

```
InstallWV2   NOT (REMOVE OR WVRTINSTALLEDLM OR WVRTINSTALLEDCU)
```

Set the property yourself and the action is skipped:

```bash
WINEPREFIX=~/.wine-nt8 wine msiexec /i ~/Downloads/NinjaTrader.Install.msi \
  WVRTINSTALLEDLM=1 /qb /L*v ~/nt8-install.log
```

Confirm with `Action ended … InstallFinalize. Return value 1.` in the log.

> Prefer this over faking the registry key that the installer probes. The
> property leaves the registry honest, so NT8's own runtime check still
> correctly concludes WebView2 is absent instead of being pointed at a path
> that does not exist.

NT8 lands in `~/.wine-nt8/drive_c/Program Files/NinjaTrader 8/bin/` (note:
`bin`, not `bin64`).

## 6. Fix the black window

Launched as-is, NT8 maps a window that renders **completely black**. This is not
a broken renderer — DXVK creates a healthy D3D9Ex device and logs no errors. The
failure is in the **XWayland presentation path**, and the tell is:

```
MESA-EGL: warning: pci id for fd 31: 10de:1e81, driver (null)
MESA-EGL: warning: egl: failed to create dri2 screen
```

Force WPF's software rasteriser:

```bash
WINEPREFIX=~/.wine-nt8 wine reg add "HKCU\Software\Microsoft\Avalon.Graphics" \
  /v DisableHWAcceleration /t REG_DWORD /d 1 /f
```

The cost is CPU-bound chart redraws. See [Limitations](#limitations).

## 7. Launch

```bash
WINEPREFIX=~/.wine-nt8 wine "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
```

---

## 8. Making the windows behave

Everything below is Hyprland configuration, and all of it follows from one fact.

### The two-window architecture

**Every NT8 chart is two X11 windows:**

| Window | Title | Role |
|---|---|---|
| Frame | `Chart - MNQ SEP26` | **Owns all mouse input**; draws side panels (e.g. Chart Trader) |
| Renderer | *(empty)* | **Draws the chart only**; handles no input |

The frame is `WM_TRANSIENT_FOR` the renderer, and the renderer sits inset at
frame `+{8,31}`. Wine keeps their geometry in sync, but a **workspace** is a
window-manager concept an X client cannot see — so moving one without the other
splits them. The symptoms are diagnostic:

- Chart shows an **empty hole** that still opens context menus → you moved the
  frame and left the renderer behind.
- Chart is **visible but ignores the mouse** → you are clicking the renderer.

### Make charts tile

They arrive with `WM_TRANSIENT_FOR` set, so Hyprland floats them like dialogs.

```lua
o.window({ class = "ninjatrader\\.exe", title = "Chart - .*" }, { tile = true })
```

> **Patterns must match the whole string.** `title = "^Chart - "` never matches
> `Chart - MNQ SEP26`. This is the single most expensive mistake to make here,
> because `hl.window_rule` **silently accepts** bad keys and patterns — no
> error, nothing in `hyprctl configerrors`, the rule just never fires.

### Make the mouse work

The renderer floats on top of the frame and swallows every click. Mark it
unfocusable so events fall through:

```lua
o.window({ class = "ninjatrader\\.exe", title = "" }, { no_focus = true })
```

Omarchy does this for XWayland helpers in `default/hypr/windows.lua`, but that
rule only matches an *empty* class and NT8's helpers carry a real one.

### Verifying a rule actually matches

Never assume. Apply a tag and read it back — this needs no new windows:

```bash
hyprctl eval 'hl.window_rule({ tag = "+probe", match = { class = "foo" } }) return "ok"'
hyprctl clients -j | grep -A2 tags
hyprctl eval 'hl.window_rule({ tag = "-probe", match = { class = "foo" } }) return "ok"'
```

`hyprctl eval` runs arbitrary Lua but only prints `ok`; write results to a file
with `io.open` to see them.

---

## 9. Optional: route charts to workspaces by instrument

A static rule **cannot** do this: the renderer has no title to match on, so it
can only be identified geometrically. That requires a handler.

Save as `~/.config/hypr/ninjatrader.lua` and add `require("hypr.ninjatrader")`
to `hyprland.lua`. Full source: see the file itself; the essential design points
are:

- Match on `hl.on("window.open")` and `hl.on("window.title")`, filtering by
  class first — terminals retitle constantly and will flood the handler.
- Defer with `hl.timer` (~250 ms). Geometry is not settled when the event fires.
- Move the **renderer first**, then the frame.
- Pair by **position**, using size only to break ties. Size must never gate the
  match: a chart with a Chart Trader panel has a renderer ~200 px narrower than
  `frame - {14,78}`, and gating on size strands it permanently.
- Run a **reconcile** pass afterwards. Moving one chart reflows the layout, so
  the next chart's frame shifts before Wine re-syncs its renderer. Reconcile
  pulls any renderer back to its frame's workspace, and refuses to act when a
  renderer matches two frames equally rather than guessing.
- Route only *persistent* tool windows (Control Center, Market Analyzer, …).
  Leave transient dialogs alone so they open where you are working.

## 10. Optional: workspace indicators in the bar

Hyprland creates workspaces on demand — there is no "number of workspaces"
setting. Two hardcoded spots cap you at 10, both package-owned and overwritten
on update:

- `/usr/share/omarchy/default/hypr/bindings/tiling.lua` — `for workspace = 1, 10`
- `/usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml` — `workspaceIds()`

Never edit those. Clone instead:

```bash
omarchy plugin clone omarchy.workspaces
# -> ~/.config/omarchy/plugins/<user>.workspaces/
```

Then edit `workspaceIds()` for the range and add a label map:

```qml
readonly property var labels: ({ 8: "ES", 9: "NQ", 10: "0", 11: "$" })

text: root.labels[modelData] !== undefined ? root.labels[modelData]
                                           : (focused ? "\uDB85\uDCFB" : String(modelData))
active: focused
```

Placement lives in `~/.config/omarchy/shell.json` under `bar.layout`
(`left` / `center` / `right`); `centerAnchor` pins one widget to true centre, so
items after it in `center` render to its right.

To show workspaces on **both** sides of the clock you need two widget instances.
`allowMultiple: false` blocks reusing one id, so copy the plugin directory and
change `id` (and `moduleName`) in the copy.

> Widget **code** changes need a full `omarchy restart shell`. Hot-reload and
> `omarchy-shell shell rescanPlugins` silently ignore them. `shell.json` layout
> changes *do* hot-reload.

A workspace above 10 has no `SUPER`+key binding — reach it by clicking its bar
indicator, or add a binding in `~/.config/hypr/bindings.lua`.

---

## Limitations

- **No GPU rendering.** WPF runs on its software rasteriser, so chart redraws
  are CPU-bound. Test a busy chart under live ticks before committing.
- **WebView2 panels do not work** — anything embedding a browser is dead. Charts
  and order entry are pure WPF and unaffected.
- **Broker passwords do not migrate** from a Windows machine. NT8 encrypts
  credentials, and if it uses Windows DPAPI the key is bound to that user and
  machine. Copy `Config.xml`, `db/NinjaTrader.sqlite`, `workspaces/`,
  `templates/` and `bin/Custom/` (sources, let NT8 recompile), then re-enter
  passwords. Prefer NT8's own Backup/Restore, and close NT8 on both ends first —
  it rewrites `Config.xml` on exit.

### Do not bother with Wine's Wayland driver

Setting `HKCU\Software\Wine\Drivers` → `Graphics = wayland` **does** run NT8 as
a native Wayland client and **renders perfectly with hardware WPF** — proving
the black window is an XWayland bug, not a WPF one.

But **login hangs**: the button sticks on "Loading.", the HTTPS connection to
the auth host establishes then goes idle, a thread spins ~42% CPU, and no
further window ever maps. Reproduced with both hardware and software WPF, so it
is the driver, not rendering. Revert with:

```bash
WINEPREFIX=~/.wine-nt8 wine reg delete "HKCU\Software\Wine\Drivers" /v Graphics /f
```

Worth retesting after a Wine update — it is two registry values, and it is the
only known path back to GPU rendering.
