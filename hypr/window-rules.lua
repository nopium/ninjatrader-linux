-- NinjaTrader window rules. Paste into ~/.config/hypr/hyprland.lua, or keep in
-- its own file and require() it.
--
-- Patterns must match the WHOLE string -- a "^Chart - " prefix never matches
-- "Chart - MNQ SEP26". hl.window_rule silently accepts bad keys and patterns,
-- so a wrong rule fails with no error anywhere. Verify with a tag probe:
--
--   hyprctl eval 'hl.window_rule({ tag = "+probe", match = { class = "..." } }) return "ok"'
--   hyprctl clients -j | grep -A2 tags

-- Charts are WPF owned-windows, so they reach XWayland with WM_TRANSIENT_FOR
-- set and Hyprland floats them like dialogs.
o.window({ class = "ninjatrader\\.exe", title = "Chart - .*" }, { tile = true })

-- Each chart is TWO X11 windows: an untitled renderer that only draws, and this
-- titled frame that owns all mouse input. The renderer floats on top, so it
-- swallows every click unless made unfocusable -- without this, right-click on
-- a chart silently does nothing.
--
-- Omarchy does the same for XWayland helpers in default/hypr/windows.lua, but
-- that rule only matches an empty class and NinjaTrader's helpers carry a real
-- one.
o.window({ class = "ninjatrader\\.exe", title = "" }, { no_focus = true })
