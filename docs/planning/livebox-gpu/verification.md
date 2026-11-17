# LiveBox GPU — verification

**Shipped in v1.65 (2026-11-17).**

## Checked

- Installed 1.65 on the M4 Max and let LiveBox render. A one-process diagnostic
  file written from inside the widget sandbox returned
  `{"available":true,"value":45}`, so the IOAccelerator registry read is allowed
  in the extension. The diagnostic file was removed before the final build.
- Five direct reads outside the sandbox returned 35, 37, 35, 35, 35 over two
  seconds, so the counter is live rather than a boot-time snapshot.
- The GPU row uses the same `metricRow` as CPU/MEM/DISK, with its own show
  toggle, color and 80/90 warn/alarm pair. The chart and persisted history are
  unchanged.
- `GPUStatsParser` rejects missing/non-numeric/NaN and clamps to 0...100; the
  decoder keeps the legacy threshold pair for GPU too.
- 1,760 shared tests green; Debug and Release builds green; release CI green;
  the published DMG's checksum and version were verified.

## Not shippable

ANE usage has no public API. `powermetrics --samplers ane_power` requires
superuser and the only other source is the private `IOReport` framework. The
roadmap records the blocker; no privileged helper or private framework was
added.

## Release

- GitHub release: `v1.65`
- DMG SHA256: `540e403f9d1b4bec2e460e73682482ea167ed6297a743c086077e997c3c46c01`
