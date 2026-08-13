# Inline brief: OpenBox cost-per-day chart (stacked by model)

Source: deck-next handoff (2026-08-14).

OpenBox's next slice: a cost-per-day chart stacked by model, alongside the
existing 14-day token chart. The opencode DB already has per-model and per-day
cost; the work is one new SQL grouping (day × model) in the agent reader, a
snapshot field with tolerant decode, and a Chart face + settings toggle cloned
from the openbox-tool-usage PR.

Caveat: remote serve mode must produce the same breakdown, and old snapshots
must decode without the new field. Tests follow the existing scratch-package
parser pattern.
