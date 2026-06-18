# Architecture

Deeper, component-by-component walkthrough of the platform. For the one-screen overview and the diagram,
see the [README](../README.md). For the security rationale, see [SECURITY.md](../SECURITY.md).

Region: **swedencentral**. Resource group: **`rg-newcode-cv`**. Everything is provisioned by Terraform
(`azurerm`) with state in `stnewcodecvtf/tfstate/cv.tfstate`. IaC lives in [`terraform/`](../terraform/);
the cluster definition is [`terraform/aks.tf`](../terraform/aks.tf).

---

## Components

### AKS — private cluster (`aks-newcode-cv`)
A managed Kubernetes cluster with **no public API server endpoint**. The control plane is reachable only
from inside the virtual network or over the tailnet (below). This is the deliberate, non-obvious choice:
it removes the single most-scanned attack surface a cluster has. App workloads run in namespace `cv`;
demo tenant namespaces `tenant-a` / `tenant-b` show isolation.

### Workload Identity (`id-cv-app`)
The app does not hold any Azure credential. The k8s ServiceAccount `cv-site` (namespace `cv`) is labeled
`azure.workload.identity/use: "true"` and annotated with `azure.workload.identity/client-id`. AKS
projects a federated token into the pod; Azure trusts it because the user-assigned managed identity
`id-cv-app` is federated to that exact SA. The identity has only the Key Vault RBAC it needs — it cannot
deploy or modify infrastructure.

### Secrets Store CSI Driver + SecretProviderClass
Runtime secrets (e.g. the Cloudflare Tunnel token) are **not** Kubernetes Secrets baked from the repo.
A `SecretProviderClass` (in [`helm/cv-site/templates/`](../helm/cv-site/templates/)) tells the CSI driver
to fetch named secrets from Key Vault `kv-newcode-cv` (RBAC mode) using the workload identity, and mount
them into the pod at runtime. The secret value never touches git, never sits in a manifest.

### Tailscale Kubernetes Operator — API-server proxy
Because the API server is private, CI cannot `kubectl`/`helm` against a public endpoint. The Tailscale
Operator runs in-cluster and exposes the API server as a node *on the tailnet*. CI joins the tailnet
ephemerally (OAuth client, `tag:ci`) for the duration of a run and points kubectl at the tailnet proxy.
No public control-plane endpoint, no stored kubeconfig with a public IP, and the CI node disappears
when the run ends. Setup action: [`.github/actions/setup-tailscale/`](../.github/actions/setup-tailscale/).

### Cloudflare Tunnel (`cloudflared`)
App ingress is **outbound-only**. `cloudflared` runs as its own Deployment in namespace `cv` and dials
out to the Cloudflare edge, which routes `aks-newcode.msulawiak.pl` back down the tunnel to the
ClusterIP Service. There is no LoadBalancer, no public Ingress, no NodePort — nothing to expose. The
tunnel token comes from Key Vault via the CSI driver, not the repo.

### Managed Prometheus (`amw-newcode-cv`) + Managed Grafana (`amg-newcode-cv`)
Each cv-site pod runs an `nginx-prometheus-exporter` sidecar on `:9113 /metrics`, scraping nginx
`stub_status` on `127.0.0.1:8081`. A `ServiceMonitor` (in the Helm chart) tells Azure Managed Prometheus
what to scrape. Managed Grafana renders the RED dashboard
([`grafana/dashboard-red.json`](../grafana/dashboard-red.json)): request **R**ate, **E**rror rate, and
**D**uration (p50/p95). Diagnostic logs land in Log Analytics `log-newcode-cv`. SLO in [SLO.md](../SLO.md).

This Azure-native path is the **production-grade variant**. For the public live window there is also a
**lightweight in-cluster Prometheus + anonymous Grafana** (in the Helm chart) exposed through the same
Cloudflare Tunnel at `grafana-newcode.msulawiak.pl`, so anyone can read the live dashboard in a browser
with no Azure login. It scrapes the same exporter (per-pod, via a headless Service + DNS SD) and renders a
trimmed live dashboard ([`helm/cv-site/dashboards/cv-site-live.json`](../helm/cv-site/dashboards/cv-site-live.json))
— only the panels backed by real `stub_status` data, so a visitor never lands on an empty "No data" panel.

