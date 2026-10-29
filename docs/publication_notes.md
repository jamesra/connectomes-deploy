# Publication notes: connectomes-deploy

Install and run the connectomes backend (nornir build appliance and dashboard, Viking servers, proxy and certificates) on Ubuntu or Windows Docker hosts. Material for future papers: citations, formulas, algorithmic decisions and the reasoning behind them. Index of
all projects: `~/.cursor/publication-notes.md`. Format and rules: the `publication-notes` skill.

## Methods and contributions

- None recorded yet.

## Formulas

None recorded yet.

## Algorithmic decisions

- **2026-10-29 Segmentation model servers are rows of a models table, generated from one template service.**
  Why: the hardcoded `segmentation-v3` / `-v4` / `-sem-v1` services and their `SEG_*` variables had to be edited in the
  compose file, the proxy, the certificate renewer and the host-name defaults for every new model, and the earlier
  `models.json` script (D:\Docker\Builds\SegmentationServer) copied the whole container definition into the generated
  file, so the copy drifted from the base service (it still pointed at the pre-consolidation certbot volume).
  Now a row in `Run/viking-segmentation/models.json` is the whole definition: `stack.ps1 viking-segmentation model`
  writes `compose.generated.yaml`, whose services `extends` one template in Viking's compose file. Rejected: compose
  profiles per model (static, a new model needs a code change); a generator that emits the full service (drifts).
  Where: `stack.ps1` (`Invoke-ModelAction`), Viking `Servers/SegmentationServer/rebuild-and-start.ps1`.
- **2026-10-29 Model host names are one label (`segmentation-<prefix>.<domain>`).** Why: `*.connectomes.pitt.edu`
  covers one label, so `v3.segmentation.<domain>` (the dev box's `v3.segmentation.codepharm.net` scheme) would need
  its own `*.segmentation.<domain>` certificate, which HTTP-01 cannot issue. Rejected: two-label names by default
  (a `hostname` field in the row still allows them).
- **2026-10-29 The proxy reaches a model server over a shared Docker network when it is on the same host.** Why: no
  published port and no host firewall bypass; the name resolves through Docker DNS. Rows default to this when
  `VIKING_BACKEND_NETWORK` is set, to a published host port otherwise, and `macvlan` gives a row its own MAC and IP.
  Rejected: always publishing a port (the proxy then needs the host's address and the port is open to the LAN).
- **2026-10-29 Other stacks learn model names through drop-in folders, not their own variables.** The script writes
  `segmentation.map` (viking-proxy `models.d`) and `segmentation.names` (viking-certs `names.d`); the proxy
  includes `models.d/*.map` in its SNI map and the renewer re-reads `names.d/*.names` every cycle. Why: the proxy
  and renewer then know no model by name, and a new model's certificate name is requested without restarting
  either. Rejected: `VIKING_HOSTNAME_SEG_*` per model (the old arrangement).

## Discussion points

- None recorded yet.

## References

- None recorded yet.

## Open questions for a paper

- None recorded yet.
