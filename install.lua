-- Universal Passive Automation installer. Needs an Internet Card (can be removed afterwards).
-- Paste into the OpenOS shell:
--   wget -f <BASE>install.lua /tmp/i.lua && /tmp/i.lua
-- Re-running it updates the script and keeps your existing config.
local shell = require("shell")
local fs = require("filesystem")

local BASE = "https://raw.githubusercontent.com/USER/REPO/main/" -- set to where you host these files

local function get(file, dest)
  fs.remove(dest)
  shell.execute("wget -fq " .. BASE .. file .. " " .. dest)
  assert(fs.exists(dest), "download failed: " .. BASE .. file)
  print("Installed " .. dest)
end

fs.makeDirectory("/home/bin")
get("universal-passive-automation.lua", "/home/bin/universal-passive-automation.lua")

local cfg = "/home/universal-passive-automation.cfg"
if fs.exists(cfg) then print("Kept existing " .. cfg) else get("universal-passive-automation.cfg", cfg) end

-- Autostart on boot + short "upa" command, added once.
local rc = "/home/.shrc"
local f = io.open(rc)
local txt = f and f:read("*a") or ""
if f then f:close() end
if not txt:find("universal-passive-automation", 1, true) then
  f = io.open(rc, "a")
  f:write("alias upa=universal-passive-automation\nuniversal-passive-automation\n")
  f:close()
  print("Added autostart to " .. rc)
end

print("\nNext: edit " .. cfg .. " (find keys with: upa dump <text>), then reboot.")
