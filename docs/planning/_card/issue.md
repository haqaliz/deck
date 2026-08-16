# Inline brief: netbox-interface-picker

Source: deck-next handoff (2026-08-15).

Build the NetBox interface picker: a manual override of the auto "most active"
interface (ROADMAP.md:79). Add an interface picker to the NetBox settings tab —
a `NetBoxSettings` extension with tolerant decode like every other settings
struct — and have the widget filter its getifaddrs samples to the chosen
interface, keeping the auto pick as the default when unset. No agent or
snapshot changes; the widget already samples getifaddrs in-process. Caveats:
fall back to the auto pick when the chosen interface vanishes (Wi-Fi off), and
default the picker's list to interfaces with real traffic (skip lo0 and
zero-rate ones).
