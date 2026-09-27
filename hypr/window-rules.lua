-- NinjaTrader window rules. Paste into ~/.config/hypr/hyprland.lua, or keep in
-- its own file and require() it.
--
-- Patterns must match the WHOLE string -- a "^Chart - " prefix never matches
-- "Chart - MNQ SEP26". hl.window_rule validates match property NAMES, but not
-- rule keys and not patterns, so a wrong rule or a non-matching pattern fails
-- with no error anywhere. Verify with a tag probe:
--
--   hyprctl eval 'hl.window_rule({ tag = "+probe", match = { class = "..." } }) return "ok"'
--   hyprctl clients -j | grep -A2 tags

-- Charts are WPF owned-windows, so they reach XWayland with WM_TRANSIENT_FOR
-- set and Hyprland floats them like dialogs.
o.window({ class = "ninjatrader\\.exe", title = "Chart - .*" }, { tile = true })

-- Each chart is TWO X11 windows: an untitled renderer that only draws, and this
-- titled frame that owns all mouse input. The renderer floats on top, so it
-- swallows every click unless made unfocusable.
--
-- That is deliberately NOT done here. A static rule matching every untitled
-- NinjaTrader window also matches its menus, and a WPF menu that cannot take
-- focus closes the instant it opens -- every Control Center menu flashes up for
-- a second and vanishes. ninjatrader.lua marks only windows positively
-- identified as a renderer, via set_prop on that one window.
