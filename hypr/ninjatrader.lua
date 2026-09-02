-- NinjaTrader window routing: charts by instrument, service windows together.
--
-- Why this is a handler and not a static window rule:
--
-- Each chart is really TWO X11 windows -- an untitled one that does the actual
-- rendering, plus a titled frame that is transient for it. Wine keeps their
-- geometry in sync (content sits at frame + {8, 31}), so tiling works, but it
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

local CONTENT_DX, CONTENT_DY = 8, 31
local CONTENT_DW, CONTENT_DH = 14, 78
local MATCH_SLOP = 4
local SETTLE_MS = 250

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

-- The renderer sits inset inside its frame by a fixed amount.
--
-- Position is the primary test and size only breaks ties. Size must NOT gate
-- the match: a stranded renderer often carries a stale width, and requiring an
-- exact size match is exactly what leaves it stranded. Position alone is
-- ambiguous across workspaces though (every workspace lays out from the same
-- origin), which is what size is for.
local function position_matches(frame, content)
  return math.abs(content.at.x - (frame.at.x + CONTENT_DX)) <= MATCH_SLOP
    and math.abs(content.at.y - (frame.at.y + CONTENT_DY)) <= MATCH_SLOP
end

local function size_matches(frame, content)
  return math.abs(content.size.x - (frame.size.x - CONTENT_DW)) <= MATCH_SLOP
    and math.abs(content.size.y - (frame.size.y - CONTENT_DH)) <= MATCH_SLOP
end

local function content_for(frame, windows)
  local matches = {}
  for _, w in ipairs(windows) do
    if (w.title or "") == "" and w.address ~= frame.address and position_matches(frame, w) then
      matches[#matches + 1] = w
    end
  end
  if #matches <= 1 then
    return matches[1]
  end
  for _, w in ipairs(matches) do
    if size_matches(frame, w) then
      return w
    end
  end
end

local function move(win, ws)
  hl.dispatch(hl.dsp.window.move({
    workspace = tostring(ws),
    window = "address:" .. win.address,
    follow = false,
  }))
end

-- Reverse of content_for. Refuses to act on a tie rather than guessing, since
-- a wrong guess drags a renderer off its own chart.
local function frame_for(content, windows)
  local matches = {}
  for _, w in ipairs(windows) do
    if (w.title or "") ~= "" and w.address ~= content.address and position_matches(w, content) then
      matches[#matches + 1] = w
    end
  end
  if #matches <= 1 then
    return matches[1]
  end

  local sized
  for _, w in ipairs(matches) do
    if size_matches(w, content) then
      if sized then
        return nil
      end
      sized = w
    end
  end
  return sized
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

  -- Renderer first, so it is never briefly stranded on its own.
  local content = content_for(frame, windows)
  if content then
    move(content, ws)
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
    hl.timer(reconcile, { timeout = SETTLE_MS, type = "oneshot" })
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
  hl.timer(reconcile, { timeout = SETTLE_MS, type = "oneshot" })
end, { timeout = SETTLE_MS, type = "oneshot" })
