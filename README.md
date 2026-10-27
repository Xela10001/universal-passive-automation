# Universal Passive Automation

OpenComputers script for GregTech: New Horizons. It keeps a group of machines (DTPFs, fusion reactors, ...) making whichever product you are lowest on, by switching a wireless redstone frequency that enables that recipe's ingredients.

## How it works

Every check (default 60 s), it reads your ME stock and picks the product with the lowest `stock / weight` that:
- is below its `cap` (or has no cap), and
- has every ingredient in `need` at or above its minimum.

It then transmits that product's frequency. If nothing qualifies, the transmitter turns off. If the ME read fails, the current signal is kept.

## Hardware (one computer per machine group)

- Computer with a **Tier 2 Redstone Card** (wireless redstone), screen, keyboard.
- **Internet Card** for installing (can be removed afterwards).
- **Adapter** touching the group's ME controller (or an ME interface).
- One WR-CBE **wireless receiver** per recipe, powering that recipe's toggle bus.

## Install

Paste into the OpenOS shell:

```
wget -f https://raw.githubusercontent.com/Xela10001/universal-passive-automation/master/install.lua /tmp/i.lua && /tmp/i.lua
```

This installs the script, an example config (only if you don't have one), autostart, and the short command `upa`. Run it again to update; your config is kept.

## Configure

Edit `/home/universal-passive-automation.cfg`, then reboot.

```lua
return {
  name = "DTPF",   -- dashboard title
  poll = 60,       -- seconds between checks
  products = {
    {key = "molten.infinity", weight = 10, cap = "150M", freq = 1001,
      need = {["plasma.example"] = "10M", ["gregtech:gt.metaitem.01:32100"] = "10k"}},
    {key = "molten.spacetime", weight = 1, freq = 1002},
  },
}
```

| Field | Meaning |
|-------|---------|
| `key` | Fluid: OC fluid name (`molten.infinity`). Item: `name:damage`. |
| `weight` | Stock ratio. Weight 10 vs 1 keeps 10x more of the first. |
| `cap` | Optional. Stop making it at this amount. No cap = always a candidate. |
| `freq` | Wireless frequency of this recipe's receiver. Must be unique. |
| `need` | Optional. Ingredient key -> minimum stock before it may run. |

Amounts accept numbers (`150e6`) or quoted strings with `K/M/B/T` (`"150M"`).

Find keys with `upa dump <text>`, e.g. `upa dump spacetime`.

## Commands

| Command | Does |
|---------|------|
| `upa` | Run (starts automatically on boot) |
| `upa --dry` | Show choices without switching machines |
| `upa dump <text>` | List fluid/item keys whose name contains `<text>` |
| `upa test` | Self-check of the selection logic |

Ctrl+C stops it; the current signal stays as it is.

## Dashboard

```
DTPF - Now making: Molten Infinity
Updated 14:02, checks every 60s
──────────────────────────────────────────────────────────────
> Molten Infinity   [████████░░░░░░░░░░░░]  40% of target  60M / 150M ↑  MAKING
  Molten SpaceTime  [██████████░░░░░░░░░░]  50% vs others  12M        ↓  WAITING: needs Excited Plasma
  Molten Hypogen    [████████████████████] 100% vs others  80M           READY
```

- **of target**: stock / cap.
- **vs others**: stock compared to the average of the other products (by weight). Full = not behind.
- Bars are red below 25%. Lowest bars are listed first. Arrows show change since the last check.
- Status: `MAKING`, `FULL` (at cap), `WAITING` (missing ingredient), `READY` (can run, not its turn).
