# Universal Passive Automation

OpenComputers script for GregTech: New Horizons.
It keeps a group of machines making whichever product you are lowest on, by switching a wireless redstone frequency that enables that recipe's ingredients.

## Install

Paste into the OpenOS shell:

```
wget -f https://raw.githubusercontent.com/Xela10001/universal-passive-automation/master/install.lua /tmp/i.lua && /tmp/i.lua
```

This installs the script, an example config (only if you don't have one), autostart, and the short command `upa`. Run it again to update; your config is kept.

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

### Default DTPF config

The installed config covers every DTPF product, each using its best recipe below Stellar catalyst (Exotic where one exists). Products that only have a Stellar recipe are not included. Every product is capped at 10k items / 10M L and needs at least 10k of each item ingredient and 1M L of each fluid ingredient. Programmed circuits and other non-consumed inputs are not checked, so keep them in the machine permanently. Delete any product you don't build a receiver for. Keys marked `verify` in the config haven't been checked in game.

| Freq | Product | Freq | Product |
|------|---------|------|---------|
| 1001 | Quantum Anomaly | 1012 | Raw Tesseract |
| 1002 | Superconductor Base LuV | 1013 | Superconductor Base UEV |
| 1003 | Superconductor Base ZPM | 1014 | Superconductor Base UIV |
| 1004 | Superconductor Base UV | 1015 | SpaceTime |
| 1005 | Bedrockium | 1016 | Superconductor Base UMV |
| 1006 | Chromatic Glass | 1017 | Shirabon |
| 1007 | Neutronium | 1018 | Quantum (+ Astral Titanium) |
| 1008 | Cosmic Neutronium | 1019 | Dimensionally Shifted Superfluid |
| 1009 | Infinity | 1020 | Six-Phased Copper |
| 1010 | Superconductor Base UHV | 1021 | Dark Matter |
| 1011 | Hypogen | | |

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
