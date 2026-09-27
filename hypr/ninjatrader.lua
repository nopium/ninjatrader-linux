-- NinjaTrader window routing: charts by instrument, service windows together.
--
-- Why this is a handler and not a static window rule:
--
-- Each chart is really TWO X11 windows -- an untitled one that does the actual
-- rendering, plus a titled frame that is transient for it. Wine keeps their
-- geometry in sync (the renderer nests inside the frame), so tiling works, but it
-- cannot follow a workspace move: moving only the frame leaves the renderer
-- behind and the chart shows an empty hole. Both must move together, and the
-- untitled one has no title to match on -- so it can only be found
-- geometrically, which a static rule cannot do.

local NT_CLASS = "ninjatrader.exe"
local SERVICE_WS = 11
local INSTRUMENT_WS = { { "NQ", 9 }, { "ES", 8 } }

-- Persistent tool windows. Transient dialogs (Data Series, Error, property
-- sheets) are deliberately absent: they should pop up where you are working,
-- not get yanked to the service workspace. Add prefixes here to route more.
local SERVICE_PREFIXES = {
  "Control Center",
  "Market Analyzer",
  "Option Chain",
  "Playback",
  "Chat",
}

local EDGE_SLOP = 8
local MIN_FILL = 0.5
local SETTLE_MS = 250

-- Only chart windows own a renderer; service windows are a single window. This
-- is the constraint that disambiguates a stranded renderer when two workspaces
-- happen to share a layout -- geometry alone cannot tell those apart, because
-- every workspace tiles from the same origin at the same size.
local function is_chart(win)
  return ((win.title or ""):match("^Chart %- ")) ~= nil
end

local function target_ws(title)
  local instrument = title:match("^Chart %- (.+)$")
  if instrument then
    for _, pair in ipairs(INSTRUMENT_WS) do
      if instrument:find(pair[1], 1, true) then
        return pair[2]
      end
    end
    return nil -- a chart we have no home for: leave it alone
  end

  for _, prefix in ipairs(SERVICE_PREFIXES) do
    if title:sub(1, #prefix) == prefix then
      return SERVICE_WS
    end
  end
  return nil
end

local function nt_windows()
  local out = {}
  for _, w in ipairs(hl.get_windows()) do
    if w.class == NT_CLASS then
      out[#out + 1] = w
    end
  end
  return out
end

-- Match the renderer to its frame by CONTAINMENT, not by a fixed inset.
--
-- The inset is decoration geometry, not a constant: it measured {8,31} under
-- one Hyprland border/gap config and {5,19} after those changed. Hardcoding it
-- silently strands every chart the day it shifts -- the rule stops matching,
-- and a no-op is indistinguishable from "already in the right place". What is
-- actually invariant is that the renderer nests inside its frame's rectangle.
local function nests_in(frame, content)
  return content.at.x >= frame.at.x - EDGE_SLOP
    and content.at.y >= frame.at.y - EDGE_SLOP
    and content.at.x + content.size.x <= frame.at.x + frame.size.x + EDGE_SLOP
    and content.at.y + content.size.y <= frame.at.y + frame.size.y + EDGE_SLOP
    and content.size.x <= frame.size.x
    and content.size.y <= frame.size.y
    -- A renderer very nearly fills its frame. Menus are untitled NinjaTrader
    -- windows that also nest inside one, and are small; this keeps them out.
    and (content.size.x * content.size.y) >= (frame.size.x * frame.size.y) * MIN_FILL
end

-- Leftover frame around the renderer. The true pair is the tightest fit, which
-- is what separates a chart from a larger window it happens to sit inside.
local function slack(frame, content)
  return (frame.size.x - content.size.x) + (frame.size.y - content.size.y)
end

local function content_for(frame, windows)
  local best, best_slack
  for _, w in ipairs(windows) do
    if (w.title or "") == "" and w.address ~= frame.address and nests_in(frame, w) then
      local s = slack(frame, w)
      if not best or s < best_slack then
        best, best_slack = w, s
      end
    end
  end
  return best
end

local function move(win, ws)
  hl.dispatch(hl.dsp.window.move({
    workspace = tostring(ws),
    window = "address:" .. win.address,
    follow = false,
  }))
end

-- Reverse of content_for. Refuses to act on an exact tie rather than guessing,
-- since a wrong guess drags a renderer off its own chart.
local function frame_for(content, windows)
  local best, best_slack, tied
  for _, w in ipairs(windows) do
    if is_chart(w) and w.address ~= content.address and nests_in(w, content) then
      local s = slack(w, content)
      if not best or s < best_slack then
        best, best_slack, tied = w, s, false
      elseif s == best_slack then
        tied = true
      end
    end
  end
  if tied then
    return nil
  end
  return best
end

-- Moving one chart reflows the layout, so a second chart's frame can shift
-- before Wine has re-synced its renderer -- and the positional pairing misses,
-- stranding the renderer. Pull any renderer back to its frame's workspace.
local function reconcile()
  local windows = nt_windows()
  for _, w in ipairs(windows) do
    if (w.title or "") == "" and w.workspace then
      local frame = frame_for(w, windows)
      if frame and frame.workspace and frame.workspace.id ~= w.workspace.id then
        move(w, frame.workspace.id)
      end
    end
  end
end

-- A renderer floats on top of its frame and swallows every click, so it has to
-- be unfocusable. This is done per-window rather than by a static rule because
-- menus are untitled NinjaTrader windows too -- a blanket rule makes every menu
-- close the moment it opens.
local function mark_renderers()
  local windows = nt_windows()
  for _, w in ipairs(windows) do
    if (w.title or "") == "" and frame_for(w, windows) then
      hl.dispatch(hl.dsp.window.set_prop({
        window = "address:" .. w.address,
        prop = "no_focus",
        value = 1,
      }))
    end
  end
end

local function route(address)
  local windows = nt_windows()

  local frame
  for _, w in ipairs(windows) do
    if w.address == address then
      frame = w
      break
    end
  end
  if not frame then
    return
  end

  local title = frame.title or ""
  if title == "" then
    return -- a renderer window; it travels with its frame
  end

  local ws = target_ws(title)
  if not ws or (frame.workspace and frame.workspace.id == ws) then
    return
  end

  -- Renderer first, so it is never briefly stranded on its own. Service windows
  -- have none, and looking anyway risks dragging an unrelated window along.
  if is_chart(frame) then
    local content = content_for(frame, windows)
    if content then
      move(content, ws)
    end
  end
  move(frame, ws)
end

local function on_window(win)
  if not win or win.class ~= NT_CLASS then
    return
  end
  -- Geometry is not settled when the event fires, and the pairing is
  -- positional, so let the layout land before looking for the partner.
  local address = win.address
  hl.timer(function()
    route(address)
    hl.timer(function()
      reconcile()
      mark_renderers()
    end, { timeout = SETTLE_MS, type = "oneshot" })
  end, { timeout = SETTLE_MS, type = "oneshot" })
end

hl.on("window.open", on_window)
hl.on("window.title", on_window)

-- Place anything already open (also runs on each config reload; it is a no-op
-- for windows that are already where they belong).
hl.timer(function()
  for _, w in ipairs(nt_windows()) do
    route(w.address)
  end
  hl.timer(function()
    reconcile()
    mark_renderers()
  end, { timeout = SETTLE_MS, type = "oneshot" })
end, { timeout = SETTLE_MS, type = "oneshot" })
