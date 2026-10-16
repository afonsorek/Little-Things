-- @description Little Things - Launchpad Chop Engine for REAPER
-- @version 2.2
-- @author Little Things (Afonso Rekbaim, Erick Martins)
-- @about
--   Launchpad MK3 Chop Engine - Instant sampling & chopping from timeline to pads.
--   - [SEND]  Send timeline range to the selected pad (time selection is cleared afterwards)
--   - [CHOP]  Chop a range into 8/16/32/64 pads (spills over to the next pages)
--   - [ITEMS] Load every audio item of the source track into consecutive pads
--   - Pages: Launchpad arrows (or the scene buttons) switch page, up to 8 pages
--   - Gate / One-Shot / Loop (Hold or Toggle)
--   - Multi-select (Shift = range, Ctrl/Cmd = one by one) and drag to move pads
--   - Kits: save / export / import with the chopped audio included (portable)
--   - Runs in background when the window is closed. Delete the "LT Chops" track to stop it.
--
--   v2.2: animation per pad (type, color incl. rainbow, speed, preview) in the pad menu;
--         special pads: Metronome (blinks on the DAW beat, press = metronome on/off) and Stop sound.
--   v2.1: Launchpad animations (Flash / Ripple / Cross / Sparkle), 8 pages always available,
--         LED watchdog + single LED path (pads losing their color), 14 px drag threshold,
--         Backspace no longer deletes pads.
--   v2.0.2: only one engine can drive the Launchpad (a newer one retires the older); own
--           window id so an old v1.x window can no longer hide behind it; LED resync after kit load.
--   v2.0.1: the shortcut / action reopens the window (relaunch was being ignored).
--   v2.0: pages, router JSFX (auto-installed), loop toggle, multi-select, drag-move, portable
--   kits, background engine, settings panel, collapsible inspector, color picker, credits.
--   v1.6: choke cuts fade out (release) instead of hard-cutting.
--   v1.5: micro-fade (attack/release) on every pad.

--------------------------------------------------------------------------------
-- CONFIG & CONSTANTS
--------------------------------------------------------------------------------

local SCRIPT_NAME = "Little Things - Launchpad Chop Engine"
local SCRIPT_VERSION = "2.2"
local EXT_SECTION = "LittleThings_ChopEngine"
local TRACK_NAME = "LT Chops"
local HW_ROWS, HW_COLS = 8, 8
local PAGE_SIZE = HW_ROWS * HW_COLS
local MAX_PAGES = 8
local NUM_PADS = PAGE_SIZE * MAX_PAGES
local RS5K_NAME = "ReaSamplOmatic5000"
local ROUTER_TAG = "Launchpad Router"
local ROUTER_DIR = "LittleThings"
local ROUTER_FILE = "LittleThings_Launchpad_Router.jsfx"
local FLASH_TIME = 0.15
local PERSIST_INTERVAL = 1.0
local HEARTBEAT_INTERVAL = 0.5
local ROUTER_RESYNC_INTERVAL = 2.0

local CREDITS = {
  { name = "Erick",  handle = "erickk_martins", url = "https://www.instagram.com/erickk_martins/" },
  { name = "Afonso", handle = "afonsorek",      url = "https://www.instagram.com/afonsorek/" },
}

local GRID_PRESETS = {
  { rows = 8, cols = 8, name = "8x8 (64 pads)" },
  { rows = 4, cols = 8, name = "4x8 (32 pads)" },
  { rows = 8, cols = 4, name = "8x4 (32 pads)" },
  { rows = 4, cols = 4, name = "4x4 (16 pads)" },
}

local floor, max, min = math.floor, math.max, math.min

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- MK3 Programmer Mode note mapping: Row 0 (top) = notes 81-88, Row 7 (bottom) = 11-18
local function mk3_note_for_pad(row, col)
  return (8 - row) * 10 + (col + 1)
end

-- Right column (scene) buttons: index 0 (top) = 89 ... index 7 (bottom) = 19
local function mk3_cc_for_scene(index)
  return (8 - index) * 10 + 9
end

-- Top row: 91 = Up, 92 = Down, 93 = Left, 94 = Right, 95..98 = Session/Drums/Keys/User
local CC_UP, CC_DOWN, CC_LEFT, CC_RIGHT = 91, 92, 93, 94

-- Launchpad Color Palette (velocity -> 0xRRGGBBAA hex color for GUI display)
local PALETTE = {
  { vel = 0,  name = "Off",          hex = 0x22242DFF },
  { vel = 5,  name = "Bright Red",   hex = 0xFF2D55FF },
  { vel = 6,  name = "Red",          hex = 0xD62246FF },
  { vel = 7,  name = "Dim Red",      hex = 0x8E1630FF },
  { vel = 9,  name = "Orange",       hex = 0xFF9500FF },
  { vel = 10, name = "Warm Amber",   hex = 0xE07A00FF },
  { vel = 11, name = "Dim Amber",    hex = 0x945100FF },
  { vel = 13, name = "Yellow",       hex = 0xFFCC00FF },
  { vel = 14, name = "Soft Yellow",  hex = 0xD4A900FF },
  { vel = 17, name = "Lime",         hex = 0xA4E000FF },
  { vel = 21, name = "Bright Green", hex = 0x34C759FF },
  { vel = 22, name = "Green",        hex = 0x248A3DFF },
  { vel = 23, name = "Dim Green",    hex = 0x145224FF },
  { vel = 29, name = "Mint / Teal",  hex = 0x00C7BEFF },
  { vel = 33, name = "Light Cyan",   hex = 0x32ADE6FF },
  { vel = 37, name = "Cyan",         hex = 0x007AFFFF },
  { vel = 45, name = "Deep Blue",    hex = 0x1B58F4FF },
  { vel = 46, name = "Navy Blue",    hex = 0x133EADFF },
  { vel = 49, name = "Indigo",       hex = 0x5856D6FF },
  { vel = 53, name = "Violet",       hex = 0xAF52DEFF },
  { vel = 54, name = "Purple",       hex = 0x893CAEFF },
  { vel = 57, name = "Bright Pink",  hex = 0xFF3B8AFF },
  { vel = 58, name = "Rose",         hex = 0xD12D70FF },
  { vel = 3,  name = "White",        hex = 0xFFFFFFFF },
  { vel = 2,  name = "Silver",       hex = 0xC7C7CCFF },
  { vel = 1,  name = "Dim White",    hex = 0x636366FF },
}

local CHOP_COLORS = { 9, 13, 21, 29, 37, 45, 53, 57 }

local VEL_TO_COLOR, VEL_TO_NAME = {}, {}
for _, c in ipairs(PALETTE) do
  VEL_TO_COLOR[c.vel] = c.hex
  VEL_TO_NAME[c.vel] = c.name
end

local function get_color_for_vel(vel) return VEL_TO_COLOR[vel] or 0x007AFFFF end
local function get_name_for_vel(vel) return VEL_TO_NAME[vel] or ("Color " .. tostring(vel)) end

local function brighten_color(rgba, factor)
  local r = (rgba >> 24) & 0xFF
  local g = (rgba >> 16) & 0xFF
  local b = (rgba >> 8) & 0xFF
  local a = rgba & 0xFF
  r = min(255, floor(r * factor + 20))
  g = min(255, floor(g * factor + 20))
  b = min(255, floor(b * factor + 20))
  return (r << 24) | (g << 16) | (b << 8) | a
end

-- Playback modes: 1=Gate (stop on release), 2=One-Shot, 3=Loop (Hold or Toggle)
local MODES = { "Gate", "1-Shot", "Loop" }

--------------------------------------------------------------------------------
-- SMALL UTILITIES
--------------------------------------------------------------------------------

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function copy_file(src, dst)
  if src == dst then return true end
  local fin = io.open(src, "rb")
  if not fin then return false end
  local fout = io.open(dst, "wb")
  if not fout then fin:close() return false end
  while true do
    local chunk = fin:read(1024 * 1024)
    if not chunk then break end
    fout:write(chunk)
  end
  fin:close()
  fout:close()
  return true
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function basename(path)
  return (path or ""):match("([^/\\]+)$") or (path or "")
end

local function dirname(path)
  return (path or ""):match("^(.*)[/\\]") or ""
end

local function strip_ext(name)
  return (name:gsub("%.%w+$", ""))
end

local function safe_name(s)
  local r = (tostring(s or ""):gsub("[^%w_%-]", "_"))
  if r == "" then r = "Kit" end
  return r
end

local function is_abs_path(p)
  return p:match("^/") ~= nil or p:match("^%a:[/\\]") ~= nil or p:match("^\\\\") ~= nil
end