### Azure Static Web Apps (`swa-newcode-cv`)
The always-on, free-tier front at `newcode.msulawiak.pl`. It serves the **same** Astro static output as
the container image — the SWA is the durable, $0 surface so the CV is never down, while AKS is the
on-demand proof surface.

### ACR (`acrnewcodecv`) + image
`acrnewcodecv.azurecr.io/cv-site:<tag>` where `<tag>` is the git short SHA on `main`; the `main` build
also updates the moving `:latest` tag that the on-demand AKS proof deploys. (Promoting an immutable
`:latest` via a GitHub Release is a more rigorous path — wired in `ci.yml` but not used for now.) The
image is nginx serving the Astro static output on `:8080`, `/healthz` returns 200.
Built, Trivy-scanned, and cosign-signed in CI; verified before deploy.

---

## Data & secret flow

1. **Provision**: GitHub Actions → OIDC token (`id-gh-oidc-newcode-cv`) → Azure ARM → Terraform creates
   all resources. No SP secret involved.
2. **Build**: CI builds the image → Trivy scan (HIGH/CRITICAL, ignore-unfixed, fail-on-find) → cosign
   keyless sign → push to ACR.
3. **Deploy** (on-demand): CI joins tailnet (`tag:ci`) → `helm upgrade --install cv-site` through the
   Tailscale API proxy → cosign verify the image → pods start.
4. **Runtime secrets**: pod uses workload identity (`id-cv-app`) → Secrets Store CSI fetches the tunnel
   token from Key Vault → `cloudflared` dials out to Cloudflare edge.
5. **Observe**: exporter sidecar → ServiceMonitor → Managed Prometheus (`amw`) → Managed Grafana (`amg`).
6. **Prove & destroy**: CI captures kubectl/helm/curl output into [`docs/evidence/`](evidence/), then
   tears the cluster down.

The only secret *values* that exist live in Key Vault and GitHub secret stores — never in git.

---

## Cost rationale — why hybrid (always-on SWA + on-demand AKS)

A private AKS cluster with node pools running 24/7 to serve a static CV would cost real money for zero
benefit — the CV is static HTML. So:

- **Always-on** is Azure **Static Web Apps free tier**: $0, globally cached, never 404s.
- **On-demand** is the full AKS platform, run as a **daily live window** (10:00–13:00 Europe/Warsaw) by
  the `deploy-aks` workflow: an `up` run (cron + manual) stands the cluster up and leaves it running so it
  is browsable; a `down` run (cron + manual) tears it back down. Each `up` records timestamped evidence in
  [`docs/evidence/`](evidence/), so the durable artifact is the proof, not a running cluster.

This mirrors a real early-stage tradeoff: pay for the proof, not for idle capacity. It also demonstrates
clean teardown / reproducible-from-zero infrastructure, which matters more than uptime for a demo.

---

## Model-serving extension (credible, not benchmarked)

For an agentic-AI product, model-inference workloads would slot into the same chassis: a GPU node pool
(e.g. an NVIDIA-backed AKS node pool with the device plugin) scheduled via taints/tolerations and
`nodeSelector`, serving models behind the same private-API + Cloudflare-Tunnel posture so inference
endpoints carry **no public ingress**. Model weights and provider API keys would flow through the **same**
Key Vault + CSI + workload-identity path used here — no secrets in the repo. Autoscaling would extend
from the current HPA to KEDA (queue/GPU-utilization triggers) and Cluster Autoscaler on the GPU pool so
expensive nodes scale to zero when idle. The observability path (ServiceMonitor → Managed Prometheus →
Grafana) extends to inference RED metrics + token/latency gauges. No invented numbers here — the point is
that the security, secrets, networking, and observability primitives in this repo are exactly the ones a
model-serving tier needs.
