-- Universal Passive Automation. One computer per machine group.
-- Each poll: run the stocked, under-cap product with the lowest stock/weight by transmitting
-- its WR-CBE frequency on a Tier 2 Redstone Card. Nothing eligible -> transmitter off.
--   universal-passive-automation              run
--   universal-passive-automation --dry        run without transmitting
--   universal-passive-automation dump <text>  list network keys whose label contains <text>
--   universal-passive-automation test         self-check of the selection logic
local args = {...}

local function fmt(n)
  for _, u in ipairs({{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}) do
    if n >= u[1] then return (string.format("%.1f", n / u[1]):gsub("%.0$", "")) .. u[2] end
  end
  return tostring(math.floor(n))
end

-- Config amounts: plain numbers or strings like "150M", "1.5B", "20k".
local MULT = {K = 1e3, M = 1e6, B = 1e9, G = 1e9, T = 1e12}
local function num(v)
  if type(v) == "number" then return v end
  local n, u = tostring(v):upper():gsub("[%s_,]", ""):match("^([%d%.]+)([KMBGT]?)$")
  assert(n and tonumber(n), "bad amount in config: " .. tostring(v))
  return tonumber(n) * (MULT[u] or 1)
end

-- Why a product can't run: "full" (at cap) or "waiting", <missing ingredient key>. nil = can run.
local function blocked(p, stock)
  if p.cap and (stock[p.key] or 0) >= p.cap then return "full" end
  for k, min in pairs(p.need or {}) do
    if (stock[k] or 0) < min then return "waiting", k end
  end
end

-- Lowest stock/weight among products that can run.
local function pick(products, stock)
  local best, bestScore
  for _, p in ipairs(products) do
    local score = (stock[p.key] or 0) / p.weight
    if not blocked(p, stock) and (not bestScore or score < bestScore) then best, bestScore = p, score end
  end
  return best
end

-- Bar fill, 0..1. Capped: stock / cap. Uncapped: its stock/weight vs the average stock/weight of
-- every other product, so balanced = full and losing half its stock = half bar.
local function fill(p, products, stock)
  if p.cap then return math.min((stock[p.key] or 0) / p.cap, 1) end
  local mine, sum, n = (stock[p.key] or 0) / p.weight, 0, 0
  for _, o in ipairs(products) do
    if o ~= p then sum, n = sum + (stock[o.key] or 0) / o.weight, n + 1 end
  end
  if n == 0 or sum == 0 then return 1 end -- nothing to compare against
  return math.min(mine / (sum / n), 1)
end

if args[1] == "test" then
  local F = {{key = "a", weight = 1}, {key = "b", weight = 10}, {key = "c", weight = 1, cap = 100}}
  assert(fill(F[1], F, {a = 50, b = 1000, c = 100}) == 0.5) -- half of the others' average (100)
  assert(fill(F[1], F, {a = 500, b = 1000, c = 100}) == 1)  -- above average -> full
  assert(fill(F[3], F, {c = 25}) == 0.25)                   -- capped -> stock / cap
  assert(fill(F[1], {F[1]}, {a = 5}) == 1)                  -- alone -> full
  local P = {{key = "a", weight = 10, need = {x = 5}}, {key = "b", weight = 1, cap = 100}, {key = "c", weight = 1}}
  assert(pick(P, {a = 50, b = 10, c = 20, x = 5}).key == "a")   -- 50/10 beats 10/1 and 20/1
  assert(pick(P, {a = 50, b = 10, c = 20, x = 4}).key == "b")   -- a missing input
  assert(pick(P, {a = 50, b = 100, c = 20, x = 4}).key == "c")  -- b at cap
  assert(pick({P[2]}, {b = 100}) == nil)                        -- nothing eligible -> off
  local why, k = blocked(P[1], {x = 4})
  assert(why == "waiting" and k == "x" and blocked(P[2], {b = 100}) == "full" and blocked(P[3], {}) == nil)
  assert(num("150M") == 150e6 and num("1.5b") == 1.5e9 and num("20k") == 2e4 and num(7) == 7 and num("42") == 42)
  assert(fmt(15e6) == "15M" and fmt(1.25e9) == "1.2B" and fmt(999) == "999")
  print("ok")
  return
end

local component = require("component")
local event = require("event")
local term = require("term")
local gpu = component.gpu

local me = component[component.isAvailable("me_controller") and "me_controller" or "me_interface"]

if args[1] == "dump" then
  local q = table.concat(args, " ", 2):lower()
  for _, f in ipairs(me.getFluidsInNetwork()) do
    if (f.label or ""):lower():find(q, 1, true) then print(f.name, f.label) end
  end
  -- allItems() streams (full list breaks on big networks) but errors if stock changes mid-scan: retry
  for _ = 1, 5 do
    local found = {}
    local ok = pcall(function()
      for s in me.allItems() do
        if s and (s.label or ""):lower():find(q, 1, true) then
          found[#found + 1] = s.name .. ":" .. math.floor(s.damage) .. "\t" .. s.label
        end
      end
    end)
    if ok then
      for _, line in ipairs(found) do print(line) end
      return
    end
  end
  print("item scan failed 5x (network too busy), try again")
  return
end

local cfg = dofile("/home/universal-passive-automation.cfg")
local rs = component.redstone
local dry = args[1] == "--dry"

-- Item keys are "name:damage" (contain a colon); fluid keys are the bare fluid name.
local items, freqs = {}, {}
local function addKey(k)
  if k:find(":") then
    local name, dmg = k:match("^(.+):(%d+)$")
    assert(name, "item key must be name:damage, got " .. k)
    items[k] = {name = name, damage = tonumber(dmg)}
  end
end
for _, p in ipairs(cfg.products) do
  assert(p.key and p.weight and p.freq, "every product needs key, weight, freq")
  assert(not freqs[p.freq], "duplicate freq " .. p.freq)
  freqs[p.freq] = true
  p.weight, p.cap = num(p.weight), p.cap and num(p.cap)
  addKey(p.key)
  for k, v in pairs(p.need or {}) do addKey(k) p.need[k] = num(v) end
end

local labels = {} -- key -> display name, remembered so products at 0 stock keep their name
local function read()
  local stock = {}
  for _, f in ipairs(me.getFluidsInNetwork()) do
    stock[f.name], labels[f.name] = f.amount, f.label
  end
  -- Direct lookup per item (GTNH OC). getItemsInNetwork(filter) never matches names: OC passes
  -- Lua strings in tables as byte arrays and the filter compares them to Java strings.
  for k, it in pairs(items) do
    local s = me.getItemInNetwork(it.name, it.damage)
    if s then stock[k], labels[k] = s.size, s.label end
  end
  return stock
end

local BAR = 20
local GREEN, RED, BLUE, GREY, YELLOW = 0x00FF00, 0xFF0000, 0x55CCFF, 0x888888, 0xFFCC00
local function put(s, color) -- write s in color, restoring the previous color
  if not color then return io.write(s) end
  local old = gpu.setForeground(color)
  io.write(s)
  gpu.setForeground(old)
end

-- prev = stock from the last poll (nil on the first), used for the up/down arrows.
local function draw(stock, prev, active)
  term.clear()
  local name = function(k) return labels[k] or k end
  put((cfg.name or "Universal Passive Automation") .. " - Now making: ", GREY)
  put((active and name(active.key) or "nothing (everything is full or waiting)") .. "\n", active and BLUE or YELLOW)
  put(string.format("Updated %s, checks every %ds%s\n", os.date("%H:%M"), cfg.poll or 60,
    dry and "  [DRY RUN: not switching machines]" or ""), GREY)
  put(string.rep("─", gpu.getResolution() - 1) .. "\n", GREY) -- -1: a full-width line would wrap

  -- amount column: stock right-aligned, cap left-aligned, so the "/" lines up
  local rows, w, wh, wc = {}, 0, 0, 0
  for i, p in ipairs(cfg.products) do
    local have = stock[p.key] or 0
    local r = {p = p, i = i, have = have, f = fill(p, cfg.products, stock),
      h = fmt(have), c = p.cap and fmt(p.cap) or ""}
    rows[i], w = r, math.max(w, #name(p.key))
    wh, wc = math.max(wh, #r.h), math.max(wc, #r.c)
  end
  for _, r in ipairs(rows) do
    r.amt = string.format("%" .. wh .. "s %s %-" .. wc .. "s", r.h, r.p.cap and "/" or " ", r.c)
  end
  local wa = #rows > 0 and #rows[1].amt or 0
  -- uncapped first (lowest bar first), then capped (lowest cap first); ties keep config order
  table.sort(rows, function(a, b)
    local ca, cb = a.p.cap, b.p.cap
    if (ca == nil) ~= (cb == nil) then return ca == nil end
    if ca and ca ~= cb then return ca < cb end
    if not ca and a.f ~= b.f then return a.f < b.f end
    return a.i < b.i
  end)

  for _, r in ipairs(rows) do
    local p, on = r.p, r.p == active
    local n = math.floor(r.f * BAR)
    put(string.format("%s %-" .. w .. "s ", on and ">" or " ", name(p.key)), on and BLUE or nil)
    put("[" .. string.rep("█", n) .. string.rep("░", BAR - n) .. "]", r.f >= 0.25 and GREEN or RED)
    io.write(string.format(" %3d%% ", math.floor(r.f * 100)))
    put(p.cap and "of target " or "vs others ", GREY)
    io.write(string.format(" %-" .. wa .. "s ", r.amt))
    local old = prev and (prev[p.key] or 0)
    if old and r.have > old then put("↑", GREEN) elseif old and r.have < old then put("↓", RED) else io.write(" ") end
    io.write("  ")
    local why, k = blocked(p, stock)
    if on then put("MAKING", BLUE)
    elseif why == "full" then put("FULL", GREEN)
    elseif why == "waiting" then put("WAITING: needs " .. name(k), YELLOW)
    else put("READY", GREY) end
    io.write("\n")
  end
end

local prev -- last poll's stock, for trend arrows
local cur -- frequency being transmitted, false = off, nil = unknown (forces a set on first poll)
repeat
  local ok, stock = pcall(read)
  if ok then
    local p = pick(cfg.products, stock)
    local want = p and p.freq or false
    if not dry and want ~= cur then
      if want then
        rs.setWirelessFrequency(want)
        rs.setWirelessOutput(true)
      else
        rs.setWirelessOutput(false)
      end
      cur = want
    end
    draw(stock, prev, p)
    prev = stock
  else
    print(os.date("%H:%M") .. " ME read failed, keeping current output: " .. tostring(stock))
  end
until event.pull(cfg.poll or 60, "interrupted")