-- Escape a string so it never contains the separators used by the persisted state
local function esc(s)
  return (tostring(s or ""):gsub("[%%|;=%c]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

local function unesc(s)
  return ((s or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do
    out[#out + 1] = part
  end
  return out
end

local function is_mac()
  local os_name = (reaper.GetOS() or ""):lower()
  return os_name:find("osx", 1, true) ~= nil or os_name:find("mac", 1, true) ~= nil
end

local function open_url(url)
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(url)
    return
  end
  local os_name = (reaper.GetOS() or ""):lower()
  if os_name:find("win", 1, true) then
    os.execute('start "" "' .. url .. '"')
  elseif is_mac() then
    os.execute('open "' .. url .. '"')
  else
    os.execute('xdg-open "' .. url .. '" &')
  end
end

-- Finds a native action by (part of) its name, so no command ID is ever guessed wrong
local action_cache = {}
local function find_action(wanted, candidates)
  wanted = wanted:lower()
  if action_cache[wanted] ~= nil then return action_cache[wanted] or nil end
  local found = false
  pcall(function()
    local section = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0) or nil
    if reaper.kbd_getTextFromCmd then
      for _, id in ipairs(candidates or {}) do
        local t = reaper.kbd_getTextFromCmd(id, section)
        if t and t:lower():find(wanted, 1, true) then found = id return end
      end
    end
    if reaper.kbd_enumerateActions and section then
      local i = 0
      while i < 100000 do
        local id, name = reaper.kbd_enumerateActions(section, i)
        if not id or id == 0 then break end
        if name and name:lower():find(wanted, 1, true) then found = id return end
        i = i + 1
      end
    end
  end)
  action_cache[wanted] = found
  return found or nil
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local pads = {}                 -- NUM_PADS pad configs (8 pages x 64)
local note_to_local = {}        -- MK3 note -> local index 1..64
local selected_pad = 1          -- focused pad (inspector)
local selection = { [1] = true }
local sel_anchor = 1
local pending_collapse = nil
local current_page = 1
local num_pages = 1
local grid_rows, grid_cols = 8, 8
local current_kit_name = "Soul Chops 01"
local master_volume = 1.0
local status_msg = "Ready - select a timeline range and send it to a pad"
local status_color_hex = 0x34C759FF

-- Chop options
local chop_division = 16
local chop_choke = true
local auto_advance = true
local default_chop_mode = 2
local auto_mute_source_track = false
local fade_ms = 3
local auto_reset_midi = true

-- MIDI device state
local midi_out_device, midi_out_name = -1, ""
local midi_in_device, midi_in_name = -1, ""
local midi_connected = false
local midi_disabled_hint = false
local available_midi_ins, available_midi_outs = {}, {}
local saved_midi_out, saved_midi_in = "", ""
local last_midi_seq = nil
local next_midi_scan = 0
local midi_reset_done = false

-- Track / instances
local rs5k_track = nil
local rs5k_fx_indices = {}      -- pad_idx -> fx index
local rs5k_guids = {}           -- pad_idx -> fx GUID (detects shifted indices)
local rs5k_ready = false
local adopt_pending = false

-- Router JSFX
local router_idx = -1
local router_counter = nil
local router_cmd_counter = nil
local router_flags_dirty = true
local next_router_resync = 0
local router_error_shown = false

-- Playback tracking
local active_until = {}
local pressed_pads = {}
local flash_timers = {}
local last_hit = {}
local ui_held = {}
local hw_note_pad = {}
local led_cache = {}
local cc_cache = {}
local pending_led_sync = nil
local choke_pending = {}

-- Engine / persistence
local last_saved_pads = ""
local last_saved_settings = ""
local next_persist_time = 0
local next_heartbeat = 0
local shut_down = false
local cur_proj = nil
local engine_active = false

-- UI
local ctx = nil
local font_main = nil
local ui_visible = true
local focus_request = false
local imgui_available = false
local instance_id = ""          -- this engine's id; only the owner may drive the Launchpad

local function set_status(msg, color)
  status_msg = msg
  status_color_hex = color or 0x34C759FF
end

--------------------------------------------------------------------------------
-- PAD DATA STRUCTURE & INDEXING
--------------------------------------------------------------------------------

local function pad_page(idx) return (idx - 1) // PAGE_SIZE + 1 end
local function pad_local(idx) return (idx - 1) % PAGE_SIZE + 1 end
local function page_pad(page, li) return (page - 1) * PAGE_SIZE + li end

for r = 0, HW_ROWS - 1 do
  for c = 0, HW_COLS - 1 do
    note_to_local[mk3_note_for_pad(r, c)] = r * HW_COLS + c + 1
  end
end

local function default_label(row, col)
  return string.format("Pad %d,%d", row + 1, col + 1)
end

local function is_default_label(label)
  return label == nil or label == "" or label:match("^Pad %d+,%d+$") ~= nil
end

local function create_pad(idx)
  local li = pad_local(idx)
  local row, col = (li - 1) // HW_COLS, (li - 1) % HW_COLS
  return {
    idx = idx,
    page = pad_page(idx),       -- RS5K listens on MIDI channel page + 1
    row = row,
    col = col,
    label = default_label(row, col),
    sample_path = "",
    start_offs = 0.0,
    end_offs = 1.0,
    color_vel = 0,
    mode = 2,
    loop_toggle = false,
    volume = 1.0,
    velocity_sensitive = false,
    pitch_semitones = 0,
    pitch_rate = 1.0,
    release_ms = 0.0,
    choke_group = 1,
    midi_note = mk3_note_for_pad(row, col),
    is_bounced = false,
    role = 1,                   -- 1 sample pad, 2 metronome, 3 stop sound
    anim_type = 3,              -- 1 Off, 2 Flash, 3 Ripple, 4 Cross, 5 Sparkle
    anim_color = -1,            -- -1 pad color, -2 rainbow, >= 0 Launchpad palette velocity
    anim_speed = 2,             -- 1 slow, 2 normal, 3 fast
  }
end

local CONTENT_KEYS = {
  "label", "sample_path", "start_offs", "end_offs", "color_vel", "mode", "loop_toggle",
  "volume", "velocity_sensitive", "pitch_semitones", "pitch_rate", "release_ms",
  "choke_group", "is_bounced", "role", "anim_type", "anim_color", "anim_speed",
}

local function get_content(p)
  local t = {}
  for _, k in ipairs(CONTENT_KEYS) do t[k] = p[k] end
  return t
end

local function set_content(p, t)
  for _, k in ipairs(CONTENT_KEYS) do p[k] = t[k] end
  if is_default_label(p.label) then p.label = default_label(p.row, p.col) end
end

local function reset_pad_content(p)
  set_content(p, get_content(create_pad(p.idx)))
end

local function init_pads()
  pads = {}
  for i = 1, NUM_PADS do pads[i] = create_pad(i) end
end

local function pad_is_default(p)
  return p.sample_path == "" and is_default_label(p.label) and p.color_vel == 0 and p.mode == 2
    and not p.loop_toggle and p.volume == 1.0 and not p.velocity_sensitive
    and p.pitch_semitones == 0 and p.choke_group == 1
    and p.role == 1 and p.anim_type == 3 and p.anim_color == -1 and p.anim_speed == 2
end

local function is_visible(idx)
  local p = pads[idx]
  return p ~= nil and p.row < grid_rows and p.col < grid_cols
end

local function is_toggle(idx)
  local p = pads[idx]
  return p ~= nil and p.role == 1 and p.mode == 3 and p.loop_toggle == true
end

-- Pads that can receive chops / items (special pads are skipped)
local function is_sample_slot(idx)
  return is_visible(idx) and pads[idx].role == 1
end

local function apply_capture_defaults(pad, choke_group)
  pad.mode = default_chop_mode
  pad.loop_toggle = false
  pad.volume = 1.0
  pad.velocity_sensitive = false
  pad.pitch_semitones = 0
  pad.release_ms = 0.0
  pad.choke_group = choke_group
end

-- Visible pads in play order, starting at idx (crosses into the next pages)
local function usable_from(idx, count)
  local out = {}
  local i = idx
  while i <= NUM_PADS and #out < count do
    if is_sample_slot(i) then out[#out + 1] = i end
    i = i + 1
  end
  return out
end

local function next_usable(idx)
  local last = NUM_PADS
  for i = idx + 1, last do
    if is_sample_slot(i) then return i end
  end
  return page_pad(1, 1)
end

--------------------------------------------------------------------------------
-- SELECTION
--------------------------------------------------------------------------------

local function sel_count()
  local n = 0
  for _ in pairs(selection) do n = n + 1 end
  return n
end

local function sel_list()
  local t = {}
  for i in pairs(selection) do t[#t + 1] = i end
  table.sort(t)
  if #t == 0 then t[1] = selected_pad end
  return t
end

local function select_single(idx)
  selection = { [idx] = true }
  selected_pad = idx
  sel_anchor = idx
end

local function select_range(a, b)
  selection = {}
  for i = min(a, b), max(a, b) do
    if pad_page(i) == current_page and is_visible(i) then selection[i] = true end
  end
  selection[b] = true
  selected_pad = b
end

local function toggle_select(idx)
  if selection[idx] and sel_count() > 1 then
    selection[idx] = nil
    if selected_pad == idx then selected_pad = sel_list()[1] end
  else
    selection[idx] = true
    selected_pad = idx
  end
  sel_anchor = idx
end

local function select_all_visible()
  selection = {}
  for li = 1, PAGE_SIZE do
    local i = page_pad(current_page, li)
    if is_visible(i) then selection[i] = true end
  end
  if not selection[selected_pad] then selected_pad = page_pad(current_page, 1) end
end

--------------------------------------------------------------------------------
-- PERSISTENCE (project ext-state + global ext-state)
--------------------------------------------------------------------------------

local function proj_valid(p)
  return p ~= nil and (not reaper.ValidatePtr or reaper.ValidatePtr(p, "ReaProject*"))
end

local function serialize_pads()
  local rec = {}
  for i = 1, NUM_PADS do
    local p = pads[i]
    if not pad_is_default(p) then
      rec[#rec + 1] = table.concat({
        i,
        esc(is_default_label(p.label) and "" or p.label),
        p.color_vel or 0,
        p.mode or 2,
        string.format("%.4f", p.volume or 1.0),
        p.velocity_sensitive and 1 or 0,
        p.pitch_semitones or 0,
        p.choke_group or 0,
        p.is_bounced and 1 or 0,
        p.loop_toggle and 1 or 0,
        esc(p.sample_path),
        string.format("%.6f", p.start_offs or 0),
        string.format("%.6f", p.end_offs or 1),
        p.role, p.anim_type, p.anim_color, p.anim_speed,
      }, "|")
    end
  end
  return table.concat(rec, ";")
end

-- role, animation type, animation color, animation speed (absent in older files -> defaults)
local function apply_fx_fields(p, role, atype, acolor, aspeed)
  p.role = clamp(floor(tonumber(role) or 1), 1, 3)
  p.anim_type = clamp(floor(tonumber(atype) or 3), 1, 5)
  p.anim_color = clamp(floor(tonumber(acolor) or -1), -2, 127)
  p.anim_speed = clamp(floor(tonumber(aspeed) or 2), 1, 3)
end

local function apply_pad_fields(p, f, first)
  -- f[first] = label, then color, mode, volume, velsens, pitch, choke, bounced
  local label = unesc(f[first] or "")
  p.label = (label ~= "") and label or default_label(p.row, p.col)
  p.color_vel = clamp(floor(tonumber(f[first + 1]) or 0), 0, 127)
  local m = floor(tonumber(f[first + 2]) or 2)
  p.mode = (m >= 1 and m <= 3) and m or 2
  p.volume = clamp(tonumber(f[first + 3]) or 1.0, 0.0, 1.0)
  p.velocity_sensitive = (f[first + 4] == "1")
  p.pitch_semitones = clamp(floor(tonumber(f[first + 5]) or 0), -12, 12)
  p.choke_group = clamp(floor(tonumber(f[first + 6]) or 0), 0, 4)
  p.is_bounced = (f[first + 7] == "1")
end

local function deserialize_pads2(s)
  if not s or s == "" then return end
  for _, rec in ipairs(split(s, ";")) do
    if rec ~= "" then
      local f = split(rec, "|")
      local idx = tonumber(f[1])
      local p = idx and pads[floor(idx)]
      if p and #f >= 13 then
        apply_pad_fields(p, f, 2)
        p.loop_toggle = (f[10] == "1")
        p.sample_path = unesc(f[11])
        p.start_offs = clamp(tonumber(f[12]) or 0, 0, 1)
        p.end_offs = clamp(tonumber(f[13]) or 1, 0, 1)
        apply_fx_fields(p, f[14], f[15], f[16], f[17])
      end
    end
  end
end

-- v1.x format: 64 positional records (page 1 only)
local function deserialize_pads_legacy(s)
  if not s or s == "" then return false end
  local records = split(s, ";")
  for i = 1, min(#records, PAGE_SIZE) do
    local f = split(records[i], "|")
    if #f >= 7 then apply_pad_fields(pads[i], f, 1) end
  end
  return true
end

local function settings_string()
  return table.concat({
    "kit=" .. esc(current_kit_name),
    "div=" .. chop_division,
    "choke=" .. (chop_choke and 1 or 0),
    "adv=" .. (auto_advance and 1 or 0),
    "fade=" .. fade_ms,
    "amute=" .. (auto_mute_source_track and 1 or 0),
    "areset=" .. (auto_reset_midi and 1 or 0),

    "grid=" .. grid_rows .. "x" .. grid_cols,
    "out=" .. esc(midi_out_name),
    "in=" .. esc(midi_in_name),
  }, ";")
end

local function load_settings()
  local s = reaper.GetExtState(EXT_SECTION, "settings")
  if not s or s == "" then return end
  for _, kv in ipairs(split(s, ";")) do
    local k, v = kv:match("^([^=]+)=(.*)$")
    if k then
      if k == "kit" then
        v = unesc(v)
        if v ~= "" then current_kit_name = v end
      elseif k == "div" then
        local d = tonumber(v)
        if d == 8 or d == 16 or d == 32 or d == 64 then chop_division = d end
      elseif k == "choke" then chop_choke = (v == "1")
      elseif k == "adv" then auto_advance = (v == "1")
      elseif k == "fade" then
        local f = tonumber(v)
        if f then fade_ms = clamp(floor(f), 0, 20) end
      elseif k == "amute" then auto_mute_source_track = (v == "1")
      elseif k == "areset" then auto_reset_midi = (v == "1")

      elseif k == "grid" then
        local r, c = v:match("^(%d+)x(%d+)$")
        r, c = tonumber(r), tonumber(c)
        if r and c then
          grid_rows, grid_cols = clamp(r, 1, HW_ROWS), clamp(c, 1, HW_COLS)
        end
      elseif k == "out" then saved_midi_out = unesc(v)
      elseif k == "in" then saved_midi_in = unesc(v)
      end
    end
  end
  last_saved_settings = settings_string()
end

local function state_key()
  return serialize_pads() .. "#" .. string.format("%.3f", master_volume) .. "#" .. num_pages
end

-- Returns true when a project state was found and applied
local function load_state()
  local restored = false
  local _, ver = reaper.GetProjExtState(cur_proj, EXT_SECTION, "v")
  if ver == "2" then
    local _, s = reaper.GetProjExtState(cur_proj, EXT_SECTION, "pads2")
    deserialize_pads2(s)
    restored = true
  else
    local _, s = reaper.GetProjExtState(cur_proj, EXT_SECTION, "pads")
    if s and s ~= "" then
      restored = deserialize_pads_legacy(s)
    else
      -- No project state yet: fall back to the last used LED colors (global)
      local cols = reaper.GetExtState(EXT_SECTION, "colors")
      if cols and cols ~= "" then
        local list = split(cols, ",")
        for i = 1, min(#list, PAGE_SIZE) do
          pads[i].color_vel = clamp(floor(tonumber(list[i]) or 0), 0, 127)
        end
      end
    end
  end
  local _, mv = reaper.GetProjExtState(cur_proj, EXT_SECTION, "master")
  local mvn = tonumber(mv)
  if mvn then master_volume = clamp(mvn, 0.0, 1.0) end
  local _, pg = reaper.GetProjExtState(cur_proj, EXT_SECTION, "pages")
  num_pages = clamp(floor(tonumber(pg) or 1), 1, MAX_PAGES)
  -- never hide pages that hold samples
  for i = NUM_PADS, 1, -1 do
    if pads[i].sample_path ~= "" then
      num_pages = max(num_pages, pad_page(i))
      break
    end
  end
  last_saved_pads = state_key()
  return restored
end

local function save_state(force)
  if engine_active and proj_valid(cur_proj) then
    local key = state_key()
    if force or key ~= last_saved_pads then
      last_saved_pads = key
      reaper.SetProjExtState(cur_proj, EXT_SECTION, "v", "2")
      reaper.SetProjExtState(cur_proj, EXT_SECTION, "pads2", serialize_pads())
      reaper.SetProjExtState(cur_proj, EXT_SECTION, "master", string.format("%.3f", master_volume))
      reaper.SetProjExtState(cur_proj, EXT_SECTION, "pages", tostring(num_pages))
      local cols = {}
      for i = 1, PAGE_SIZE do cols[i] = tostring(pads[i].color_vel or 0) end
      reaper.SetExtState(EXT_SECTION, "colors", table.concat(cols, ","), true)
    end
  end
  local st = settings_string()
  if force or st ~= last_saved_settings then
    last_saved_settings = st
    reaper.SetExtState(EXT_SECTION, "settings", st, true)
  end
end

local function persist_tick()
  local now = reaper.time_precise()
  if now < next_persist_time then return end
  next_persist_time = now + PERSIST_INTERVAL
  save_state(false)
end

--------------------------------------------------------------------------------
-- RS5K PARAMETERS
--------------------------------------------------------------------------------

-- Defaults (used if parameter names cannot be resolved). Re-resolved BY NAME the first time an
-- RS5K instance is found, so a different RS5K parameter layout still works.
local RS5K_P = {
  VOL = 0, PAN = 1, MIN_VOL = 2, NOTE_START = 3, NOTE_END = 4, PITCH_START = 5, PITCH_END = 6,
  MIDI_CHAN = 7, VOICES = 8, ATTACK = 9, RELEASE = 10, OBEY_OFF = 11, LOOP = 12,
  START_OFFS = 13, END_OFFS = 14, PITCH = 15, DECAY = 24,
}

local RS5K_PARAM_NAMES = {
  ["volume"] = "VOL",
  ["pan"] = "PAN",
  ["gain for minimum velocity"] = "MIN_VOL",
  ["note range start"] = "NOTE_START",
  ["note range end"] = "NOTE_END",
  ["midi channel"] = "MIDI_CHAN",
  ["max voices"] = "VOICES",
  ["attack"] = "ATTACK",
  ["release"] = "RELEASE",
  ["obey note-offs"] = "OBEY_OFF",
  ["loop"] = "LOOP",
  ["sample start offset"] = "START_OFFS",
  ["sample end offset"] = "END_OFFS",
  ["pitch offset"] = "PITCH",
  ["decay"] = "DECAY",
}

local rs5k_params_resolved = false

local function resolve_rs5k_params(track, fx)
  if rs5k_params_resolved then return end
  local n = reaper.TrackFX_GetNumParams(track, fx)
  local seen = {}
  for p = 0, n - 1 do
    local _, pname = reaper.TrackFX_GetParamName(track, fx, p, "")
    local key = RS5K_PARAM_NAMES[(pname or ""):lower()]
    if key and not seen[key] then
      seen[key] = true
      RS5K_P[key] = p
    end
  end
  rs5k_params_resolved = true
end

local function is_rs5k_fx(name)
  if not name or name == "" then return false end
  local n = name:lower()
  return n:find("reasamplomatic", 1, true) ~= nil or n:find("rs5k", 1, true) ~= nil
end

local function set_p(track, fx, key, value)
  reaper.TrackFX_SetParamNormalized(track, fx, RS5K_P[key], value)
end

local function get_p(track, fx, key)
  return reaper.TrackFX_GetParamNormalized(track, fx, RS5K_P[key])
end

local function pitch_to_norm(semitones)
  return clamp(0.5 + ((semitones or 0) / 160.0), 0.0, 1.0)
end

-- MIDI channel parameter: ask RS5K how each normalized value is displayed (0 = omni)
local chan_norm = nil

local function build_chan_table(track, fx)
  if chan_norm then return end
  local first, last = {}, {}
  local found = false
  if reaper.TrackFX_FormatParamValueNormalized then
    for step = 0, 340 do
      local n = step / 340
      local ok, s = reaper.TrackFX_FormatParamValueNormalized(track, fx, RS5K_P.MIDI_CHAN, n, "")
      if ok and s and s ~= "" then
        local num = tonumber(s:match("%d+")) or 0
        if num >= 0 and num <= 16 then
          if not first[num] then first[num] = n end
          last[num] = n
          found = true
        end
      end
    end
  end
  chan_norm = {}
  for ch = 0, 16 do
    if found and first[ch] then
      chan_norm[ch] = (first[ch] + last[ch]) / 2
    else
      chan_norm[ch] = ch / 16
    end
  end
end

local function get_fx_chan(track, fx)
  local ok, s = reaper.TrackFX_GetFormattedParamValue(track, fx, RS5K_P.MIDI_CHAN, "")
  if ok and s and s ~= "" then
    return tonumber(s:match("%d+")) or 0
  end
  return floor(get_p(track, fx, "MIDI_CHAN") * 16 + 0.5)
end

-- RS5K attack/release use their own scale: search the normalized value showing the wanted ms
local ms_norm_cache = {}

local function displayed_ms(track, fx, key, norm)
  local ok, s = reaper.TrackFX_FormatParamValueNormalized(track, fx, RS5K_P[key], norm, "")
  if not ok or not s then return nil end
  local num = tonumber(s:match("[-+]?%d*%.?%d+"))
  if not num then return nil end
  local low = s:lower()
  if low:find("ms", 1, true) then return num end
  if low:find("s", 1, true) then return num * 1000 end
  return nil
end

local function ms_to_norm(track, fx, key, ms)
  if ms <= 0 then return 0.0 end
  local ck = key .. ":" .. ms
  if ms_norm_cache[ck] then return ms_norm_cache[ck] end
  local fallback = clamp(ms / (key == "DECAY" and 15000 or 2000), 0.0, 1.0)
  local result = fallback
  if reaper.TrackFX_FormatParamValueNormalized then
    local top = displayed_ms(track, fx, key, 1.0)
    if top and top >= ms then
      local lo, hi = 0.0, 1.0
      for _ = 1, 24 do
        local mid = (lo + hi) / 2
        local shown = displayed_ms(track, fx, key, mid)
        if not shown then lo, hi = 0, 0 break end
        if shown < ms then lo = mid else hi = mid end
      end
      if hi > 0 then result = (lo + hi) / 2 end
    end
  end
  ms_norm_cache[ck] = result
  return result
end

local function effective_volume_norm(pad)
  -- RS5K: 0.50 normalized = 0.0 dB. Pad volume and master volume scale it down from unity.
  return clamp((pad.volume or 1.0) * master_volume, 0.0, 1.0) * 0.5
end

local function configure_rs5k_instance(track, fx_idx, pad)
  if not track or not fx_idx or not pad then return end
  build_chan_table(track, fx_idx)
  local note = pad.midi_note
  set_p(track, fx_idx, "NOTE_START", note / 127)
  set_p(track, fx_idx, "NOTE_END", note / 127)
  set_p(track, fx_idx, "MIDI_CHAN", chan_norm[pad.page + 1])
  set_p(track, fx_idx, "ATTACK", ms_to_norm(track, fx_idx, "ATTACK", fade_ms))
  set_p(track, fx_idx, "RELEASE", ms_to_norm(track, fx_idx, "RELEASE", fade_ms))
  set_p(track, fx_idx, "DECAY", 1.0)
  set_p(track, fx_idx, "LOOP", (pad.mode == 3) and 1.0 or 0.0)
  -- One-Shot ignores note-offs; Gate and Loop (the router swallows toggle releases) obey them
  set_p(track, fx_idx, "OBEY_OFF", (pad.mode == 2) and 0.0 or 1.0)
  set_p(track, fx_idx, "VOICES", 0.0)
  local s_start = clamp(pad.start_offs or 0.0, 0.0, 1.0)
  local s_end = max(s_start + 0.0001, min(1.0, pad.end_offs or 1.0))
  set_p(track, fx_idx, "START_OFFS", s_start)
  set_p(track, fx_idx, "END_OFFS", s_end)
  set_p(track, fx_idx, "VOL", effective_volume_norm(pad))
  set_p(track, fx_idx, "MIN_VOL", pad.velocity_sensitive and 0.0 or 1.0)
  set_p(track, fx_idx, "PITCH", pitch_to_norm(pad.pitch_semitones))
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "DONE", "")
end

local function clear_rs5k_sample(track, fx_idx)
  reaper.TrackFX_SetEnabled(track, fx_idx, false)
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "-FILE*", "")
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "FILE0", "")
  reaper.TrackFX_SetNamedConfigParm(track, fx_idx, "DONE", "")
end

local function adopt_rs5k_settings(pad, track, fx)
  local loop = get_p(track, fx, "LOOP") > 0.5
  local obey = get_p(track, fx, "OBEY_OFF") > 0.5
  pad.mode = loop and 3 or (obey and 1 or 2)
  pad.loop_toggle = false
  pad.volume = clamp(get_p(track, fx, "VOL") * 2.0, 0.0, 1.0)
  pad.velocity_sensitive = get_p(track, fx, "MIN_VOL") < 0.5
  pad.pitch_semitones = clamp(floor((get_p(track, fx, "PITCH") - 0.5) * 160.0 + 0.5), -12, 12)
end

-- Lua allows at most 200 local variables per function. The engine is split in two scopes:
-- everything above is file level, everything below lives inside engine_main() and still
-- sees the locals above as upvalues.
local function engine_main()

--------------------------------------------------------------------------------
-- ROUTER JSFX (installed and kept up to date by this script)
--   Launchpad (MIDI ch 1) -> RS5K pads of the current page (MIDI ch = page + 1)
--   Toggle loops, gate releases across page changes, event report to the script.
--------------------------------------------------------------------------------

local ROUTER_CODE = [==[
desc:Little Things - Launchpad Router
//tags: MIDI routing launchpad
// Generated by "Little Things - Launchpad Chop Engine". The script rewrites this file: do not edit.
// Launchpad (MIDI ch 1) -> RS5K pads of the current page (MIDI ch = page + 1), toggle loops,
// and a small event buffer the script reads to know which pads were hit.

slider1:1<1,14,1>Page
slider2:8<1,8,1>Rows
slider3:8<1,8,1>Columns
slider4:0<0,1000000,1>-Event counter
slider5:0<0,3000,1>-Event 1
slider6:0<0,3000,1>-Event 2
slider7:0<0,3000,1>-Event 3
slider8:0<0,3000,1>-Event 4
slider9:0<0,3000,1>-Event 5
slider10:0<0,3000,1>-Event 6
slider11:0<0,3000,1>-Event 7
slider12:0<0,3000,1>-Event 8
slider13:0<0,3000,1>-Event 9
slider14:0<0,3000,1>-Event 10
slider15:0<0,3000,1>-Event 11
slider16:0<0,3000,1>-Event 12
slider17:0<0,3000,1>-Event 13
slider18:0<0,3000,1>-Event 14
slider19:0<0,3000,1>-Event 15
slider20:0<0,3000,1>-Event 16
slider21:0<0,65535,1>-Toggle mask 1
slider22:0<0,65535,1>-Toggle mask 2
slider23:0<0,65535,1>-Toggle mask 3
slider24:0<0,65535,1>-Toggle mask 4
slider25:0<0,1000000,1>-Command counter
slider26:0<0,100000,1>-Command 1
slider27:0<0,100000,1>-Command 2
slider28:0<0,100000,1>-Command 3
slider29:0<0,100000,1>-Command 4
slider30:0<0,100000,1>-Command 5
slider31:0<0,100000,1>-Command 6
slider32:0<0,100000,1>-Command 7
slider33:0<0,100000,1>-Command 8

in_pin:none
out_pin:none

@init
ext_noinit = 1;
held = 0;
looping = 128;
memset(0, 0, 128 + 2048);
cmd_ready = 0;
last_cmd = 0;

function report(code)
(
  slider4 = (slider4 + 1) % 1000000;
  slider(5 + (slider4 % 16)) = code;
);

function grid_index(note) local(row, col)
(
  row = 8 - floor(note / 10);
  col = (note % 10) - 1;
  (note >= 11 && note <= 88 && row >= 0 && row < slider2 && col >= 0 && col < slider3) ? row * 8 + col : -1;
);

function is_toggle(li) local(mask)
(
  mask = slider(21 + floor(li / 16));
  floor(mask / (2 ^ (li % 16))) % 2;
);

function page_chan()
(
  max(1, min(14, floor(slider1 + 0.5)));
);

function toggle_press(ofs, note, vel) local(pch, k)
(
  pch = page_chan();
  k = note * 16 + pch;
  looping[k] ? (
    midisend(ofs, 128 + pch, note, 0);
    looping[k] = 0;
    report(2000 + note);
  ) : (
    midisend(ofs, 144 + pch, note, vel);
    looping[k] = 1;
    report(1000 + note);
  );
);

@block
target = floor(slider25 + 0.5);
cmd_ready == 0 ? ( last_cmd = target; cmd_ready = 1; );
diff = (target - last_cmd + 1000000) % 1000000;
diff > 8 ? ( last_cmd = (target - 8 + 1000000) % 1000000; diff = 8; );
loop(diff,
  last_cmd = (last_cmd + 1) % 1000000;
  c = floor(slider(26 + (last_cmd % 8)) + 0.5);
  c == 0 ? (
    memset(looping, 0, 2048);
    memset(held, 0, 128);
  ) : c >= 50000 ? (
    cnote = c - 50000;
    grid_index(cnote) >= 0 ? toggle_press(0, cnote, 127);
  ) : (
    looping[c] = 0;
  );
);

while (midirecv(ofs, m1, m2, m3)) (
  st = m1 & 240;
  ch = m1 & 15;
  pass = 1;
  (ch == 0 && (st == 144 || st == 128)) ? (
    pass = 0;
    note = m2;
    li = grid_index(note);
    (st == 144 && m3 > 0) ? (
      li >= 0 ? (
        is_toggle(li) ? (
          toggle_press(ofs, note, m3);
        ) : (
          pch = page_chan();
          held[note] = pch;
          midisend(ofs, 144 + pch, note, m3);
          report(1000 + note);
        );
      );
    ) : (
      held[note] > 0 ? (
        midisend(ofs, 128 + held[note], note, 0);
        held[note] = 0;
        report(2000 + note);
      );
    );
  ) : (ch == 0 && st == 160) ? (
    pass = 0;
  );
  pass ? midisend(ofs, m1, m2, m3);
);
]==]

local P_PAGE, P_ROWS, P_COLS, P_EVCOUNT, P_EV0 = 0, 1, 2, 3, 4
local P_MASK0, P_CMDCOUNT, P_CMD0 = 20, 24, 25

local function track_valid(tr)
  return tr ~= nil and reaper.ValidatePtr2(0, tr, "MediaTrack*")
end

local function ensure_router_file()
  local dir = reaper.GetResourcePath() .. "/Effects/" .. ROUTER_DIR
  reaper.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/" .. ROUTER_FILE
  if read_file(path) ~= ROUTER_CODE then
    local f = io.open(path, "wb")
    if f then
      f:write(ROUTER_CODE)
      f:close()
    end
  end
end

local function find_router()
  if not track_valid(rs5k_track) then return -1 end
  local count = reaper.TrackFX_GetCount(rs5k_track)
  if router_idx >= 0 and router_idx < count then
    local _, name = reaper.TrackFX_GetFXName(rs5k_track, router_idx)
    if name and name:find(ROUTER_TAG, 1, true) then return router_idx end
  end
  router_idx = -1
  for i = 0, count - 1 do
    local _, name = reaper.TrackFX_GetFXName(rs5k_track, i)
    if name and name:find(ROUTER_TAG, 1, true) then
      router_idx = i
      router_counter, router_cmd_counter = nil, nil
      return i
    end
  end
  return -1
end

local function router_ok()
  return find_router() >= 0
end

-- Only writes parameters whose value differs (keeps the project from being marked dirty)
local function router_set_if_changed(idx, param, value)
  local cur = reaper.TrackFX_GetParam(rs5k_track, idx, param)
  if floor(cur + 0.5) ~= value then reaper.TrackFX_SetParam(rs5k_track, idx, param, value) end
end

local function router_push_params()
  local idx = find_router()
  if idx < 0 then return end
  router_set_if_changed(idx, P_PAGE, current_page)
  router_set_if_changed(idx, P_ROWS, grid_rows)
  router_set_if_changed(idx, P_COLS, grid_cols)
  for k = 0, 3 do
    local mask = 0
    for b = 0, 15 do
      if is_toggle(page_pad(current_page, k * 16 + b + 1)) then mask = mask + (1 << b) end
    end
    router_set_if_changed(idx, P_MASK0 + k, mask)
  end
  router_flags_dirty = false
end

-- code 0 = stop everything, note*16+chan = forget a toggle loop, 50000+note = toggle press
local function router_command(code)
  local idx = find_router()
  if idx < 0 then return false end
  if router_cmd_counter == nil then
    router_cmd_counter = floor(reaper.TrackFX_GetParam(rs5k_track, idx, P_CMDCOUNT) + 0.5)
  end
  router_cmd_counter = (router_cmd_counter + 1) % 1000000
  reaper.TrackFX_SetParam(rs5k_track, idx, P_CMD0 + (router_cmd_counter % 8), code)
  reaper.TrackFX_SetParam(rs5k_track, idx, P_CMDCOUNT, router_cmd_counter)
  return true
end

-- Makes sure the router exists and is the FIRST fx on the track. Returns true if fx moved.
local function ensure_router()
  if not track_valid(rs5k_track) then return false end
  local moved = false
  local idx = find_router()
  if idx < 0 then
    ensure_router_file()
    idx = reaper.TrackFX_AddByName(rs5k_track, "JS:" .. ROUTER_DIR .. "/" .. ROUTER_FILE, false, -1)
    if not idx or idx < 0 then
      idx = reaper.TrackFX_AddByName(rs5k_track, "JS:" .. ROUTER_DIR .. "/" .. strip_ext(ROUTER_FILE), false, -1)
    end
    if not idx or idx < 0 then
      if not router_error_shown then
        router_error_shown = true
        set_status("[!] Router JSFX could not be loaded - hardware pads use the slower fallback", 0xFF3B30FF)
      end
      return false
    end
    router_idx = idx
    router_counter, router_cmd_counter = nil, nil
  end
  if idx ~= 0 then
    reaper.TrackFX_CopyToTrack(rs5k_track, idx, rs5k_track, 0, true)
    router_idx = 0
    moved = true
  end
  router_push_params()
  return moved
end

--------------------------------------------------------------------------------
-- RS5K TRACK & INSTANCES
--------------------------------------------------------------------------------

local function find_rs5k_track()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == TRACK_NAME then return tr end
  end
  return nil
end

local function reset_track_refs()
  rs5k_track = nil
  rs5k_fx_indices = {}
  rs5k_guids = {}
  rs5k_ready = false
  router_idx = -1
  router_counter, router_cmd_counter = nil, nil
end

local function find_or_create_rs5k_track()
  if track_valid(rs5k_track) then return rs5k_track end
  reset_track_refs()
  rs5k_track = find_rs5k_track()
  if rs5k_track then return rs5k_track end
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  rs5k_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(rs5k_track, "P_NAME", TRACK_NAME, true)
  return rs5k_track
end

local function inst_pad_index(note, chan)
  local li = note_to_local[note]
  if not li then return nil end
  local page = (chan >= 2) and (chan - 1) or 1   -- omni / ch 1 = instances made by v1.x
  if page > MAX_PAGES then return nil end
  return page_pad(page, li)
end

local function scan_rs5k_instances()
  local list = {}
  local count = reaper.TrackFX_GetCount(rs5k_track)
  for i = 0, count - 1 do
    local _, name = reaper.TrackFX_GetFXName(rs5k_track, i)
    if is_rs5k_fx(name) then
      resolve_rs5k_params(rs5k_track, i)
      local note = floor(get_p(rs5k_track, i, "NOTE_START") * 127 + 0.5)
      local chan = get_fx_chan(rs5k_track, i)
      local ok, fp = reaper.TrackFX_GetNamedConfigParm(rs5k_track, i, "FILE0")
      list[#list + 1] = {
        fx_idx = i,
        note = note,
        chan = chan,
        pad_idx = inst_pad_index(note, chan),
        file = (ok and fp) or "",
      }
    end
  end
  return list
end

local function map_instance(p, fx_idx)
  rs5k_fx_indices[p] = fx_idx
  rs5k_guids[p] = reaper.TrackFX_GetFXGUID(rs5k_track, fx_idx)
end

local function sync_rs5k_instances()
  if not track_valid(rs5k_track) then return end
  reaper.PreventUIRefresh(1)

  local list = scan_rs5k_instances()

  -- Step 1: one instance per pad (keep the one that has a sample loaded)
  local by_pad, dead = {}, {}
  for _, inst in ipairs(list) do
    if inst.pad_idx then
      local cur = by_pad[inst.pad_idx]
      if not cur then
        by_pad[inst.pad_idx] = inst
      elseif inst.file ~= "" and cur.file == "" then
        dead[#dead + 1] = cur.fx_idx
        by_pad[inst.pad_idx] = inst
      else
        dead[#dead + 1] = inst.fx_idx
      end
    end
  end

  if #dead > 0 then
    table.sort(dead, function(a, b) return a > b end)
    for _, idx in ipairs(dead) do reaper.TrackFX_Delete(rs5k_track, idx) end
    list = scan_rs5k_instances()
    by_pad = {}
    for _, inst in ipairs(list) do
      if inst.pad_idx and not by_pad[inst.pad_idx] then by_pad[inst.pad_idx] = inst end
    end
  end

  -- Step 2: map instances to pads and pull sample info back into the pads
  rs5k_fx_indices, rs5k_guids = {}, {}
  local used = {}
  for p, inst in pairs(by_pad) do
    map_instance(p, inst.fx_idx)
    used[inst.fx_idx] = true
    local pad = pads[p]
    if inst.chan ~= pad.page + 1 then
      build_chan_table(rs5k_track, inst.fx_idx)
      set_p(rs5k_track, inst.fx_idx, "MIDI_CHAN", chan_norm[pad.page + 1])
    end
    if inst.file ~= "" then
      pad.sample_path = inst.file
      pad.start_offs = get_p(rs5k_track, inst.fx_idx, "START_OFFS")
      pad.end_offs = get_p(rs5k_track, inst.fx_idx, "END_OFFS")
      if is_default_label(pad.label) then pad.label = strip_ext(basename(inst.file)) end
      if adopt_pending then adopt_rs5k_settings(pad, rs5k_track, inst.fx_idx) end
    elseif pad.sample_path ~= "" and file_exists(pad.sample_path) then
      -- self-heal: the instance lost its sample but the pad still knows it
      configure_rs5k_instance(rs5k_track, inst.fx_idx, pad)
      reaper.TrackFX_SetNamedConfigParm(rs5k_track, inst.fx_idx, "FILE0", pad.sample_path)
      reaper.TrackFX_SetNamedConfigParm(rs5k_track, inst.fx_idx, "DONE", "")
      reaper.TrackFX_SetEnabled(rs5k_track, inst.fx_idx, true)
    end
  end

  -- Step 3: spare RS5K instances (note outside the pad map) can be re-purposed
  local spare = {}
  for _, inst in ipairs(list) do
    if not used[inst.fx_idx] and not inst.pad_idx then spare[#spare + 1] = inst.fx_idx end
  end

  -- Step 4: only pads that hold a sample need an instance (empty pads stay lightweight)
  for p = 1, NUM_PADS do
    local pad = pads[p]
    if not rs5k_fx_indices[p] and pad.sample_path ~= "" and file_exists(pad.sample_path) then
      local fx_idx = table.remove(spare, 1)
      if not fx_idx then fx_idx = reaper.TrackFX_AddByName(rs5k_track, RS5K_NAME, false, -1) end
      if fx_idx and fx_idx >= 0 then
        resolve_rs5k_params(rs5k_track, fx_idx)
        map_instance(p, fx_idx)
        configure_rs5k_instance(rs5k_track, fx_idx, pad)
        reaper.TrackFX_SetNamedConfigParm(rs5k_track, fx_idx, "FILE0", pad.sample_path)
        reaper.TrackFX_SetNamedConfigParm(rs5k_track, fx_idx, "DONE", "")
        reaper.TrackFX_SetEnabled(rs5k_track, fx_idx, true)
      end
    end
  end

  adopt_pending = false
  reaper.PreventUIRefresh(-1)
end

local function ensure_rs5k_track_ready(force)
  if not engine_active then return end
  if not force and rs5k_ready and track_valid(rs5k_track) then return end

  find_or_create_rs5k_track()

  -- 4096 + 2016 = All MIDI inputs, all channels (Virtual MIDI Keyboard + Launchpad)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "I_RECINPUT", 4096 + 2016)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "I_RECARM", 1)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "I_RECMON", 1)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "I_RECMODE", 2)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "B_MAINSEND", 1)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "B_MUTE", 0)
  reaper.SetMediaTrackInfo_Value(rs5k_track, "D_VOL", 1.0)

  ensure_router()
  sync_rs5k_instances()
  rs5k_ready = true
end

local function fx_still_valid(idx, fx)
  if not fx or fx < 0 or fx >= reaper.TrackFX_GetCount(rs5k_track) then return false end
  return reaper.TrackFX_GetFXGUID(rs5k_track, fx) == rs5k_guids[idx]
end

-- create = true creates the RS5K instance if the pad has none yet
local function get_pad_fx_idx(idx, create)
  if not idx or idx < 1 or idx > NUM_PADS then return nil end
  ensure_rs5k_track_ready()
  if not track_valid(rs5k_track) then return nil end

  local fx = rs5k_fx_indices[idx]
  if fx then
    if fx_still_valid(idx, fx) then return fx end
    sync_rs5k_instances()
    fx = rs5k_fx_indices[idx]
  end
  if fx or not create then return fx end

  fx = reaper.TrackFX_AddByName(rs5k_track, RS5K_NAME, false, -1)
  if fx and fx >= 0 then
    resolve_rs5k_params(rs5k_track, fx)
    map_instance(idx, fx)
    configure_rs5k_instance(rs5k_track, fx, pads[idx])
    reaper.TrackFX_SetEnabled(rs5k_track, fx, false)
    return fx
  end
  return nil
end

local function apply_fade_to_all()
  if not track_valid(rs5k_track) then return end
  reaper.PreventUIRefresh(1)
  for i = 1, NUM_PADS do
    if pads[i].sample_path ~= "" then
      local fx = get_pad_fx_idx(i, false)
      if fx then
        set_p(rs5k_track, fx, "ATTACK", ms_to_norm(rs5k_track, fx, "ATTACK", fade_ms))
        set_p(rs5k_track, fx, "RELEASE", ms_to_norm(rs5k_track, fx, "RELEASE", fade_ms))
      end
    end
  end
  reaper.PreventUIRefresh(-1)
end

-- opts.keep    : keep the pad's current settings instead of resetting to defaults
-- opts.bounced : the file is a temporary bounce owned by the script (may be deleted with the pad)
local function load_sample_to_rs5k(pad_idx, file_path, start_offs, end_offs, opts)
  opts = opts or {}
  ensure_rs5k_track_ready()
  local fx_idx = get_pad_fx_idx(pad_idx, true)
  if not fx_idx then return end

  local pad = pads[pad_idx]
  reaper.TrackFX_SetEnabled(rs5k_track, fx_idx, true)
  reaper.TrackFX_SetNamedConfigParm(rs5k_track, fx_idx, "FILE0", file_path)
  reaper.TrackFX_SetNamedConfigParm(rs5k_track, fx_idx, "DONE", "")

  pad.sample_path = file_path
  pad.start_offs = start_offs or 0.0
  pad.end_offs = end_offs or 1.0
  pad.is_bounced = opts.bounced == true
  if not opts.keep then pad.role = 1 end

  if not opts.keep then apply_capture_defaults(pad, 1) end

  configure_rs5k_instance(rs5k_track, fx_idx, pad)

  if is_default_label(pad.label) then pad.label = strip_ext(basename(file_path)) end
  router_flags_dirty = true
end

-- Re-applies a pad's whole content to its RS5K instance (moves, kit loads)
local function apply_pad_to_rs5k(idx)
  local p = pads[idx]
  if p.sample_path ~= "" and file_exists(p.sample_path) then
    load_sample_to_rs5k(idx, p.sample_path, p.start_offs, p.end_offs, { keep = true, bounced = p.is_bounced })
  else
    p.sample_path = ""
    local fx = get_pad_fx_idx(idx, false)
    if fx then clear_rs5k_sample(rs5k_track, fx) end
  end
end

local function pad_fx_set(idx, key, value)
  local fx = get_pad_fx_idx(idx, false)
  if fx and rs5k_track then set_p(rs5k_track, fx, key, value) end
end

local function update_rs5k_volume(idx)
  pad_fx_set(idx, "VOL", effective_volume_norm(pads[idx]))
end

local sample_len_cache = {}

local function get_sample_length(path)
  if not path or path == "" then return 0 end
  local l = sample_len_cache[path]
  if l then return l end
  l = 0
  local src = reaper.PCM_Source_CreateFromFile(path)
  if src then
    l = reaper.GetMediaSourceLength(src) or 0
    reaper.PCM_Source_Destroy(src)
  end
  sample_len_cache[path] = l
  return l
end

--------------------------------------------------------------------------------
-- MIDI DEVICES & LAUNCHPAD LEDS
--------------------------------------------------------------------------------

local function score_launchpad_device(name)
  if not name or name == "" then return -1 end
  local n = name:lower()
  local is_lp = n:find("launchpad") or n:find("lpmini") or n:find("lpx") or n:find("lppro")
  if not is_lp then return -1 end
  local score = 100
  if n:find("daw") or n:find("%s+da$") or n:find("%s+da%s+") then score = score - 80 end
  if n:find("midi") or n:find("%s+mi$") or n:find("%s+mi%s+") or n:find("standalone") or n:find("programmer") then
    score = score + 50
  end
  return score
end

local function refresh_midi_device_lists()
  available_midi_ins, available_midi_outs = {}, {}
  midi_disabled_hint = false
  local num_ins = reaper.GetNumMIDIInputs and reaper.GetNumMIDIInputs() or 32
  for i = 0, max(32, num_ins - 1) do
    local rv, name = reaper.GetMIDIInputName(i, "")
    if name and name ~= "" then
      local sc = score_launchpad_device(name)
      if not rv and sc > 0 then midi_disabled_hint = true end
      available_midi_ins[#available_midi_ins + 1] = { id = i, name = name, enabled = rv, score = rv and sc or -1 }
    end
  end
  local num_outs = reaper.GetNumMIDIOutputs and reaper.GetNumMIDIOutputs() or 32
  for i = 0, max(32, num_outs - 1) do
    local rv, name = reaper.GetMIDIOutputName(i, "")
    if name and name ~= "" then
      local sc = score_launchpad_device(name)
      if not rv and sc > 0 then midi_disabled_hint = true end
      available_midi_outs[#available_midi_outs + 1] = { id = i, name = name, enabled = rv, score = rv and sc or -1 }
    end
  end
end

-- One path only: sending every LED twice (queued + immediate) let a stale copy arrive after
-- the fresh one, leaving a pad with the wrong color / dark.
local function hw_send(b1, b2, b3)
  if midi_out_device < 0 then return end
  reaper.StuffMIDIMessage(16 + midi_out_device, b1, b2 & 0x7F, b3 & 0x7F)
end

-- ch 0 = static, 1 = flashing, 2 = pulsing (Launchpad MK3 programmer mode LED channels)
local function set_led(note, velocity, force, ch)
  if midi_out_device < 0 then return end
  ch = ch or 0
  local key = velocity + ch * 256
  if not force and led_cache[note] == key then return end
  led_cache[note] = key
  hw_send(0x90 | ch, clamp(floor(note), 0, 127), clamp(floor(velocity), 0, 127))
end

local function set_cc_led(cc, velocity, force)
  if midi_out_device < 0 then return end
  if not force and cc_cache[cc] == velocity then return end
  cc_cache[cc] = velocity
  hw_send(0xB0, cc, velocity)
end

local function schedule_led_sync(delay)
  pending_led_sync = reaper.time_precise() + (delay or 0.3)
end

local function set_launchpad_programmer_mode(out_dev)
  if out_dev < 0 then return end
  -- Mini MK3, LPX, LPPro MK3, LPPro MK1, MK2 (unknown ones are ignored by the device)
  local sysex_msgs = {
    { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7 },
    { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x01, 0xF7 },
    { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x0E, 0x01, 0xF7 },
    { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x2C, 0x03, 0xF7 },
    { 0xF0, 0x00, 0x20, 0x29, 0x02, 0x18, 0x22, 0x00, 0xF7 },
  }
  if reaper.SendMIDIMessageToHardware then
    for _, bytes in ipairs(sysex_msgs) do
      reaper.SendMIDIMessageToHardware(out_dev, string.char(table.unpack(bytes)))
    end
  end
  led_cache, cc_cache = {}, {}
  schedule_led_sync(0.35)
end

local function find_by_name(list, wanted)
  if not wanted or wanted == "" then return nil end
  for _, dev in ipairs(list) do
    if dev.name == wanted and dev.enabled then return dev end
  end
  return nil
end

local function best_device(list)
  local best, best_score = nil, 0
  for _, dev in ipairs(list) do
    if dev.score > best_score then
      best_score = dev.score
      best = dev
    end
  end
  return best
end

local function find_launchpad_devices(use_saved)
  refresh_midi_device_lists()
  local out = (use_saved and find_by_name(available_midi_outs, saved_midi_out)) or best_device(available_midi_outs)
  local inp = (use_saved and find_by_name(available_midi_ins, saved_midi_in)) or best_device(available_midi_ins)
  midi_out_device = out and out.id or -1
  midi_out_name = out and out.name or ""
  midi_in_device = inp and inp.id or -1
  midi_in_name = inp and inp.name or ""
  midi_connected = (midi_out_device >= 0)
  if midi_connected then set_launchpad_programmer_mode(midi_out_device) end
end

-- REAPER has no API to tick "Enable input/output" in Preferences. What we can do: re-scan the
-- drivers (Reset all MIDI devices) and pick the Launchpad ports automatically.
local function reset_midi_devices()
  local id = find_action("reset all midi devices", { 41175 })
  if id then
    reaper.Main_OnCommand(id, 0)
    next_midi_scan = reaper.time_precise() + 1.5
    midi_connected = false
    set_status("MIDI devices re-scanned, looking for the Launchpad...", 0xFF9500FF)
  else
    set_status("[!] Action 'Reset all MIDI devices' not found", 0xFF3B30FF)
  end
end

local function open_midi_prefs()
  if reaper.ViewPrefs then
    reaper.ViewPrefs(0, "mididevs")
  else
    reaper.Main_OnCommand(40016, 0)
  end
end

local function midi_autoconnect_tick()
  if midi_connected then return end
  local now = reaper.time_precise()
  if now < next_midi_scan then return end
  next_midi_scan = now + 3.0
  find_launchpad_devices(true)
  if midi_connected then
    set_status("Launchpad connected: " .. midi_out_name, 0x34C759FF)
  elseif auto_reset_midi and not midi_reset_done then
    midi_reset_done = true
    reset_midi_devices()
  end
end

local function page_has_content(p)
  for li = 1, PAGE_SIZE do
    if pads[page_pad(p, li)].sample_path ~= "" then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- ANIMATIONS (drawn on the Launchpad on top of the pad colors)
--------------------------------------------------------------------------------

local ANIM_NAMES = { "Off", "Flash", "Ripple", "Cross", "Sparkle" }
local ANIM_STEP = { 0.08, 0.05, 0.03 }   -- seconds per animation step (slow / normal / fast)
local MAX_ANIMS = 6
local anims = {}                          -- running animations
local anim_overlay = {}                   -- note -> velocity shown over the pad color

-- Launchpad palette: colors come in groups of 4 (bright .. dim); returns the dim one
local function dim_vel(v)
  if v == 3 or v == 2 then return 1 end
  if v < 4 or v > 63 then return v end
  local base = (v % 4 == 0) and (v + 1) or (v - ((v - 1) % 4))
  return base + 2
end

local function anim_put(out, r, c, v)
  if r >= 0 and r < grid_rows and c >= 0 and c < grid_cols then
    out[mk3_note_for_pad(r, c)] = v
  end
end

-- Writes the cells of animation a at time now into out; returns false when finished
local function anim_frame(a, now, out)
  local k = floor((now - a.t0) / (ANIM_STEP[a.speed] or 0.05))
  if a.rainbow then a.vel = CHOP_COLORS[(k % #CHOP_COLORS) + 1] end
  local dim = dim_vel(a.vel)
  if a.kind == 3 then -- Ripple: a ring growing from the pad, with a dim trail
    if k > 9 then return false end
    for r = 0, grid_rows - 1 do
      for c = 0, grid_cols - 1 do
        local d = max(math.abs(r - a.r), math.abs(c - a.c))
        if d == k then anim_put(out, r, c, (k == 0) and 3 or a.vel)
        elseif d == k - 1 then anim_put(out, r, c, dim) end
      end
    end
    return true
  elseif a.kind == 4 then -- Cross: the pad's row and column light up outwards
    if k > 9 then return false end
    for d = max(0, k - 1), k do
      local v = (d == k) and a.vel or dim
      if d == 0 then v = 3 end
      anim_put(out, a.r + d, a.c, v)
      anim_put(out, a.r - d, a.c, v)
      anim_put(out, a.r, a.c + d, v)
      anim_put(out, a.r, a.c - d, v)
    end
    return true
  elseif a.kind == 5 then -- Sparkle: random sparks around the pad
    if k > 7 then return false end
    for i = 1, 3 do
      local h = (a.seed * 7919 + k * 104729 + i * 15485863) % 2147483647
      anim_put(out, a.r + (h % 5) - 2, a.c + ((h // 5) % 5) - 2, (i == 1) and 3 or ((k % 2 == 0) and a.vel or dim))
    end
    return true
  end
  return false
end

--------------------------------------------------------------------------------
-- SPECIAL PADS: metronome (blinks on the DAW beat, press = metronome on/off) and stop sound
--------------------------------------------------------------------------------

local ROLE_NAMES = { "Sample", "Metronome", "Stop sound" }
local metro = { phase = 0, downbeat = false, on = false }

local function metronome_cmd()
  return find_action("toggle metronome", { 40364 })
end

local function metronome_is_on()
  local id = metronome_cmd()
  return id ~= nil and reaper.GetToggleCommandState(id) == 1
end

-- Beat position: follows the play cursor while playing, free-runs at the project tempo when stopped
local function update_beat()
  if (reaper.GetPlayState() & 1) == 1 then
    local b = reaper.TimeMap2_timeToBeats(0, reaper.GetPlayPosition())
    local bi = floor(b)
    metro.phase, metro.downbeat = b - bi, (bi == 0)
  else
    local t = reaper.time_precise() * reaper.Master_GetTempo() / 60
    metro.phase, metro.downbeat = t - floor(t), false
  end
  metro.on = metronome_is_on()
end

local function flash_vel(p)
  return (p.anim_color >= 0) and p.anim_color or 3
end

-- LED state of a pad on the current page
local function pad_led_state(idx)
  local p = pads[idx]
  if not is_visible(idx) then return 0, 0 end
  local ov = anim_overlay[p.midi_note]
  if ov then return ov, 0 end
  if flash_timers[idx] then return flash_vel(p), 0 end
  if p.role == 2 then
    -- metronome ON: bright on the beat (white on the downbeat), dim between beats
    -- metronome OFF: dim blink only
    local col = (p.color_vel > 0) and p.color_vel or 21
    local lit = metro.phase < 0.3
    if metro.on then return lit and (metro.downbeat and 3 or col) or dim_vel(col), 0 end
    return lit and dim_vel(col) or 0, 0
  end
  if p.mode == 3 and active_until[idx] and p.color_vel > 0 then return p.color_vel, 2 end
  return p.color_vel, 0
end

local function send_pad_color(idx, force)
  if not pads[idx] or pad_page(idx) ~= current_page then return end
  local vel, ch = pad_led_state(idx)
  set_led(pads[idx].midi_note, vel, force, ch)
end

-- Arrows lit when there is a page in that direction. Right column = pages 1-8:
-- orange = current, blue = has sounds, dim white = empty
local function update_nav_leds(force)
  if midi_out_device < 0 then return end
  local has_prev = current_page > 1
  local has_next = current_page < MAX_PAGES
  set_cc_led(CC_UP, has_prev and 45 or 0, force)
  set_cc_led(CC_LEFT, has_prev and 45 or 0, force)
  set_cc_led(CC_DOWN, has_next and 45 or 0, force)
  set_cc_led(CC_RIGHT, has_next and 45 or 0, force)
  for i = 0, 7 do
    local p = i + 1
    local v = 1
    if p == current_page then v = 9 elseif page_has_content(p) then v = 47 end
    set_cc_led(mk3_cc_for_scene(i), v, force)
  end
end

local function send_all_pad_colors(force)
  for li = 1, PAGE_SIZE do send_pad_color(page_pad(current_page, li), force) end
  update_nav_leds(force)
end

local function clear_all_leds()
  if midi_out_device < 0 then return end
  for r = 0, 7 do
    for c = 0, 7 do set_led(mk3_note_for_pad(r, c), 0, true) end
  end
  for cc = 91, 98 do set_cc_led(cc, 0, true) end
  for i = 0, 7 do set_cc_led(mk3_cc_for_scene(i), 0, true) end
end

local function flash_pad(idx)
  if pads[idx].anim_type == 1 then return end
  flash_timers[idx] = reaper.time_precise() + FLASH_TIME
  send_pad_color(idx)
end

local function start_anim(idx)
  local p = pads[idx]
  if p.anim_type < 3 or pad_page(idx) ~= current_page or not is_visible(idx) then return end
  local vel
  if p.anim_color >= 0 then vel = p.anim_color
  else vel = (p.color_vel > 0) and p.color_vel or 3 end
  if #anims >= MAX_ANIMS then table.remove(anims, 1) end
  anims[#anims + 1] = {
    r = p.row, c = p.col, vel = vel, rainbow = (p.anim_color == -2),
    t0 = reaper.time_precise(), kind = p.anim_type, speed = p.anim_speed,
    page = p.page, seed = math.random(1, 999983),
  }
end

-- Metronome pads need a fresh LED every tick (only changes are actually sent)
local function update_special_leds()
  local first = true
  for li = 1, PAGE_SIZE do
    local idx = page_pad(current_page, li)
    if pads[idx].role == 2 and is_visible(idx) then
      if first then update_beat() first = false end
      send_pad_color(idx)
    end
  end
end

local function clear_anims()
  anims = {}
  anim_overlay = {}
end

-- Recomputes the overlay and only re-sends the LEDs that changed
local function update_animations()
  if #anims == 0 and next(anim_overlay) == nil then return end
  local now = reaper.time_precise()
  local new, alive = {}, {}
  for _, a in ipairs(anims) do
    if a.page == current_page and anim_frame(a, now, new) then alive[#alive + 1] = a end
  end
  anims = alive
  local old = anim_overlay
  anim_overlay = new
  for n, v in pairs(new) do
    if old[n] ~= v then send_pad_color(page_pad(current_page, note_to_local[n])) end
  end
  for n in pairs(old) do
    if new[n] == nil then send_pad_color(page_pad(current_page, note_to_local[n])) end
  end
end

-- LED watchdog: re-sends 2 LEDs every 40 ms (the whole page every ~1.3 s), so a message that
-- got lost or overwritten fixes itself. Pulsing / animated LEDs are skipped (no visible restart).
local led_refresh_cursor = 0
local next_led_refresh = 0

local function led_refresh_tick()
  if midi_out_device < 0 then return end
  local now = reaper.time_precise()
  if now < next_led_refresh then return end
  next_led_refresh = now + 0.04
  for _ = 1, 2 do
    led_refresh_cursor = led_refresh_cursor % (PAGE_SIZE + 1) + 1
    if led_refresh_cursor > PAGE_SIZE then
      update_nav_leds(true)
    else
      local idx = page_pad(current_page, led_refresh_cursor)
      local note = pads[idx].midi_note
      local vel, ch = pad_led_state(idx)
      if ch == 0 and not anim_overlay[note] then set_led(note, vel, true, 0) end
    end
  end
end

--------------------------------------------------------------------------------
-- PLAYBACK (choke, triggers, stop)
--------------------------------------------------------------------------------

-- Pads of page p listen on MIDI channel p + 1 (status nibble = p)
local function note_on(idx, vel)
  reaper.StuffMIDIMessage(0, 0x90 | pads[idx].page, pads[idx].midi_note, vel or 127)
end

local function note_off(idx)
  reaper.StuffMIDIMessage(0, 0x80 | pads[idx].page, pads[idx].midi_note, 0)
end

local function mark_pad_active(idx)
  local pad = pads[idx]
  if not pad or pad.sample_path == "" then
    active_until[idx] = nil
    return
  end
  local now = reaper.time_precise()
  if pad.mode == 2 then
    local len = get_sample_length(pad.sample_path)
    if len <= 0 then len = 10 end
    local slice = max(0.001, (pad.end_offs or 1) - (pad.start_offs or 0)) * len
    local rate = 2 ^ ((pad.pitch_semitones or 0) / 12)
    active_until[idx] = now + slice / rate + 0.25
  else
    active_until[idx] = math.huge
  end
end

local function finish_choke(idx, do_flush)
  local e = choke_pending[idx]
  if not e then return end
  choke_pending[idx] = nil
  if not track_valid(rs5k_track) then return end
  local fx_i = rs5k_fx_indices[idx]
  if not fx_i then return end
  if e.temp_obey then
    set_p(rs5k_track, fx_i, "OBEY_OFF", (pads[idx].mode == 2) and 0.0 or 1.0)
  end
  if do_flush then
    reaper.TrackFX_SetEnabled(rs5k_track, fx_i, false)
    reaper.TrackFX_SetEnabled(rs5k_track, fx_i, true)
  end
end

local function update_choke_pending()
  if next(choke_pending) == nil then return end
  local now = reaper.time_precise()
  for i, e in pairs(choke_pending) do
    if now >= e.at then
      local retriggered = last_hit[i] and last_hit[i] > e.t0
      finish_choke(i, not retriggered)
    end
  end
end

-- Fade-out stop of one voice (RS5K release = micro-fade, never a hard cut)
local function stop_pad(idx)
  local now = reaper.time_precise()
  local fx_i = get_pad_fx_idx(idx, false)
  local temp = false
  if fx_i and rs5k_track and pads[idx].mode == 2 then
    set_p(rs5k_track, fx_i, "OBEY_OFF", 1.0)
    temp = true
  end
  if is_toggle(idx) then router_command(pads[idx].midi_note * 16 + pads[idx].page) end
  note_off(idx)
  if fx_i then
    choke_pending[idx] = { at = now + max(fade_ms, 0) / 1000 + 0.03, t0 = now, temp_obey = temp }
  end
  pressed_pads[idx] = nil
  flash_timers[idx] = nil
  active_until[idx] = nil
  send_pad_color(idx)
end

local function choke_group_cut(trig_idx)
  local trig = pads[trig_idx]
  if not trig or not trig.choke_group or trig.choke_group == 0 then return end
  local grp = trig.choke_group
  local now = reaper.time_precise()
  for i, until_t in pairs(active_until) do
    if i ~= trig_idx and pads[i].choke_group == grp and until_t > now then
      stop_pad(i)
    end
  end
end

local function trigger_pad_off(idx)
  if not pads[idx] then return end
  note_off(idx)
  pressed_pads[idx] = nil
  active_until[idx] = nil
  send_pad_color(idx)
end

-- Common bookkeeping once a pad has started (by the UI or by the hardware)
local function on_pad_started(idx, source)
  local pad = pads[idx]
  last_hit[idx] = reaper.time_precise()
  pressed_pads[idx] = true
  mark_pad_active(idx)
  flash_pad(idx)
  start_anim(idx)
  set_status(string.format("%s: %s (page %d)", source, pad.label, pad.page))
end

local run_special   -- defined after stop_all_sounds

local function trigger_pad_on(idx)
  local pad = pads[idx]
  if not pad then return end
  if pad.role ~= 1 then run_special(idx) return end
  ensure_rs5k_track_ready()

  -- Toggle loops go through the router so it remembers the loop state (same as hardware)
  if is_toggle(idx) then
    if pad.page == current_page and router_command(50000 + pad.midi_note) then return end
    if active_until[idx] then stop_pad(idx) return end
  end

  finish_choke(idx, false)
  choke_group_cut(idx)
  note_off(idx)
  note_on(idx, 127)
  on_pad_started(idx, "Playing")
end

local function stop_all_sounds(quiet)
  for i in pairs(choke_pending) do finish_choke(i, false) end
  for i = 1, NUM_PADS do
    if pads[i].sample_path ~= "" or active_until[i] then note_off(i) end
  end
  for p = 1, MAX_PAGES do reaper.StuffMIDIMessage(0, 0xB0 | p, 123, 0) end
  router_command(0)
  if track_valid(rs5k_track) then
    for i = 1, NUM_PADS do
      local fx_i = rs5k_fx_indices[i]
      if fx_i and pads[i].sample_path ~= "" then
        reaper.TrackFX_SetEnabled(rs5k_track, fx_i, false)
        reaper.TrackFX_SetEnabled(rs5k_track, fx_i, true)
      end
    end
  end
  pressed_pads, active_until, flash_timers = {}, {}, {}
  send_all_pad_colors()
  if not quiet then set_status("Sound stopped", 0xFF2D55FF) end
end

run_special = function(idx)
  local p = pads[idx]
  if p.role == 2 then
    local id = metronome_cmd()
    if id then reaper.Main_OnCommand(id, 0) end
    update_beat()
    set_status(metro.on and "Metronome ON" or "Metronome OFF", 0x34C759FF)
  elseif p.role == 3 then
    stop_all_sounds(true)
    set_status("Sound stopped (pad #" .. pad_local(idx) .. ")", 0xFF2D55FF)
  end
  last_hit[idx] = reaper.time_precise()
  flash_pad(idx)
  start_anim(idx)
  send_pad_color(idx)
end

local function update_flash_timers()
  local now = reaper.time_precise()
  for idx, t in pairs(flash_timers) do
    if now >= t then
      flash_timers[idx] = nil
      if pads[idx].mode == 2 then pressed_pads[idx] = nil end
      send_pad_color(idx)
    end
  end
  -- one-shots that finished on their own: drop the "active" flag
  for idx, t in pairs(active_until) do
    if t ~= math.huge and now > t then
      active_until[idx] = nil
      pressed_pads[idx] = nil
    end
  end
end

--------------------------------------------------------------------------------
-- PAGES
--------------------------------------------------------------------------------

local function set_page(p, quiet)
  p = clamp(floor(p), 1, MAX_PAGES)
  if p == current_page then return end
  current_page = p
  clear_anims()
  select_single(page_pad(p, 1))
  router_push_params()
  send_all_pad_colors()
  if not quiet then
    set_status(string.format("Page %d / %d%s", current_page, MAX_PAGES,
      page_has_content(current_page) and "" or "  (empty)"), 0x32ADE6FF)
  end
end

-- All 8 pages are always reachable; num_pages only remembers the highest page used
local function set_num_pages(n)
  num_pages = clamp(floor(n), 1, MAX_PAGES)
  update_nav_leds()
end

local function set_grid(rows, cols)
  grid_rows, grid_cols = clamp(rows, 1, HW_ROWS), clamp(cols, 1, HW_COLS)
  clear_anims()
  if not is_visible(selected_pad) then select_single(page_pad(current_page, 1)) end
  for i in pairs(selection) do
    if not is_visible(i) then selection[i] = nil end
  end
  router_push_params()
  led_cache = {}
  send_all_pad_colors(true)
end

--------------------------------------------------------------------------------
-- HARDWARE INPUT (router events + Launchpad navigation buttons)
--------------------------------------------------------------------------------

local function handle_hw_event(idx, is_on)
  local pad = pads[idx]
  if not pad then return end
  if is_on and pad.role ~= 1 then
    if sel_count() <= 1 then select_single(idx) end
    run_special(idx)
    return
  end
  if is_on then
    if sel_count() <= 1 then select_single(idx) end
    finish_choke(idx, false)
    choke_group_cut(idx)
    on_pad_started(idx, "Pad")
  else
    pressed_pads[idx] = nil
    flash_timers[idx] = nil
    if pad.mode ~= 2 then active_until[idx] = nil end
    send_pad_color(idx)
  end
end

local function poll_router()
  local idx = find_router()
  if idx < 0 then return false end
  local cnt = floor(reaper.TrackFX_GetParam(rs5k_track, idx, P_EVCOUNT) + 0.5)
  if router_counter == nil then
    router_counter = cnt
    return true
  end
  local diff = (cnt - router_counter) % 1000000
  router_counter = cnt
  if diff == 0 then return true end
  if diff > 16 then diff = 16 end
  for k = diff - 1, 0, -1 do
    local c = (cnt - k) % 1000000
    local code = floor(reaper.TrackFX_GetParam(rs5k_track, idx, P_EV0 + (c % 16)) + 0.5)
    local kind, note = code // 1000, code % 1000
    local li = note_to_local[note]
    if li then
      local here = page_pad(current_page, li)
      if kind == 1 then
        hw_note_pad[note] = here
        handle_hw_event(here, true)
      elseif kind == 2 then
        local target = is_toggle(here) and here or (hw_note_pad[note] or here)
        hw_note_pad[note] = nil
        handle_hw_event(target, false)
      end
    end
  end
  return true
end

local function handle_nav_cc(cc)
  if cc == CC_UP or cc == CC_LEFT then
    set_page(current_page - 1)
  elseif cc == CC_DOWN or cc == CC_RIGHT then
    set_page(current_page + 1)
  elseif cc >= 19 and cc <= 89 and cc % 10 == 9 then
    set_page(9 - cc // 10)
  end
end

-- Without the router (fallback) pad notes are handled here too, with defer latency
local function fallback_note(note, is_on)
  local li = note_to_local[note]
  if not li then return end
  local idx = page_pad(current_page, li)
  if not is_visible(idx) then return end
  local pad = pads[idx]
  if is_on then
    if is_toggle(idx) and active_until[idx] then stop_pad(idx) return end
    if sel_count() <= 1 then select_single(idx) end
    trigger_pad_on(idx)
  elseif pad.role == 1 and (pad.mode == 1 or (pad.mode == 3 and not pad.loop_toggle)) then
    trigger_pad_off(idx)
  end
end

local function poll_recent_midi(router_present)
  if not reaper.MIDI_GetRecentInputEvent then return end
  local events = {}
  for i = 0, 15 do
    local seq, buf, _, devIdx = reaper.MIDI_GetRecentInputEvent(i)
    if not seq or seq == 0 then break end
    if last_midi_seq and seq <= last_midi_seq then break end
    events[#events + 1] = { buf = buf, dev = devIdx }
  end
  local top_seq = reaper.MIDI_GetRecentInputEvent(0)
  if top_seq and top_seq ~= 0 then last_midi_seq = top_seq end

  for k = #events, 1, -1 do
    local ev = events[k]
    local in_dev = ev.dev and (ev.dev & 0xFFFF) or -1
    local is_match = (midi_in_device < 0) or (in_dev == midi_in_device)
    local buf = ev.buf
    if is_match and buf and #buf >= 3 then
      local b1, b2, b3 = string.byte(buf, 1, 3)
      local st, ch = b1 & 0xF0, b1 & 0x0F
      if ch == 0 then
        if st == 0xB0 and b3 > 0 then
          handle_nav_cc(b2)
        elseif not router_present then
          if st == 0x90 and b3 > 0 then fallback_note(b2, true)
          elseif st == 0x80 or (st == 0x90 and b3 == 0) then fallback_note(b2, false) end
        end
      end
    end
  end
end

local function poll_hardware_midi_input()
  local router_present = poll_router()
  poll_recent_midi(router_present)
end

--------------------------------------------------------------------------------
-- MOVE PADS (drag & drop on the grid)
--------------------------------------------------------------------------------

local function move_pads(src, dst)
  if not src or not dst or src == dst then return end
  if pad_page(src) ~= current_page or pad_page(dst) ~= current_page then return end

  local group = (selection[src] and sel_count() > 1) and sel_list() or { src }
  local dr = pads[dst].row - pads[src].row
  local dc = pads[dst].col - pads[src].col

  local map, in_a, in_b = {}, {}, {}
  for _, g in ipairs(group) do
    local nr, nc = pads[g].row + dr, pads[g].col + dc
    if nr < 0 or nr >= grid_rows or nc < 0 or nc >= grid_cols then
      set_status("[!] The selection does not fit there", 0xFF9500FF)
      return
    end
    local t = page_pad(current_page, nr * HW_COLS + nc + 1)
    map[g] = t
    in_a[g] = true
    in_b[t] = true
  end

  -- pads covered by the moved group go to the places the group left
  local vacated, displaced = {}, {}
  for _, g in ipairs(group) do
    if not in_b[g] then vacated[#vacated + 1] = g end
    if not in_a[map[g]] then displaced[#displaced + 1] = map[g] end
  end
  table.sort(vacated)
  table.sort(displaced)

  local content, touched = {}, {}
  for g in pairs(in_a) do content[g] = get_content(pads[g]); touched[g] = true end
  for t in pairs(in_b) do content[t] = content[t] or get_content(pads[t]); touched[t] = true end

  for i in pairs(touched) do
    if active_until[i] then stop_pad(i) end
  end

  local new_content = {}
  for _, g in ipairs(group) do new_content[map[g]] = content[g] end
  for k = 1, #vacated do new_content[vacated[k]] = content[displaced[k]] end

  reaper.PreventUIRefresh(1)
  for i, c in pairs(new_content) do
    set_content(pads[i], c)
    apply_pad_to_rs5k(i)
    send_pad_color(i)
  end
  reaper.PreventUIRefresh(-1)

  selection = {}
  for _, g in ipairs(group) do selection[map[g]] = true end
  selected_pad = map[src]
  sel_anchor = selected_pad
  router_flags_dirty = true
  save_state(false)
  set_status(string.format("[MOVE] %d pad(s) moved", #group), 0x32ADE6FF)
end

--------------------------------------------------------------------------------
-- SOURCE TRACK HELPERS
--------------------------------------------------------------------------------

local function get_bounces_dir()
  local proj_path = reaper.GetProjectPath("")
  local dir
  if proj_path and proj_path ~= "" then
    dir = proj_path .. "/LittleThings_Bounces"
  else
    dir = reaper.GetResourcePath() .. "/Scripts/LittleThings_Bounces"
  end
  reaper.RecursiveCreateDirectory(dir, 0)
  return dir
end

local function get_source_track()
  local tr = reaper.GetSelectedTrack(0, 0)
  if tr and tr ~= rs5k_track then
    local _, tn = reaper.GetTrackName(tr)
    if tn ~= TRACK_NAME then return tr end
  end
  local it = reaper.GetSelectedMediaItem(0, 0)
  if it then
    local itr = reaper.GetMediaItem_Track(it)
    if itr and itr ~= rs5k_track then
      local _, tn = reaper.GetTrackName(itr)
      if tn ~= TRACK_NAME then return itr end
    end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    if t ~= rs5k_track then
      local _, tn = reaper.GetTrackName(t)
      if tn ~= TRACK_NAME then return t end
    end
  end
  return nil
end

local function silence_selected_range_on_source_track()
  local track = get_source_track()
  if not track then
    set_status("[!] Select a source track first", 0xFF3B30FF)
    return
  end
  local _, tr_name = reaper.GetTrackName(track)
  local t_start, t_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if t_end <= t_start then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
      t_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      t_end = t_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    else
      set_status("[!] Select a time selection or item on the timeline", 0xFF3B30FF)
      return
    end
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local to_delete = {}
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local iend = ipos + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if ipos < t_end and iend > t_start then
      if iend > t_end then reaper.SplitMediaItem(it, t_end) end
      local mid_item = it
      if ipos < t_start then mid_item = reaper.SplitMediaItem(it, t_start) end
      if mid_item then to_delete[#to_delete + 1] = mid_item end
    end
  end
  for _, it in ipairs(to_delete) do reaper.DeleteTrackMediaItem(track, it) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Little Things: Silence Audio on Source Track", -1)
  set_status(string.format("[CUT] Audio removed from [%s] (%.2fs - %.2fs)", tr_name, t_start, t_end), 0xFF3B30FF)
end

local function solo_lt_chops_track()
  if not track_valid(rs5k_track) then return end
  local cur = reaper.GetMediaTrackInfo_Value(rs5k_track, "I_SOLO")
  local new = (cur > 0.5) and 0 or 1
  reaper.SetMediaTrackInfo_Value(rs5k_track, "I_SOLO", new)
  set_status(string.format("LT Chops track %s", (new == 1) and "SOLOED" or "UN-SOLOED"), (new == 1) and 0xFF9500FF or 0x34C759FF)
end

-- The source track is ONLY muted when "Auto-mute source" is ON; otherwise it is restored.
local function apply_source_mute_policy(track, original_mute)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_MUTE", auto_mute_source_track and 1 or original_mute)
end

local function clear_time_selection()
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
  reaper.UpdateTimeline()
end

--------------------------------------------------------------------------------
-- INSTANT CHOP / RANGE CAPTURE (MIDI OR WAV)
--------------------------------------------------------------------------------

-- Returns: path, duration, is_sliced_source, slice_start (0..1), slice_end (0..1)
--   or:    nil, error message
local function capture_timeline_range_audio()
  local t_start, t_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_sel = (t_end > t_start and (t_end - t_start) > 0.005)

  local track = get_source_track()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not track and item then track = reaper.GetMediaItem_Track(item) end
  if not track then return nil, "No source track found in project" end
  reaper.SetOnlyTrackSelected(track)

  if not has_time_sel then
    if item then
      t_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      t_end = t_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      reaper.GetSet_LoopTimeRange(true, false, t_start, t_end, false)
    else
      return nil, "Make a time selection or select an item on the timeline"
    end
  end

  local range_dur = t_end - t_start
  if range_dur <= 0.005 then return nil, "Selected range is too short" end

  reaper.Undo_BeginBlock()
  local n_before = reaper.CountTracks(0)
  local orig_mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
  if orig_mute > 0.5 then reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0) end

  -- Render selected area of tracks to stereo post-fader stem tracks
  reaper.Main_OnCommand(41716, 0)

  local n_after = reaper.CountTracks(0)
  local wav_path = nil
  if n_after > n_before then
    local stem_track = nil
    for i = 0, n_after - 1 do
      local t = reaper.GetTrack(0, i)
      if t ~= track and t ~= rs5k_track then
        local _, name = reaper.GetTrackName(t)
        if name:lower():find("stem") then stem_track = t break end
      end
    end
    if not stem_track then stem_track = reaper.GetTrack(0, n_after - 1) end
    if stem_track then
      local stem_item = reaper.GetTrackMediaItem(stem_track, 0)
      if stem_item then
        local take = reaper.GetActiveTake(stem_item)
        if take then wav_path = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take), "") end
      end
      reaper.DeleteTrack(stem_track)
    end
  end

  apply_source_mute_policy(track, orig_mute)
  reaper.SetOnlyTrackSelected(track)
  reaper.Undo_EndBlock("Little Things: Capture Range", -1)

  if wav_path and wav_path ~= "" and file_exists(wav_path) then
    local fname = basename(wav_path)
    if fname == "" then fname = string.format("Chop_%d.wav", os.time()) end
    local safe_path = get_bounces_dir() .. "/" .. fname
    if wav_path ~= safe_path and copy_file(wav_path, safe_path) then wav_path = safe_path end
    return wav_path, range_dur, false, 0.0, 1.0
  end

  -- Render failed: fall back to the item's own source file and compute the slice
  if item then
    local take = reaper.GetActiveTake(item)
    if take and not reaper.TakeIsMIDI(take) then
      local src = reaper.GetMediaItemTake_Source(take)
      local fpath = reaper.GetMediaSourceFileName(src, "")
      if fpath and fpath ~= "" and file_exists(fpath) then
        local s0, s1 = 0.0, 1.0
        local src_len = reaper.GetMediaSourceLength(src)
        if src_len and src_len > 0 then
          local s_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
          local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
          if not rate or rate <= 0 then rate = 1.0 end
          local it_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local it_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local rel_start = max(0, t_start - it_pos)
          local rel_end = min(it_len, t_end - it_pos)
          if rel_end > rel_start then
            s0 = clamp((s_offs + rel_start * rate) / src_len, 0.0, 1.0)
            s1 = clamp((s_offs + rel_end * rate) / src_len, 0.0, 1.0)
          end
        end
        return fpath, range_dur, true, s0, s1
      end
    end
  end

  return nil, "Render failed: the selected track needs audio or MIDI in this range"
end

local function send_range_to_selected_pad()
  local target = selected_pad
  local wav_path, err, is_sliced, s0, s1 = capture_timeline_range_audio()
  if not wav_path then
    set_status("[!] " .. (err or "Capture failed"), 0xFF3B30FF)
    return false
  end
  clear_time_selection()  -- ready for the next grab straight away

  ensure_rs5k_track_ready()
  local pad = pads[target]
  apply_capture_defaults(pad, 1)
  load_sample_to_rs5k(target, wav_path, s0, s1, { bounced = not is_sliced })
  pad.label = string.format("Chop %02d", pad_local(target))
  if pad.color_vel == 0 then
    pad.color_vel = CHOP_COLORS[((pad_local(target) - 1) % #CHOP_COLORS) + 1]
  end
  send_pad_color(target)
  trigger_pad_on(target)

  local next_pad = target
  if auto_advance then
    next_pad = next_usable(target)
    if pad_page(next_pad) ~= current_page then set_page(pad_page(next_pad), true) end
    select_single(next_pad)
  end
  set_status(string.format("[OK] Captured to pad %d (page %d)  ->  next: pad %d", pad_local(target), pad.page, pad_local(next_pad)), 0x34C759FF)
  return true
end

local function chop_range_into_n_pads(num_chops)
  local targets = usable_from(page_pad(current_page, 1), num_chops)
  if #targets == 0 then
    set_status("[!] No free pads to chop into", 0xFF3B30FF)
    return false
  end

  local wav_path, err, is_sliced, s0, s1 = capture_timeline_range_audio()
  if not wav_path then
    set_status("[!] " .. (err or "Chop failed"), 0xFF3B30FF)
    return false
  end
  clear_time_selection()

  ensure_rs5k_track_ready()
  local count = #targets
  local span = s1 - s0

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for k, idx in ipairs(targets) do
    local pad = pads[idx]
    apply_capture_defaults(pad, chop_choke and 1 or 0)
    if pad.color_vel == 0 then pad.color_vel = CHOP_COLORS[((k - 1) % #CHOP_COLORS) + 1] end
    load_sample_to_rs5k(idx, wav_path, s0 + span * (k - 1) / count, s0 + span * k / count, { bounced = not is_sliced })
    pad.label = string.format("Chop %02d", k)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Little Things: Chop Range", -1)

  local last_page = pad_page(targets[count])
  if last_page > num_pages then set_num_pages(last_page) end
  send_all_pad_colors()
  select_single(targets[1])
  trigger_pad_on(targets[1])

  local extra = (last_page > current_page) and string.format(" (pages %d-%d)", current_page, last_page) or ""
  set_status(string.format("[OK] Sliced range into %d pads%s", count, extra), 0x34C759FF)
  return true
end

local function items_to_pads()
  local track = get_source_track()
  if not track then
    set_status("[!] Select the track whose items should go to the pads", 0xFF3B30FF)
    return false
  end
  local _, tr_name = reaper.GetTrackName(track)
  local n_items = reaper.CountTrackMediaItems(track)
  if n_items == 0 then
    set_status(string.format("[!] Track [%s] has no items", tr_name), 0xFF3B30FF)
    return false
  end

  local list, skipped = {}, 0
  for i = 0, n_items - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local take = it and reaper.GetActiveTake(it)
    local ok = false
    if take and not reaper.TakeIsMIDI(take) then
      local src = reaper.GetMediaItemTake_Source(take)
      local path = src and reaper.GetMediaSourceFileName(src, "") or ""
      local src_len, is_qn = 0, false
      if src then src_len, is_qn = reaper.GetMediaSourceLength(src) end
      if path ~= "" and file_exists(path) and src_len and src_len > 0 and not is_qn then
        local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        if not rate or rate <= 0 then rate = 1.0 end
        local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        local s = clamp(offs / src_len, 0.0, 1.0)
        local e = clamp((offs + ilen * rate) / src_len, 0.0, 1.0)
        if e > s + 0.00001 then
          list[#list + 1] = {
            pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
            order = i, path = path, s = s, e = e, name = reaper.GetTakeName(take),
          }
          ok = true
        end
      end
    end
    if not ok then skipped = skipped + 1 end
  end

  if #list == 0 then
    set_status(string.format("[!] No audio items on [%s] (%d skipped)", tr_name, skipped), 0xFF3B30FF)
    return false
  end

  table.sort(list, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.order < b.order
  end)

  ensure_rs5k_track_ready()
  local targets = usable_from(selected_pad, #list)
  local count = #targets
  local orig_mute = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for k = 1, count do
    local idx = targets[k]
    local entry = list[k]
    local pad = pads[idx]
    apply_capture_defaults(pad, chop_choke and 1 or 0)
    if pad.color_vel == 0 then pad.color_vel = CHOP_COLORS[((k - 1) % #CHOP_COLORS) + 1] end
    load_sample_to_rs5k(idx, entry.path, entry.s, entry.e, { bounced = false })
    local name = strip_ext(entry.name or "")
    pad.label = (name ~= "") and name or string.format("Item %02d", k)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Little Things: Track Items to Pads", -1)

  apply_source_mute_policy(track, orig_mute)
  if count > 0 then
    local last_page = pad_page(targets[count])
    if last_page > num_pages then set_num_pages(last_page) end
  end
  send_all_pad_colors()

  local msg = string.format("[OK] %d item(s) from [%s] loaded", count, tr_name)
  local extra = {}
  if #list > count then extra[#extra + 1] = string.format("%d did not fit", #list - count) end
  if skipped > 0 then extra[#extra + 1] = string.format("%d skipped (MIDI/empty)", skipped) end
  if #extra > 0 then msg = msg .. " (" .. table.concat(extra, ", ") .. ")" end
  set_status(msg, (#extra > 0) and 0xFF9500FF or 0x34C759FF)
  return true
end

local function get_timeline_display_text()
  local t_start, t_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_sel = (t_end > t_start and (t_end - t_start) > 0.005)
  local track = get_source_track()
  local item = reaper.GetSelectedMediaItem(0, 0)
  local tr_name = "-"
  if track then
    local _, tn = reaper.GetTrackName(track)
    tr_name = tn
  end
  if has_time_sel then
    return string.format("Range %.2fs - %.2fs (%.2fs) on [%s]", t_start, t_end, t_end - t_start, tr_name), 0x007AFFFF
  elseif item then
    local take = reaper.GetActiveTake(item)
    local name = take and reaper.GetTakeName(take) or "Item"
    return string.format("Item '%s' (%.2fs) on [%s]", name, reaper.GetMediaItemInfo_Value(item, "D_LENGTH"), tr_name), 0xFF9500FF
  end
  return "Select a time range (or an item) in REAPER, then Send or Chop", 0x8E8E93FF
end

--------------------------------------------------------------------------------
-- DELETE / CLEAR
--------------------------------------------------------------------------------

local function delete_pad_chop(idx, quiet)
  local pad = pads[idx]
  if not pad then return end
  local old_path, was_bounced = pad.sample_path, pad.is_bounced

  if active_until[idx] then stop_pad(idx) end
  reset_pad_content(pad)

  local fx_idx = get_pad_fx_idx(idx, false)
  if rs5k_track and fx_idx then clear_rs5k_sample(rs5k_track, fx_idx) end
  send_pad_color(idx)

  if old_path ~= "" and was_bounced then
    local in_use = false
    for i = 1, NUM_PADS do
      if i ~= idx and pads[i].sample_path == old_path then in_use = true break end
    end
    if not in_use then
      pcall(os.remove, old_path)
      pcall(os.remove, old_path .. ".reapeaks")
    end
  end
  router_flags_dirty = true
  if not quiet then set_status(string.format("[DEL] Pad %d cleared", pad_local(idx)), 0x8E8E93FF) end
end

local function delete_selection()
  local list = sel_list()
  for _, idx in ipairs(list) do delete_pad_chop(idx, true) end
  set_status(string.format("[DEL] %d pad(s) cleared", #list), 0x8E8E93FF)
end

local function clear_all_pads()
  local paths_to_delete = {}
  for i = 1, NUM_PADS do
    if pads[i].is_bounced and pads[i].sample_path ~= "" then paths_to_delete[pads[i].sample_path] = true end
  end
  stop_all_sounds(true)
  init_pads()
  if track_valid(rs5k_track) then
    reaper.PreventUIRefresh(1)
    for i, fx_idx in pairs(rs5k_fx_indices) do
      if fx_still_valid(i, fx_idx) then clear_rs5k_sample(rs5k_track, fx_idx) end
    end
    reaper.PreventUIRefresh(-1)
  end
  for p in pairs(paths_to_delete) do
    pcall(os.remove, p)
    pcall(os.remove, p .. ".reapeaks")
  end
  select_single(page_pad(current_page, 1))
  router_flags_dirty = true
  led_cache = {}
  send_all_pad_colors(true)
  set_status("[DEL] Cleared all pads and deleted chops", 0x8E8E93FF)
end

--------------------------------------------------------------------------------
-- KITS (portable: kit file + samples folder)
--   <kits dir>/<Name>/<Name>.ltkit
--   <kits dir>/<Name>/samples/*.wav
--------------------------------------------------------------------------------

local function get_kits_dir()
  local dir = reaper.GetResourcePath() .. "/Scripts/LittleThings_Kits"
  reaper.RecursiveCreateDirectory(dir, 0)
  return dir
end

local function write_kit_package(base_dir, name)
  local sname = safe_name(name)
  local kit_dir = base_dir .. "/" .. sname
  local smp_dir = kit_dir .. "/samples"
  reaper.RecursiveCreateDirectory(smp_dir, 0)

  local exported, used_names = {}, {}
  local lines = {
    "LTKIT 2",
    "name=" .. esc(name),
    string.format("master=%.3f", master_volume),
    "pages=" .. num_pages,
  }
  local missing, n_pads = 0, 0

  for i = 1, NUM_PADS do
    local p = pads[i]
    if not pad_is_default(p) then
      local rel = ""
      if p.sample_path ~= "" then
        if exported[p.sample_path] then
          rel = exported[p.sample_path]
        elseif file_exists(p.sample_path) then
          local fname = basename(p.sample_path)
          local base, ext = fname:match("^(.*)(%.[^%.]+)$")
          if not base then base, ext = fname, "" end
          local cand, n = fname, 2
          while used_names[cand:lower()] do
            cand = string.format("%s_%d%s", base, n, ext)
            n = n + 1
          end
          used_names[cand:lower()] = true
          if copy_file(p.sample_path, smp_dir .. "/" .. cand) then
            rel = "samples/" .. cand
            exported[p.sample_path] = rel
          else
            missing = missing + 1
          end
        else
          missing = missing + 1
        end
      end
      lines[#lines + 1] = "pad=" .. table.concat({
        i, esc(p.label), esc(rel),
        string.format("%.6f", p.start_offs or 0), string.format("%.6f", p.end_offs or 1),
        p.color_vel or 0, p.mode or 2, p.loop_toggle and 1 or 0,
        string.format("%.3f", p.volume or 1), p.velocity_sensitive and 1 or 0,
        p.pitch_semitones or 0, p.choke_group or 0,
        p.role, p.anim_type, p.anim_color, p.anim_speed,
      }, "|")
      n_pads = n_pads + 1
    end
  end

  local kit_path = kit_dir .. "/" .. sname .. ".ltkit"
  local f = io.open(kit_path, "w")
  if not f then return nil, "permission denied writing " .. kit_path end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  return kit_path, kit_dir, missing, n_pads
end

local function parse_kit_v2(text)
  local data = { pads = {} }
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^(%w+)=(.*)$")
    if k == "name" then data.name = unesc(v)
    elseif k == "master" then data.master_volume = tonumber(v)
    elseif k == "pages" then data.pages = tonumber(v)
    elseif k == "pad" then
      local f = split(v, "|")
      local idx = tonumber(f[1])
      if idx and #f >= 12 then
        data.pads[#data.pads + 1] = {
          idx = floor(idx),
          label = unesc(f[2]),
          sample_path = unesc(f[3]),
          start_offs = tonumber(f[4]) or 0,
          end_offs = tonumber(f[5]) or 1,
          color_vel = tonumber(f[6]) or 0,
          mode = tonumber(f[7]) or 2,
          loop_toggle = f[8] == "1",
          volume = tonumber(f[9]) or 1,
          velocity_sensitive = f[10] == "1",
          pitch_semitones = tonumber(f[11]) or 0,
          choke_group = tonumber(f[12]) or 0,
          role = f[13], anim_type = f[14], anim_color = f[15], anim_speed = f[16],
        }
      end
    end
  end
  return data
end

-- v1.x kits were Lua tables: load them in an empty sandbox (no os / io access)
local function parse_kit_legacy(text)
  local chunk = load(text, "ltkit", "t", {})
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return nil end
  local out = { name = data.name, master_volume = data.master_volume, pads = {} }
  for i, p in ipairs(data.pads or {}) do
    if type(p) == "table" then
      out.pads[#out.pads + 1] = {
        idx = i, label = p.label, sample_path = p.sample_path or "",
        start_offs = p.start_offs or 0, end_offs = p.end_offs or 1,
        color_vel = p.color_vel or 0, mode = p.mode or 2, loop_toggle = false,
        volume = p.volume or 1, velocity_sensitive = p.velocity_sensitive == true,
        pitch_semitones = p.pitch_semitones or 0, choke_group = p.choke_group or 0,
      }
    end
  end
  return out
end

local function resolve_kit_sample(path, kit_dir)
  if path == "" then return "" end
  if not is_abs_path(path) then
    local p = kit_dir .. "/" .. path
    if file_exists(p) then return p end
  elseif file_exists(path) then
    return path
  end
  local fname = basename(path)
  for _, cand in ipairs({ kit_dir .. "/samples/" .. fname, kit_dir .. "/" .. fname, get_bounces_dir() .. "/" .. fname }) do
    if file_exists(cand) then return cand end
  end
  return ""
end

local function load_kit(path)
  local text = read_file(path)
  if not text then
    set_status("[!] Could not read kit file", 0xFF3B30FF)
    return false
  end
  local data
  if text:sub(1, 7) == "LTKIT 2" then data = parse_kit_v2(text) else data = parse_kit_legacy(text) end
  if not data then
    set_status("[!] Corrupt kit file", 0xFF3B30FF)
    return false
  end

  local kit_dir = dirname(path)
  current_kit_name = (data.name and data.name ~= "") and data.name or strip_ext(basename(path))
  master_volume = clamp(tonumber(data.master_volume) or 1.0, 0.0, 1.0)

  -- samples are copied into this project, so the project keeps working without the kit folder
  local dest_dir = get_bounces_dir() .. "/Kit_" .. safe_name(current_kit_name)
  reaper.RecursiveCreateDirectory(dest_dir, 0)

  stop_all_sounds(true)
  ensure_rs5k_track_ready()
  reaper.PreventUIRefresh(1)

  for i = 1, NUM_PADS do
    if not pad_is_default(pads[i]) then
      reset_pad_content(pads[i])
      local fx = get_pad_fx_idx(i, false)
      if fx then clear_rs5k_sample(rs5k_track, fx) end
    end
  end

  local missing, highest = 0, 1
  for _, rec in ipairs(data.pads) do
    local p = pads[rec.idx]
    if p then
      p.label = (rec.label and rec.label ~= "") and rec.label or default_label(p.row, p.col)
      p.start_offs = clamp(rec.start_offs, 0, 1)
      p.end_offs = clamp(rec.end_offs, 0, 1)
      p.color_vel = clamp(floor(rec.color_vel), 0, 127)
      p.mode = clamp(floor(rec.mode), 1, 3)
      p.loop_toggle = rec.loop_toggle
      p.volume = clamp(rec.volume, 0, 1)
      p.velocity_sensitive = rec.velocity_sensitive
      p.pitch_semitones = clamp(floor(rec.pitch_semitones), -12, 12)
      p.choke_group = clamp(floor(rec.choke_group), 0, 4)
      p.is_bounced = false
      apply_fx_fields(p, rec.role, rec.anim_type, rec.anim_color, rec.anim_speed)

      local src = resolve_kit_sample(rec.sample_path or "", kit_dir)
      if src ~= "" then
        local dst = dest_dir .. "/" .. basename(src)
        if file_exists(dst) or copy_file(src, dst) then src = dst end
        p.sample_path = src
        load_sample_to_rs5k(rec.idx, src, p.start_offs, p.end_offs, { keep = true })
        highest = max(highest, p.page)
      elseif (rec.sample_path or "") ~= "" then
        missing = missing + 1
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  for i = 1, NUM_PADS do
    if pads[i].sample_path ~= "" then update_rs5k_volume(i) end
  end
  set_num_pages(max(tonumber(data.pages) or 1, highest))
  select_single(page_pad(current_page, 1))
  router_flags_dirty = true
  led_cache, cc_cache = {}, {}
  send_all_pad_colors(true)
  schedule_led_sync(0.25)
  save_state(true)
  if missing > 0 then
    set_status(string.format("[OK] Kit '%s' loaded - %d sample(s) missing", current_kit_name, missing), 0xFF9500FF)
  else
    set_status("[OK] Kit loaded: " .. current_kit_name, 0x34C759FF)
  end
  return true
end

local function save_kit(name)
  local kit_path, kit_dir_or_err, missing, n = write_kit_package(get_kits_dir(), name)
  if not kit_path then
    set_status("[!] Error saving kit: " .. tostring(kit_dir_or_err), 0xFF3B30FF)
    return false
  end
  current_kit_name = name
  local extra = (missing and missing > 0) and string.format(" (%d sample(s) missing)", missing) or ""
  set_status(string.format("[OK] Kit saved: %s - %d pads with audio%s", name, n or 0, extra), 0x34C759FF)
  return true
end

local function export_kit(name)
  local base = get_kits_dir() .. "/Exports"
  if reaper.JS_Dialog_BrowseForFolder then
    local rv, folder = reaper.JS_Dialog_BrowseForFolder("Export kit to folder", base)
    if rv ~= 1 or not folder or folder == "" then return false end
    base = folder
  end
  reaper.RecursiveCreateDirectory(base, 0)
  local kit_path, kit_dir, missing = write_kit_package(base, name)
  if not kit_path then
    set_status("[!] Export failed: " .. tostring(kit_dir), 0xFF3B30FF)
    return false
  end
  open_url(kit_dir)
  local extra = (missing and missing > 0) and string.format(" (%d sample(s) missing)", missing) or ""
  set_status("[OK] Exported to " .. kit_dir .. extra .. " - send the whole folder", 0x34C759FF)
  return true
end

local function import_kit()
  local rv, file = reaper.GetUserFileNameForRead(get_kits_dir() .. "/", "Import Little Things kit (.ltkit)", "ltkit")
  if rv and file and file ~= "" then return load_kit(file) end
  return false
end

local function list_kits()
  local dir = get_kits_dir()
  local kits = {}
  reaper.EnumerateSubdirectories(dir, -1)
  reaper.EnumerateFiles(dir, -1)
  local i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    if sub ~= "Exports" then
      local subdir = dir .. "/" .. sub
      reaper.EnumerateFiles(subdir, -1)
      local j = 0
      while true do
        local f = reaper.EnumerateFiles(subdir, j)
        if not f then break end
        if f:match("%.ltkit$") then
          kits[#kits + 1] = { name = strip_ext(f):gsub("_", " "), path = subdir .. "/" .. f }
          break
        end
        j = j + 1
      end
    end
    i = i + 1
  end
  i = 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    if f:match("%.ltkit$") then
      kits[#kits + 1] = { name = strip_ext(f):gsub("_", " ") .. " (v1)", path = dir .. "/" .. f }
    end
    i = i + 1
  end
  table.sort(kits, function(a, b) return a.name:lower() < b.name:lower() end)
  return kits
end

--------------------------------------------------------------------------------
-- PAD EDITS (applied to every selected pad)
--------------------------------------------------------------------------------

local function set_pad_mode(idx, mode, toggle)
  local p = pads[idx]
  local new_toggle = p.loop_toggle
  if toggle ~= nil then new_toggle = toggle end
  local becomes_toggle = (mode == 3 and new_toggle)
  if active_until[idx] and (is_toggle(idx) ~= becomes_toggle or p.mode ~= mode) then stop_pad(idx) end
  p.mode = mode
  p.loop_toggle = new_toggle
  local fx = get_pad_fx_idx(idx, false)
  if fx and rs5k_track then
    set_p(rs5k_track, fx, "OBEY_OFF", (mode == 2) and 0.0 or 1.0)
    set_p(rs5k_track, fx, "LOOP", (mode == 3) and 1.0 or 0.0)
  end
  router_flags_dirty = true
end

-- Sample pad <-> special pad. A special pad has no sound, so its chop is removed first.
local function set_pad_role(idx, role)
  local p = pads[idx]
  if p.role == role then return end
  if role ~= 1 then
    if p.sample_path ~= "" or active_until[idx] then
      local color, at, ac, asp = p.color_vel, p.anim_type, p.anim_color, p.anim_speed
      delete_pad_chop(idx, true)
      p.color_vel, p.anim_type, p.anim_color, p.anim_speed = color, at, ac, asp
    end
    p.label = (role == 2) and "Metronome" or "Stop"
    if p.color_vel == 0 then p.color_vel = (role == 2) and 21 or 5 end
  elseif p.label == "Metronome" or p.label == "Stop" then
    p.label = default_label(p.row, p.col)
  end
  p.role = role
  router_flags_dirty = true
  send_pad_color(idx)
end

--------------------------------------------------------------------------------
-- REAIMGUI
--------------------------------------------------------------------------------

local function init_imgui()
  if not reaper.ImGui_CreateContext then return false end
  ctx = reaper.ImGui_CreateContext("LittleThings_ChopEngine_v2")
  font_main = reaper.ImGui_CreateFont("Arial", 0)
  reaper.ImGui_Attach(ctx, font_main)
  return true
end

local function child_border_flag()
  return reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders() or 1
end

local function small_label(text)
  reaper.ImGui_PushFont(ctx, font_main, 10)
  reaper.ImGui_TextColored(ctx, 0x8E8E93FF, text)
  reaper.ImGui_PopFont(ctx)
end

local function tooltip(text)
  if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, text) end
end

local function key_mods()
  if not reaper.ImGui_GetKeyMods then return false, false end
  local m = reaper.ImGui_GetKeyMods(ctx)
  local shift = (m & reaper.ImGui_Mod_Shift()) ~= 0
  local ctrl = (m & reaper.ImGui_Mod_Ctrl()) ~= 0
  if not ctrl and reaper.ImGui_Mod_Super then ctrl = (m & reaper.ImGui_Mod_Super()) ~= 0 end
  return shift, ctrl
end

local function colored_button(label, col, w, h)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(col, 1.15))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), brighten_color(col, 0.8))
  local r = reaper.ImGui_Button(ctx, label, w or 0, h or 0)
  reaper.ImGui_PopStyleColor(ctx, 3)
  return r
end

-- Gear icon drawn with the draw list (no font glyph needed)
local function gear_button(id, size)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local col = hovered and 0xFF9500FF or 0xC7C7CCFF
  local cx, cy = x + size / 2, y + size / 2
  local r_out, r_in = size * 0.46, size * 0.30
  for k = 0, 7 do
    local a = k * math.pi / 4
    reaper.ImGui_DrawList_AddLine(dl, cx + math.cos(a) * r_in, cy + math.sin(a) * r_in,
      cx + math.cos(a) * r_out, cy + math.sin(a) * r_out, col, size * 0.17)
  end
  reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, r_in, col)
  reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, size * 0.13, 0x1A1B22FF)
  return clicked
end

-- Color picker component: a swatch that opens the Launchpad palette
local function color_picker(id, vel, label)
  local changed, new_vel = false, vel
  local col = get_color_for_vel(vel)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(col, 1.2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
  if reaper.ImGui_Button(ctx, "##swatch" .. id, 34, 20) then
    reaper.ImGui_OpenPopup(ctx, "cp_" .. id)
  end
  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_PopStyleColor(ctx, 3)
  tooltip("Click to pick the pad / LED color")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, (label and (label .. ": ") or "") .. get_name_for_vel(vel))

  if reaper.ImGui_BeginPopup(ctx, "cp_" .. id) then
    small_label("LED COLOR")
    for k, c in ipairs(PALETTE) do
      if (k - 1) % 7 ~= 0 then reaper.ImGui_SameLine(ctx, 0, 4) end
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), c.hex)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(c.hex, 1.2))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF)
      local is_sel = (c.vel == vel)
      if is_sel then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 2.0)
      end
      if reaper.ImGui_Button(ctx, (is_sel and "x" or "") .. "##cv" .. id .. c.vel, 26, 20) then
        changed, new_vel = true, c.vel
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if is_sel then
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx)
      end
      reaper.ImGui_PopStyleColor(ctx, 3)
      tooltip(c.name .. " (vel " .. c.vel .. ")")
    end
    reaper.ImGui_EndPopup(ctx)
  end
  return changed, new_vel
end

-- GUI color for any LED velocity (dim shades that are not in PALETTE are darkened)
local function vel_gui_color(v)
  if VEL_TO_COLOR[v] then return VEL_TO_COLOR[v] end
  if v >= 4 and v <= 63 then
    local base = (v % 4 == 0) and (v + 1) or (v - ((v - 1) % 4))
    return brighten_color(get_color_for_vel(base), 0.45)
  end
  return get_color_for_vel(v)
end

local function anim_color_name(v)
  if v == -1 then return "Pad color" elseif v == -2 then return "Rainbow" end
  return get_name_for_vel(v)
end

-- Animation color: pad color, rainbow, or any Launchpad color
local function anim_color_picker(id, value, pad_vel)
  local changed, new_value = false, value
  local swatch = (value >= 0) and get_color_for_vel(value)
    or ((value == -2) and 0xFF9500FF or get_color_for_vel((pad_vel > 0) and pad_vel or 3))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), swatch)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(swatch, 1.2))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), swatch)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
  if reaper.ImGui_Button(ctx, ((value == -2) and "~" or "") .. "##aswatch" .. id, 34, 20) then
    reaper.ImGui_OpenPopup(ctx, "acp_" .. id)
  end
  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_PopStyleColor(ctx, 3)
  tooltip("Animation color")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "Color: " .. anim_color_name(value))

  if reaper.ImGui_BeginPopup(ctx, "acp_" .. id) then
    small_label("ANIMATION COLOR")
    if reaper.ImGui_Button(ctx, "Pad color##acpad", 100, 0) then
      changed, new_value = true, -1
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if colored_button("Rainbow##acrain", 0xFF9500FF, 100, 0) then
      changed, new_value = true, -2
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    for k, c in ipairs(PALETTE) do
      if c.vel ~= 0 then
        if (k - 2) % 7 ~= 0 then reaper.ImGui_SameLine(ctx, 0, 4) end
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), c.hex)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(c.hex, 1.2))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF)
        if reaper.ImGui_Button(ctx, ((c.vel == value) and "x" or "") .. "##ac" .. id .. c.vel, 26, 20) then
          changed, new_value = true, c.vel
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        tooltip(c.name)
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  return changed, new_value
end

--------------------------------------------------------------------------------
-- UI: PAD BUTTON
--------------------------------------------------------------------------------

local function draw_pad_button(pad_idx, size)
  local pad = pads[pad_idx]
  local is_focus = (pad_idx == selected_pad)
  local in_sel = selection[pad_idx] == true
  local lit = pressed_pads[pad_idx] or flash_timers[pad_idx]
  local looping = pad.mode == 3 and active_until[pad_idx] ~= nil

  local bg = get_color_for_vel(pad.color_vel)
  if anim_overlay[pad.midi_note] or pad.role == 2 then
    local v = pad_led_state(pad_idx)
    bg = (v == 0) and get_color_for_vel(0) or vel_gui_color(v)
  end
  local imgui_bg = lit and 0xFFFFFFFF or bg
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), imgui_bg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(imgui_bg, 1.25))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF)
  local n_col, n_var = 4, 1
  if in_sel or looping then
    local border = is_focus and 0xFF9500FF or (in_sel and 0x32ADE6FF or 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), border)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), is_focus and 2.5 or 2.0)
    n_col, n_var = 5, 2
  end
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
  local text_color = (pad.color_vel == 0) and 0x8E8E93FF or (lit and 0x000000FF or 0xFFFFFFFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)

  local display_label = pad.label
  if #display_label > 10 then display_label = display_label:sub(1, 9) .. ".." end
  local mark = looping and "~ " or ((pad.sample_path ~= "") and "+ " or "")
  if pad.role == 2 then mark = "[M] " elseif pad.role == 3 then mark = "[X] " end
  local btn_label = string.format("%s%s\n#%d", mark, display_label, pad_local(pad_idx))
  reaper.ImGui_Button(ctx, btn_label .. "##pad" .. pad_idx, size, size)

  reaper.ImGui_PopStyleColor(ctx, n_col)
  reaper.ImGui_PopStyleVar(ctx, n_var)

  local activated = reaper.ImGui_IsItemActivated(ctx)
  local deactivated = reaper.ImGui_IsItemDeactivated(ctx)

  if activated then
    local shift, ctrl = key_mods()
    if shift then
      select_range(sel_anchor, pad_idx)
    elseif ctrl then
      toggle_select(pad_idx)
    else
      if in_sel and sel_count() > 1 then
        selected_pad = pad_idx
        pending_collapse = pad_idx  -- collapse on release unless this becomes a drag
      else
        select_single(pad_idx)
      end
      ui_held[pad_idx] = true
      trigger_pad_on(pad_idx)
    end
  end

  local right_clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right())

  -- Drag to move (a multi-selection moves as a block)
  if reaper.ImGui_IsMouseDragging(ctx, reaper.ImGui_MouseButton_Left(), 14)
    and reaper.ImGui_BeginDragDropSource(ctx) then
    pending_collapse = nil
    reaper.ImGui_SetDragDropPayload(ctx, "LT_PAD", tostring(pad_idx))
    local n = (selection[pad_idx] and sel_count() > 1) and sel_count() or 1
    reaper.ImGui_Text(ctx, n > 1 and string.format("Move %d pads", n) or ("Move " .. pad.label))
    reaper.ImGui_EndDragDropSource(ctx)
  end

  if reaper.ImGui_BeginDragDropTarget(ctx) then
    local rv_p, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "LT_PAD")
    if rv_p and payload then move_pads(tonumber(payload), pad_idx) end
    local rv, count = reaper.ImGui_AcceptDragDropPayloadFiles(ctx)
    if rv and count and count > 0 then
      local rv_file, file_path = reaper.ImGui_GetDragDropPayloadFile(ctx, 0)
      if rv_file and file_path and file_path ~= "" then
        load_sample_to_rs5k(pad_idx, file_path)
        select_single(pad_idx)
        trigger_pad_on(pad_idx)
      end
    end
    reaper.ImGui_EndDragDropTarget(ctx)
  end

  if deactivated then
    if ui_held[pad_idx] then
      ui_held[pad_idx] = nil
      if pad.role == 1 and (pad.mode == 1 or (pad.mode == 3 and not pad.loop_toggle)) then trigger_pad_off(pad_idx) end
    end
    if pending_collapse == pad_idx then select_single(pad_idx) end
    pending_collapse = nil
  end

  if right_clicked then
    if not selection[pad_idx] then select_single(pad_idx) else selected_pad = pad_idx end
    reaper.ImGui_OpenPopup(ctx, "pad_context_" .. pad_idx)
  end

  if reaper.ImGui_BeginPopup(ctx, "pad_context_" .. pad_idx) then
    if reaper.ImGui_MenuItem(ctx, "Send current range to this pad") then
      select_single(pad_idx)
      send_range_to_selected_pad()
    end
    if reaper.ImGui_MenuItem(ctx, "Load audio file...") then
      local rv, file = reaper.GetUserFileNameForRead("", "Load Audio Sample", "*.wav;*.aif;*.aiff;*.mp3;*.flac")
      if rv then load_sample_to_rs5k(pad_idx, file) send_pad_color(pad_idx) end
    end
    local n = sel_count()
    if reaper.ImGui_MenuItem(ctx, n > 1 and string.format("Delete %d selected pads", n) or "Delete chop from pad") then
      delete_selection()
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

--------------------------------------------------------------------------------
-- UI: INSPECTOR
--------------------------------------------------------------------------------

local function draw_inspector()
  local pad = pads[selected_pad]
  if not pad then return end
  local targets = sel_list()
  local multi = #targets > 1

  reaper.ImGui_PushFont(ctx, font_main, 16)
  if multi then
    reaper.ImGui_TextColored(ctx, 0xFF9500FF, string.format("%d PADS SELECTED", #targets))
  else
    reaper.ImGui_TextColored(ctx, 0xFF9500FF, string.format("PAD #%d", pad_local(selected_pad)))
  end
  reaper.ImGui_PopFont(ctx)
  if multi then
    small_label("Edits apply to every selected pad")
  else
    small_label(string.format("Page %d  -  row %d, col %d", pad.page, pad.row + 1, pad.col + 1))
  end

  reaper.ImGui_Spacing(ctx)
  local changed, new_vel = color_picker("insp", pad.color_vel, "Color")
  if changed then
    for _, i in ipairs(targets) do
      pads[i].color_vel = new_vel
      send_pad_color(i)
    end
    save_state(false)
  end
  reaper.ImGui_Spacing(ctx)

  -- PAD TYPE
  small_label("PAD TYPE")
  for r = 1, #ROLE_NAMES do
    if r > 1 then reaper.ImGui_SameLine(ctx, 0, 4) end
    local active = (pad.role == r)
    if active then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5856D6FF) end
    if reaper.ImGui_Button(ctx, ROLE_NAMES[r] .. "##role" .. r, 88, 22) then
      for _, i in ipairs(targets) do set_pad_role(i, r) end
      save_state(false)
    end
    if active then reaper.ImGui_PopStyleColor(ctx) end
    if r == 1 then tooltip("Plays a chop / sample")
    elseif r == 2 then tooltip("Blinks on the DAW beat. Press it to turn REAPER's metronome on/off")
    else tooltip("Press it to stop every sound (same as STOP SOUND)") end
  end
  reaper.ImGui_Spacing(ctx)

  local open_flag = reaper.ImGui_TreeNodeFlags_DefaultOpen()

  if pad.role == 2 then
    reaper.ImGui_TextWrapped(ctx, "Blinks on the beat (white = bar start while playing). Press = metronome on / off.")
    reaper.ImGui_TextColored(ctx, metro.on and 0x34C759FF or 0x8E8E93FF,
      metro.on and "REAPER metronome: ON" or "REAPER metronome: OFF")
  elseif pad.role == 3 then
    reaper.ImGui_TextWrapped(ctx, "Press = stop every sound (fade out), same as the STOP SOUND button.")
  end

  if pad.role == 1 then
  if colored_button(string.format("GRAB range -> pad #%d", pad_local(selected_pad)), 0x34C759FF, -1, 30) then
    send_range_to_selected_pad()
  end

  -- SAMPLE
  if reaper.ImGui_CollapsingHeader(ctx, "Sample##hdr_sample", nil, open_flag) then
    if multi then
      small_label("Select a single pad to edit its label and slice")
    else
      local rv_label, new_label = reaper.ImGui_InputText(ctx, "Label", pad.label)
      if rv_label then pad.label = new_label end
      if pad.sample_path ~= "" then
        reaper.ImGui_TextColored(ctx, 0x34C759FF, basename(pad.sample_path))
        tooltip(pad.sample_path)
        local rv_s, new_s = reaper.ImGui_SliderDouble(ctx, "Start", pad.start_offs or 0.0, 0.0, 1.0, "%.3f")
        if rv_s then
          pad.start_offs = min(new_s, (pad.end_offs or 1.0) - 0.0001)
          pad_fx_set(selected_pad, "START_OFFS", pad.start_offs)
        end
        local rv_e, new_e = reaper.ImGui_SliderDouble(ctx, "End", pad.end_offs or 1.0, 0.0, 1.0, "%.3f")
        if rv_e then
          pad.end_offs = max(new_e, (pad.start_offs or 0.0) + 0.0001)
          pad_fx_set(selected_pad, "END_OFFS", pad.end_offs)
        end
      else
        reaper.ImGui_TextColored(ctx, 0x636366FF, "No sample loaded")
      end
      if reaper.ImGui_Button(ctx, "Load audio file...", -1, 22) then
        local rv, file = reaper.GetUserFileNameForRead("", "Load Audio Sample", "*.wav;*.aif;*.aiff;*.mp3;*.flac")
        if rv then load_sample_to_rs5k(selected_pad, file) send_pad_color(selected_pad) end
      end
    end
  end

  -- PLAYBACK
  if reaper.ImGui_CollapsingHeader(ctx, "Playback##hdr_play", nil, open_flag) then
    for m = 1, #MODES do
      if m > 1 then reaper.ImGui_SameLine(ctx) end
      local active = (pad.mode == m)
      if active then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9500FF) end
      if reaper.ImGui_Button(ctx, MODES[m] .. "##mode" .. m, 82, 24) then
        for _, i in ipairs(targets) do set_pad_mode(i, m) end
      end
      if active then reaper.ImGui_PopStyleColor(ctx) end
      if m == 1 then tooltip("Gate: plays while held")
      elseif m == 2 then tooltip("One-Shot: plays the whole chop")
      else tooltip("Loop: repeats the chop") end
    end
    if pad.mode == 3 then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x2A2C38FF)
      if reaper.ImGui_BeginChild(ctx, "loop_box", -1, 48, child_border_flag()) then
        small_label("LOOP BEHAVIOUR")
        local hold = not pad.loop_toggle
        if hold then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5856D6FF) end
        if reaper.ImGui_Button(ctx, "Hold##loophold", 110, 0) then
          for _, i in ipairs(targets) do set_pad_mode(i, 3, false) end
        end
        if hold then reaper.ImGui_PopStyleColor(ctx) end
        tooltip("Loops while the pad is held")
        reaper.ImGui_SameLine(ctx)
        if not hold then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5856D6FF) end
        if reaper.ImGui_Button(ctx, "Toggle##looptoggle", 110, 0) then
          for _, i in ipairs(targets) do set_pad_mode(i, 3, true) end
        end
        if not hold then reaper.ImGui_PopStyleColor(ctx) end
        tooltip("Press to start, press again to stop")
        reaper.ImGui_EndChild(ctx)
      end
      reaper.ImGui_PopStyleColor(ctx)
    end
  end

  -- SOUND
  if reaper.ImGui_CollapsingHeader(ctx, "Sound##hdr_sound", nil, open_flag) then
    local vol_pct = floor((pad.volume or 1.0) * 100 + 0.5)
    local rv_vol, new_vol = reaper.ImGui_SliderInt(ctx, "Volume", vol_pct, 0, 100, "%d%%")
    if rv_vol then
      for _, i in ipairs(targets) do
        pads[i].volume = new_vol / 100
        update_rs5k_volume(i)
      end
    end
    tooltip("100% = 0.0 dB (original level)")

    local semi = floor((pad.pitch_semitones or 0) + 0.5)
    local rv_pitch, new_pitch = reaper.ImGui_SliderInt(ctx, "Pitch", semi, -12, 12, "%+d st")
    if rv_pitch then
      for _, i in ipairs(targets) do
        pads[i].pitch_semitones = new_pitch
        pad_fx_set(i, "PITCH", pitch_to_norm(new_pitch))
      end
    end

    local rv_ch, new_ch = reaper.ImGui_SliderInt(ctx, "Choke", pad.choke_group or 0, 0, 4)
    if rv_ch then
      for _, i in ipairs(targets) do pads[i].choke_group = new_ch end
    end
    tooltip("0 = polyphonic. 1-4: a hit fades out the other pads of the same group")

    local rv_vel, new_vel_s = reaper.ImGui_Checkbox(ctx, "Velocity sensitive", pad.velocity_sensitive or false)
    if rv_vel then
      for _, i in ipairs(targets) do
        pads[i].velocity_sensitive = new_vel_s
        pad_fx_set(i, "MIN_VOL", new_vel_s and 0.0 or 1.0)
      end
    end
  end
  end -- sample pad sections

  -- ANIMATION (per pad)
  if reaper.ImGui_CollapsingHeader(ctx, "Animation##hdr_anim", nil, open_flag) then
    for k, name in ipairs(ANIM_NAMES) do
      if k > 1 then reaper.ImGui_SameLine(ctx, 0, 3) end
      local sel = (pad.anim_type == k)
      if sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9500FF) end
      if reaper.ImGui_Button(ctx, name .. "##at" .. k, 52, 22) then
        for _, i in ipairs(targets) do pads[i].anim_type = k end
        start_anim(selected_pad)
      end
      if sel then reaper.ImGui_PopStyleColor(ctx) end
    end
    tooltip("Off: no light  |  Flash: the pad blinks  |  Ripple / Cross / Sparkle: light spreads over the Launchpad")
    local rv_ac, new_ac = anim_color_picker("insp", pad.anim_color, pad.color_vel)
    if rv_ac then
      for _, i in ipairs(targets) do pads[i].anim_color = new_ac end
      start_anim(selected_pad)
    end
    for k, name in ipairs({ "Slow", "Normal", "Fast" }) do
      if k > 1 then reaper.ImGui_SameLine(ctx, 0, 3) end
      local sel = (pad.anim_speed == k)
      if sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9500FF) end
      if reaper.ImGui_Button(ctx, name .. "##as" .. k, 62, 0) then
        for _, i in ipairs(targets) do pads[i].anim_speed = k end
        start_anim(selected_pad)
      end
      if sel then reaper.ImGui_PopStyleColor(ctx) end
    end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "Preview##anprev", -1, 0) then
      flash_pad(selected_pad)
      start_anim(selected_pad)
    end
    tooltip("Shows the animation on the Launchpad without playing the sound")
  end

  reaper.ImGui_Spacing(ctx)
  local test_color = get_color_for_vel(pad.color_vel)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), test_color)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), brighten_color(test_color, 1.25))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF)
  reaper.ImGui_Button(ctx, (pad.role == 1) and "PLAY PAD" or "PRESS PAD", -1, 30)
  if reaper.ImGui_IsItemActivated(ctx) then trigger_pad_on(selected_pad) end
  if reaper.ImGui_IsItemDeactivated(ctx) and pad.role == 1
    and (pad.mode == 1 or (pad.mode == 3 and not pad.loop_toggle)) then
    trigger_pad_off(selected_pad)
  end
  reaper.ImGui_PopStyleColor(ctx, 3)

  reaper.ImGui_Spacing(ctx)
  if colored_button(multi and string.format("Delete %d pads", #targets) or "Reset pad", 0x3A2020FF, -1, 24) then
    delete_selection()
  end
  tooltip("Deletes the chop audio and resets the pad(s)  [Delete key]")
end

--------------------------------------------------------------------------------
-- UI: SETTINGS (gear)
--------------------------------------------------------------------------------

local function draw_settings_popup()
  if not reaper.ImGui_BeginPopup(ctx, "settings_popup") then return end
  reaper.ImGui_PushFont(ctx, font_main, 15)
  reaper.ImGui_TextColored(ctx, 0xFF9500FF, "SETTINGS")
  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_Separator(ctx)

  local open_flag = reaper.ImGui_TreeNodeFlags_DefaultOpen()

  if reaper.ImGui_CollapsingHeader(ctx, "Launchpad / MIDI##set_midi", nil, open_flag) then
    if midi_connected then
      reaper.ImGui_TextColored(ctx, 0x34C759FF, "Connected: " .. midi_out_name)
    else
      reaper.ImGui_TextColored(ctx, 0xFF9500FF, "No Launchpad found (retrying every 3 s)")
    end
    if midi_disabled_hint then
      reaper.ImGui_TextColored(ctx, 0xFF3B30FF, "A Launchpad port is disabled in REAPER:")
      reaper.ImGui_TextColored(ctx, 0xFF3B30FF, "Preferences > MIDI Devices > enable input + output")
    end
    reaper.ImGui_TextColored(ctx, router_ok() and 0x34C759FF or 0xFF3B30FF,
      router_ok() and "Router JSFX: OK" or "Router JSFX: missing (slow fallback)")

    reaper.ImGui_SetNextItemWidth(ctx, 230)
    if reaper.ImGui_BeginCombo(ctx, "Output (LEDs)", midi_out_name ~= "" and midi_out_name or "-") then
      for _, dev in ipairs(available_midi_outs) do
        local label = dev.name .. (dev.enabled and "" or "  [disabled]")
        if reaper.ImGui_Selectable(ctx, label .. "##o" .. dev.id, dev.id == midi_out_device) then
          midi_out_device, midi_out_name = dev.id, dev.name
          midi_connected = true
          set_launchpad_programmer_mode(midi_out_device)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SetNextItemWidth(ctx, 230)
    if reaper.ImGui_BeginCombo(ctx, "Input (pads)", midi_in_name ~= "" and midi_in_name or "-") then
      for _, dev in ipairs(available_midi_ins) do
        local label = dev.name .. (dev.enabled and "" or "  [disabled]")
        if reaper.ImGui_Selectable(ctx, label .. "##i" .. dev.id, dev.id == midi_in_device) then
          midi_in_device, midi_in_name = dev.id, dev.name
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    if reaper.ImGui_Button(ctx, "Auto-detect") then find_launchpad_devices(false) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Reset MIDI devices") then reset_midi_devices() end
    tooltip("Runs REAPER's 'Reset all MIDI devices' (use after plugging the Launchpad in)")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "MIDI prefs") then open_midi_prefs() end

    if reaper.ImGui_Button(ctx, "Programmer mode") then
      set_launchpad_programmer_mode(midi_out_device)
      set_status("Sent Programmer Mode SysEx to the Launchpad", 0x34C759FF)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Sync LEDs") then
      led_cache, cc_cache = {}, {}
      send_all_pad_colors(true)
    end
    local rv_ar, new_ar = reaper.ImGui_Checkbox(ctx, "Reset MIDI devices automatically if no Launchpad", auto_reset_midi)
    if rv_ar then auto_reset_midi = new_ar end
  end

  if reaper.ImGui_CollapsingHeader(ctx, "Layout##set_layout", nil, open_flag) then
    local cur_name = string.format("%dx%d", grid_rows, grid_cols)
    for _, g in ipairs(GRID_PRESETS) do
      if g.rows == grid_rows and g.cols == grid_cols then cur_name = g.name end
    end
    reaper.ImGui_SetNextItemWidth(ctx, 160)
    if reaper.ImGui_BeginCombo(ctx, "Pads on the Launchpad", cur_name) then
      for _, g in ipairs(GRID_PRESETS) do
        if reaper.ImGui_Selectable(ctx, g.name, g.rows == grid_rows and g.cols == grid_cols) then
          set_grid(g.rows, g.cols)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    tooltip("Pads outside the area keep their content, they are just hidden")
    small_label("8 pages: Launchpad arrows or the right-side buttons change page")
  end

  if reaper.ImGui_CollapsingHeader(ctx, "Chop##set_chop", nil, open_flag) then
    reaper.ImGui_SetNextItemWidth(ctx, 160)
    local rv_fd, new_fd = reaper.ImGui_SliderInt(ctx, "Micro-fade", fade_ms, 0, 20, "%d ms")
    if rv_fd then
      fade_ms = new_fd
      apply_fade_to_all()
    end
    tooltip("RS5K attack + release on every pad: removes clicks. 0 = off")
    local rv_ck, new_ck = reaper.ImGui_Checkbox(ctx, "Choke new chops (group 1)", chop_choke)
    if rv_ck then chop_choke = new_ck end
    local rv_adv, new_adv = reaper.ImGui_Checkbox(ctx, "Auto-advance after Send", auto_advance)
    if rv_adv then auto_advance = new_adv end
    local rv_am, new_am = reaper.ImGui_Checkbox(ctx, "Auto-mute source after capture", auto_mute_source_track)
    if rv_am then auto_mute_source_track = new_am end
  end

  if reaper.ImGui_CollapsingHeader(ctx, "Engine##set_engine") then
    reaper.ImGui_TextWrapped(ctx, "The engine keeps running when this window is closed (hardware, LEDs and pages keep working). Run the script again to reopen the window. Delete the 'LT Chops' track to stop it.")
  end

  reaper.ImGui_EndPopup(ctx)
end

--------------------------------------------------------------------------------
-- UI: TOP BAR / CHOP BAR / GRID / FOOTER
--------------------------------------------------------------------------------

local kit_name_buf = nil

local function draw_top_bar()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1B22FF)
  if reaper.ImGui_BeginChild(ctx, "topbar", -1, 40, child_border_flag()) then
    reaper.ImGui_PushFont(ctx, font_main, 15)
    reaper.ImGui_TextColored(ctx, 0xFF9500FF, "Little Things")
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SameLine(ctx, 0, 16)

    -- Kit combo (load)
    reaper.ImGui_SetNextItemWidth(ctx, 170)
    if reaper.ImGui_BeginCombo(ctx, "##kitcombo", "KIT: " .. current_kit_name) then
      local kits = list_kits()
      if #kits == 0 then reaper.ImGui_TextColored(ctx, 0x8E8E93FF, "No saved kits yet") end
      for k, kit in ipairs(kits) do
        if reaper.ImGui_Selectable(ctx, kit.name .. "##kit" .. k, kit.name == current_kit_name) then
          load_kit(kit.path)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Kit...") then
      kit_name_buf = current_kit_name
      reaper.ImGui_OpenPopup(ctx, "kit_popup")
    end
    tooltip("Save / export / import kits (audio included)")
    if reaper.ImGui_BeginPopup(ctx, "kit_popup") then
      small_label("KIT")
      reaper.ImGui_SetNextItemWidth(ctx, 220)
      local rv_n, new_n = reaper.ImGui_InputText(ctx, "##kitname", kit_name_buf or current_kit_name)
      if rv_n then kit_name_buf = new_n end
      local name = (kit_name_buf and kit_name_buf ~= "") and kit_name_buf or current_kit_name
      if colored_button("Save", 0x007AFFFF, 70) then
        save_kit(name)
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      tooltip("Saves the kit with copies of its sounds in the kits folder")
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Export...", 70) then
        export_kit(name)
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      tooltip("Creates a folder (kit + samples) you can open on another computer")
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Import...", 70) then
        reaper.ImGui_CloseCurrentPopup(ctx)
        import_kit()
      end
      tooltip("Opens a .ltkit file (its samples are copied into this project)")
      if reaper.ImGui_Button(ctx, "Open kits folder", -1) then open_url(get_kits_dir()) end
      reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx, 0, 14)
    reaper.ImGui_SetNextItemWidth(ctx, 80)
    local rv_mv, new_mv = reaper.ImGui_SliderInt(ctx, "Vol##master", floor(master_volume * 100 + 0.5), 0, 100, "%d%%")
    if rv_mv then
      master_volume = new_mv / 100
      for i = 1, NUM_PADS do
        if pads[i].sample_path ~= "" then update_rs5k_volume(i) end
      end
    end

    reaper.ImGui_SameLine(ctx, 0, 12)
    local soloed = track_valid(rs5k_track) and reaper.GetMediaTrackInfo_Value(rs5k_track, "I_SOLO") > 0.5
    if colored_button(soloed and "SOLO ON##solo" or "SOLO CHOPS##solo", soloed and 0xFF9500FF or 0x333644FF) then
      solo_lt_chops_track()
    end
    tooltip("Solos the LT Chops track")
    reaper.ImGui_SameLine(ctx)
    if colored_button("STOP SOUND", 0xFF2D55FF) then stop_all_sounds() end

    -- Right side: Launchpad status dot + gear
    local win_w = reaper.ImGui_GetWindowWidth(ctx)
    reaper.ImGui_SameLine(ctx, win_w - 150)
    reaper.ImGui_TextColored(ctx, midi_connected and 0x34C759FF or 0xFF9500FF, midi_connected and "Launchpad" or "No Launchpad")
    tooltip(midi_connected and midi_out_name or "Open settings (gear) to configure")
    reaper.ImGui_SameLine(ctx, win_w - 34)
    if gear_button("##gear", 20) then
      refresh_midi_device_lists()
      reaper.ImGui_OpenPopup(ctx, "settings_popup")
    end
    tooltip("Settings")
    draw_settings_popup()

    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_PopStyleColor(ctx)
end

local function draw_chop_bar()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1E202BFF)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
  if reaper.ImGui_BeginChild(ctx, "chop_bar", -1, 68, child_border_flag()) then
    local text, col = get_timeline_display_text()
    reaper.ImGui_PushFont(ctx, font_main, 11)
    reaper.ImGui_TextColored(ctx, col, text)
    reaper.ImGui_PopFont(ctx)

    reaper.ImGui_PushFont(ctx, font_main, 13)
    if colored_button(string.format("SEND RANGE -> PAD #%d", pad_local(selected_pad)), 0x34C759FF, 200, 28) then
      send_range_to_selected_pad()
    end
    tooltip("Captures the range into the selected pad, plays it and clears the time selection")

    reaper.ImGui_SameLine(ctx, 0, 12)
    if colored_button(string.format("CHOP x%d", chop_division), 0xFF9500FF, 100, 28) then
      chop_range_into_n_pads(chop_division)
    end
    tooltip("Slices the range evenly into pads starting at the first pad of this page")
    reaper.ImGui_SameLine(ctx, 0, 4)
    for _, div in ipairs({ 8, 16, 32, 64 }) do
      local sel = (chop_division == div)
      if sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9500FF) end
      if reaper.ImGui_Button(ctx, tostring(div) .. "##div" .. div, 30, 28) then chop_division = div end
      if sel then reaper.ImGui_PopStyleColor(ctx) end
      reaper.ImGui_SameLine(ctx, 0, 3)
    end

    reaper.ImGui_SameLine(ctx, 0, 12)
    if colored_button("ITEMS -> PADS", 0x5856D6FF, 120, 28) then items_to_pads() end
    tooltip("Every audio item of the source track, in timeline order, into pads from the selected one")

    reaper.ImGui_SameLine(ctx, 0, 12)
    if colored_button("Delete track sound, 0x501010FF, 160, 28) then
      silence_selected_range_on_source_track()
    end
    tooltip("Splits and deletes the audio of the selected range on the source track")

    reaper.ImGui_SameLine(ctx, 0, 12)
    if colored_button("Clear all", 0x333644FF, 80, 28) then clear_all_pads() end
    reaper.ImGui_PopFont(ctx)

    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_PopStyleVar(ctx)
  reaper.ImGui_PopStyleColor(ctx)
end

local function draw_grid_panel(w, h)
  if not reaper.ImGui_BeginChild(ctx, "grid_panel", w, h, child_border_flag()) then return end

  -- Page navigation: < 1 2 3 4 5 6 7 8 >  (blue = page has sounds, orange = current)
  if reaper.ImGui_Button(ctx, "<##pgprev", 22, 0) then set_page(current_page - 1) end
  for p = 1, MAX_PAGES do
    reaper.ImGui_SameLine(ctx, 0, 3)
    local col = (p == current_page) and 0xFF9500FF or (page_has_content(p) and 0x1B58F4FF or 0x2A2C38FF)
    if colored_button(tostring(p) .. "##pg" .. p, col, 24, 0) then set_page(p) end
    tooltip(string.format("Page %d%s", p, page_has_content(p) and "" or " (empty)"))
  end
  reaper.ImGui_SameLine(ctx, 0, 3)
  if reaper.ImGui_Button(ctx, ">##pgnext", 22, 0) then set_page(current_page + 1) end
  reaper.ImGui_SameLine(ctx, 0, 14)
  local n = sel_count()
  small_label(n > 1 and string.format("%d selected  -  drag to move, Del to clear", n)
    or "Click = play  |  Shift/Ctrl = select  |  Drag = move")

  reaper.ImGui_Spacing(ctx)

  local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local spacing = 5
  local size_w = (avail_w - spacing * (grid_cols - 1)) / grid_cols
  local size_h = (avail_h - 26 - spacing * (grid_rows - 1)) / grid_rows
  local pad_size = clamp(floor(min(size_w, size_h)), 36, 96)

  for r = 0, grid_rows - 1 do
    for c = 0, grid_cols - 1 do
      if c > 0 then reaper.ImGui_SameLine(ctx, 0, spacing) end
      draw_pad_button(page_pad(current_page, r * HW_COLS + c + 1), pad_size)
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_PushFont(ctx, font_main, 11)
  reaper.ImGui_TextColored(ctx, status_color_hex, status_msg)
  reaper.ImGui_PopFont(ctx)

  reaper.ImGui_EndChild(ctx)
end

local function draw_credits()
  reaper.ImGui_PushFont(ctx, font_main, 11)
  reaper.ImGui_TextColored(ctx, 0x636366FF, "Little Things v" .. SCRIPT_VERSION .. "  -  made by")
  for i, c in ipairs(CREDITS) do
    reaper.ImGui_SameLine(ctx, 0, (i == 1) and 8 or 14)
    local label = c.name .. " @" .. c.handle
    if reaper.ImGui_TextLinkOpenURL then
      reaper.ImGui_TextLinkOpenURL(ctx, label .. "##credit" .. i, c.url)
    else
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9500FF)
      if reaper.ImGui_SmallButton(ctx, label .. "##credit" .. i) then open_url(c.url) end
      reaper.ImGui_PopStyleColor(ctx, 2)
    end
    tooltip("Instagram: " .. c.url)
  end
  reaper.ImGui_PopFont(ctx)
end

local function handle_shortcuts()
  if not reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows()) then return end
  if reaper.ImGui_IsAnyItemActive(ctx) then return end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then
    delete_selection()
  end
  local _, ctrl = key_mods()
  if ctrl and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_A()) then select_all_visible() end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageUp()) then set_page(current_page - 1) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageDown()) then set_page(current_page + 1) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then select_single(selected_pad) end
end

local function draw_dormant()
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextColored(ctx, 0xFF9500FF, "This project has no '" .. TRACK_NAME .. "' track.")
  reaper.ImGui_Text(ctx, "The engine is waiting. Switch back to a project that has one, or:")
  reaper.ImGui_Spacing(ctx)
  if colored_button("Create LT Chops in this project", 0x34C759FF, 260, 30) then
    engine_active = true
    adopt_pending = false
    ensure_rs5k_track_ready(true)
    led_cache, cc_cache = {}, {}
    schedule_led_sync(0.1)
  end
end

local function draw_ui()
  if not ctx then
    if not init_imgui() then
      ui_visible = false
      return
    end
  end

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x121316FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), 0x18191EFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), 0x22242DFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x22242DFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), 0xFF9500FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xFF9500FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x1A1B22FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), 0x2E303CFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x2A2C38FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x3A3D4DFF)
  reaper.ImGui_PushFont(ctx, font_main, 13)

  reaper.ImGui_SetNextWindowBgAlpha(ctx, 1.0)
  reaper.ImGui_SetNextWindowSize(ctx, 1060, 760, reaper.ImGui_Cond_FirstUseEver())
  if focus_request then
    reaper.ImGui_SetNextWindowFocus(ctx)
    focus_request = false
  end

  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_NAME .. "  v" .. SCRIPT_VERSION .. "###LTChopEngineV2", true, reaper.ImGui_WindowFlags_NoCollapse())
  if visible then
    if not engine_active then
      draw_dormant()
    else
      draw_top_bar()
      reaper.ImGui_Spacing(ctx)
      draw_chop_bar()
      reaper.ImGui_Spacing(ctx)

      local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
      local footer_h = 24
      local panel_h = max(200, avail_h - footer_h)
      local inspector_w = 300
      local grid_w = avail_w - inspector_w - 12

      draw_grid_panel(grid_w, panel_h)
      reaper.ImGui_SameLine(ctx, 0, 12)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1B22FF)
      if reaper.ImGui_BeginChild(ctx, "inspector", inspector_w, panel_h, child_border_flag()) then
        draw_inspector()
        reaper.ImGui_EndChild(ctx)
      end
      reaper.ImGui_PopStyleColor(ctx)
      handle_shortcuts()
    end
    draw_credits()
    reaper.ImGui_End(ctx)
  end

  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PopStyleColor(ctx, 10)

  if not open then
    -- window closed: the engine keeps running, the ImGui context is released
    ui_visible = false
    ctx, font_main = nil, nil
  end
end

--------------------------------------------------------------------------------
-- ENGINE LIFECYCLE (background mode, project switching, track deletion)
--------------------------------------------------------------------------------

-- Another (newer) engine claimed the Launchpad: stop silently, without touching LEDs,
-- sounds or the saved state (they belong to the new owner now).
local function retire()
  shut_down = true
  ui_visible = false
  ctx, font_main = nil, nil
end

local function lost_ownership()
  local owner = reaper.GetExtState(EXT_SECTION, "owner")
  return owner ~= "" and owner ~= instance_id
end

local function heartbeat_tick()
  local now = reaper.time_precise()
  if now >= next_heartbeat then
    next_heartbeat = now + HEARTBEAT_INTERVAL
    reaper.SetExtState(EXT_SECTION, "heartbeat", string.format("%.3f", now), false)
  end
  if reaper.GetExtState(EXT_SECTION, "show_ui") == "1" then
    reaper.DeleteExtState(EXT_SECTION, "show_ui", false)
    ui_visible = imgui_available
    focus_request = true
  end
end

local function shutdown(track_deleted)
  if shut_down then return end
  if lost_ownership() then
    retire()
    return
  end
  if track_deleted then
    if proj_valid(cur_proj) then reaper.SetProjExtState(cur_proj, EXT_SECTION, "", "") end
  else
    save_state(true)
  end
  shut_down = true
  if engine_active and not track_deleted and track_valid(rs5k_track) then stop_all_sounds(true) end
  clear_all_leds()
  reaper.DeleteExtState(EXT_SECTION, "heartbeat", false)
  reaper.DeleteExtState(EXT_SECTION, "owner", false)
  if reaper.set_action_options then reaper.set_action_options(8) end
end

local function switch_project(proj)
  if engine_active then save_state(true) end
  clear_all_leds()
  cur_proj = proj
  reset_track_refs()
  active_until, pressed_pads, flash_timers, choke_pending, hw_note_pad = {}, {}, {}, {}, {}
  init_pads()
  current_page = 1
  select_single(1)
  local restored = load_state()
  local tr = find_rs5k_track()
  if tr then
    rs5k_track = tr
    engine_active = true
    adopt_pending = not restored
    ensure_rs5k_track_ready(true)
    led_cache, cc_cache = {}, {}
    schedule_led_sync(0.1)
    set_status("Project switched - LT Chops loaded", 0x32ADE6FF)
  else
    engine_active = false
  end
end

local function engine_tick()
  if lost_ownership() then
    retire()
    return
  end
  local proj = reaper.EnumProjects(-1)
  if proj ~= cur_proj then switch_project(proj) end

  if engine_active and not track_valid(rs5k_track) then
    local tr = find_rs5k_track()
    if tr then
      reset_track_refs()
      rs5k_track = tr
      ensure_rs5k_track_ready(true)
    else
      shutdown(true)   -- the LT Chops track was deleted: the engine stops
      return
    end
  end

  if engine_active then
    update_flash_timers()
    update_choke_pending()
    poll_hardware_midi_input()
    update_special_leds()
    update_animations()
    led_refresh_tick()

    local now = reaper.time_precise()
    if pending_led_sync and now >= pending_led_sync then
      pending_led_sync = nil
      led_cache, cc_cache = {}, {}
      send_all_pad_colors(true)
    end
    if router_flags_dirty or now >= next_router_resync then
      next_router_resync = now + ROUTER_RESYNC_INTERVAL
      router_push_params()
    end
    persist_tick()
  end

  midi_autoconnect_tick()
  heartbeat_tick()
end

local function main_loop()
  if shut_down then return end
  engine_tick()
  if shut_down then return end
  if ui_visible then draw_ui() end
  reaper.defer(main_loop)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function another_instance_running()
  local hb = tonumber(reaper.GetExtState(EXT_SECTION, "heartbeat") or "")
  return hb ~= nil and (reaper.time_precise() - hb) < 1.5
end

local function start_engine()
  reaper.DeleteExtState(EXT_SECTION, "show_ui", false)
  math.randomseed(floor(reaper.time_precise() * 1000) % 2147483647)
  instance_id = string.format("%d-%d", os.time(), math.random(1, 999999999))
  reaper.SetExtState(EXT_SECTION, "owner", instance_id, false)
  -- Re-running the action (shortcut / toolbar / action list) while the engine runs:
  --   1 = REAPER ends this instance (atexit saves everything)
  --   2 = ...and runs the script again, which opens the window with the saved state
  --   4 = toolbar button lit while the engine runs
  -- (flag 2 on its own means "ignore the re-launch", which is why v2.0 never reopened)
  if reaper.set_action_options then reaper.set_action_options(1 | 2 | 4) end

  imgui_available = reaper.ImGui_CreateContext ~= nil
  if not imgui_available then
    reaper.ShowMessageBox("This script requires the ReaImGui extension.\n\nInstall it via ReaPack and restart REAPER.",
      "Little Things - Missing Dependency", 0)
    return
  end

  init_pads()
  select_single(1)
  load_settings()
  cur_proj = reaper.EnumProjects(-1)
  local restored = load_state()
  adopt_pending = not restored
  engine_active = true

  find_launchpad_devices(true)
  next_midi_scan = reaper.time_precise() + 3.0
  if not midi_connected and auto_reset_midi then
    midi_reset_done = true
    reset_midi_devices()
  end

  ensure_rs5k_track_ready(true)
  apply_fade_to_all()

  if reaper.MIDI_GetRecentInputEvent then
    last_midi_seq = reaper.MIDI_GetRecentInputEvent(0) or 0
  end

  save_state(not restored)
  schedule_led_sync(0.4)
  heartbeat_tick()

  reaper.atexit(function() shutdown(false) end)
  reaper.defer(main_loop)
end

local function init()
  if not another_instance_running() then
    start_engine()
    return
  end
  -- An engine is still alive (older REAPER that asked "new instance", or the previous instance
  -- has not finished closing yet). Ask it to show its window; if it disappears instead, start.
  reaper.SetExtState(EXT_SECTION, "show_ui", "1", false)
  local give_up = reaper.time_precise() + 3.0
  local function wait_for_engine()
    if reaper.GetExtState(EXT_SECTION, "show_ui") ~= "1" then return end -- window reopened
    if not another_instance_running() then
      start_engine()
      return
    end
    if reaper.time_precise() < give_up then reaper.defer(wait_for_engine) end
  end
  reaper.defer(wait_for_engine)
end

init()
end

engine_main()
