# SLO - live front

Service-level objective for the **always-on** CV front at `newcode.msulawiak.pl`. The on-demand AKS
surface is ephemeral by design and is *not* under an availability SLO - its evidence model is described
in [docs/evidence/](docs/evidence/).

## Service

- **SLI**: successful HTTP responses (`2xx`/`3xx`) to `GET /` and `GET /healthz`, measured at the edge.
- **SLO - availability**: **99.9%** of requests succeed over a rolling **30-day** window.
- **SLO - latency**: **p95 < 500 ms** at the edge (static content, globally cached by SWA / Cloudflare).

## Error budget

- 99.9% over 30 days ≈ **43 minutes** of allowed downtime per month.
- **Burn-rate policy**: if the budget is being consumed fast enough to exhaust it before the window ends,
  alert and freeze non-essential changes until the front is healthy again.
- Most static-front "incidents" are deploy regressions (bad build shipped) rather than infra outages, so
  the practical control is: a failing `/healthz` post-deploy rolls back, and the SWA front stays on the
  last-good build.

## Measurement & alerting

- The AKS proof surface exposes the RED signals via the `nginx-prometheus-exporter` sidecar →
  ServiceMonitor → **Azure Managed Prometheus** (`amw-newcode-cv`), visualized in **Azure Managed
  Grafana** (`amg-newcode-cv`) using [`grafana/dashboard-red.json`](grafana/dashboard-red.json).
- Alerting is driven from **Managed Grafana** alert rules on the RED metrics (error-rate spike, p95
  latency breach, `/healthz` failure / target-down). Notification target: a chat/email webhook configured
  per environment in Managed Grafana.
- For the always-on SWA front, edge availability is the authoritative SLI; the in-cluster RED dashboard
  demonstrates the same signals the production app tier would emit.

## Review

Review the SLO and error-budget policy monthly. If the objective is routinely
over- or under-shot, adjust the target rather than letting it drift from reality.
