# Deployment status & resume notes

State that is **not** derivable from the code/git — what is actually deployed, what
remains, and the non-obvious gotchas hit during bring-up. For a fresh agent or human
picking this up. No secret values here (per the repo's zero-secrets rule); concrete
identifiers come from `terraform output` / GitHub secrets.

_Last updated: 2026-06-18._

## Live now ✅
- **Persistent Azure infra is applied** (`deploy_aks=false`): RG, ACR, Key Vault, Log
  Analytics, Static Web App, two managed identities (`id-gh-oidc-newcode-cv`,
  `id-cv-app`) + 3 GitHub-OIDC federated credentials + role assignments, Cloudflare
  tunnel + DNS. TF state is in the `stnewcodecvtf` storage account (`cv.tfstate`).
- **CI is green**: build → Trivy (clean) → cosign keyless sign → push. ACR holds
  `cv-site:latest`, `cv-site:<sha>`, and the `…​.sig` signature.
- **Front is live**: `https://newcode.msulawiak.pl` — Azure Static Web Apps, real CV
  content, valid TLS (SWA-managed cert).
- **GitHub is configured**: repo secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`, `CF_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `SWA_DEPLOY_TOKEN`,
  `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`) and a `production` environment.
- **The AKS live window runs end-to-end.** First successful run 2026-06-18 (manual
  `action=up`): `deploy_aks=true` stands up the private AKS cluster + Managed
  Prometheus/Grafana, bootstraps the Tailscale operator API-server proxy, cosign-verifies
  `:latest` (gate), and Helm-installs `cv-site` (app + cloudflared tunnel + in-cluster
  Prometheus/Grafana). During the window `https://aks-newcode.msulawiak.pl/healthz` and
  `https://grafana-newcode.msulawiak.pl/api/health` both return 200 and the front's "LIVE"
  badge lights up. `docs/evidence/` holds the first `aks-proof-*.md` (cosign output +
  `kubectl get pods` + `helm status`), committed back by the workflow.
- **Tailscale is configured**: one OAuth client (scopes `devices:core` + `auth_keys`, tags
  `tag:ci` + `tag:k8s-operator`) plus the tailnet ACL (mutual tag ownership + the kubernetes
  grant — see gotcha below).

## Not done yet ⏳
- **Only the manual `action=up`/`down` path is proven; a scheduled (cron) run has not yet
  been observed.** The crons (`0 8` up / `0 11` down, `* * 1-5`, CEST) are wired.
- **Quality follow-ups (not deployment blockers):** `helm lint` is not yet a CI gate; the
  chart deploys `:latest` rather than the immutable `:sha` (cosign also verifies `:latest`, a
  TOCTOU gap); `SLO.md` still describes the Managed-Grafana alerting as if always-on; most
  third-party Actions are `@tag`-pinned pending Renovate. (RUNBOOK §5 still shows the old
  single-tag Tailscale snippet — superseded by the mutual-ownership gotcha below.)

## Gotchas / decisions for whoever resumes
- **First `terraform apply` needs an RG import.** `scripts/bootstrap-backend.sh` creates
  `rg-newcode-cv` (to host the state account); Terraform also manages that RG, so import
  it before the first apply or it errors "already exists":
  `terraform -chdir=terraform import azurerm_resource_group.rg /subscriptions/<sub>/resourceGroups/rg-newcode-cv`.
- **CI identity role set.** `id-gh-oidc-newcode-cv` holds on `rg-newcode-cv`: Contributor,
  User Access Administrator (codified in `identity.tf`), and AcrPush on the ACR; plus
  `Storage Blob Data Contributor` on the state account `stnewcodecvtf`, granted out-of-band
  (the state account is bootstrap-created outside Terraform and CI reads state over AAD, so
  the grant lives outside the Terraform run). The Key Vault tunnel-token secret is written by
  the `deploy-aks` workflow, not Terraform.
- **Tailscale: the shared OAuth client needs *mutual tag ownership*.** One OAuth client
  (scopes `devices:core` + `auth_keys`) mints both the CI node (`tag:ci`) and the operator
  (`tag:k8s-operator`). An OAuth client may apply tag X only if one of *its own* tags is in
  `tagOwners[X]` — `[]` and `["autogroup:admin"]` both fail (the client is not a user). The
  tailnet ACL therefore needs `"tag:ci": ["autogroup:admin","tag:k8s-operator"]` and
  `"tag:k8s-operator": ["autogroup:admin","tag:ci"]`, plus a grant
  `{src:[tag:ci], dst:[tag:k8s-operator], app:{"tailscale.com/cap/kubernetes":[{impersonate:{groups:[system:masters]}}]}}`
  and network reachability `tag:ci → tag:k8s-operator:443`. Symptom when wrong:
  `400 "requested tags [...] are invalid or not permitted"`. NB `tailscale/github-action`
  marks its step **success** even when `tailscale up` fails every retry — read the step log.
- **The operator is bootstrapped via the runCommand ARM REST API, not `az aks command
  invoke`.** The CLI wrapper's long-running-operation poller is broken across az versions
  ("Operation returned an invalid status 'OK'/'Not Found'") and swallows the result; the REST
  call (`POST …/runCommand` with a `clusterToken`, then poll `commandResults`) surfaces
  `exitCode`/`logs`/`reason` — that is how the real failure (an Unschedulable helper pod) was
  found.
- **Node pool is 2× `Standard_D2s_v3`.** `Standard_B2s`/`B2s_v2` are unavailable / zero-quota
  in `swedencentral` for this subscription; the `D*sv3` family has quota. A single 2-vCPU node
  cannot even schedule the `command invoke` helper pod alongside the managed addons (Managed
  Prometheus + Container Insights + Cilium + CSI), hence `node_count = 2`. Managed Grafana
  needs `grafana_major_version = 12`.
- **A fresh subscription needs resource providers registered** (else `az`/TF fail, often
  with a misleading `SubscriptionNotFound`): Microsoft.Storage, ContainerRegistry,
  KeyVault, ContainerService, ManagedIdentity, OperationalInsights, Monitor, Dashboard,
  Insights, Web, Network, AlertsManagement.
- **GitHub OIDC subject matching is case-sensitive** (Entra, Aug-2024 change). Set
  `TF_VAR_github_repo` to the **exact** GitHub owner/repo casing (e.g. `Sullson/...`).
  Changing a federated credential's subject requires **delete + recreate** — an in-place
  edit does not re-register at the token endpoint (symptom: `AADSTS7002138`, "matches
  case-insensitive but not case-sensitive"). `cosign verify` uses a `(?i)` regexp for the
  same reason.
- **`aquasecurity/trivy-action` is pinned to `v0.36.0`** — `v0.28.0` referenced a removed
  `setup-trivy@v0.2.1` and failed at action setup.
- **The runtime image runs `apk upgrade`** to clear fixable base-image CVEs that the Trivy
  HIGH/CRITICAL gate (correctly) blocks on.
- **Front TLS:** the SWA custom domain is bound via `cname-delegation` and the front DNS
  record is **DNS-only (grey cloud)** so SWA terminates TLS itself. Proxying the front
  caused HTTP 526. The tunnel hosts (`aks-newcode`, `grafana-newcode`) stay **proxied**.
- **`:latest` is maintained by the main CI build** (not GitHub Releases); `deploy-aks`
  deploys `:latest`. The Release-based promote job is wired but unused.

## Full bring-up from zero
See [RUNBOOK.md](RUNBOOK.md). Order: fill `.env` → `az login` →
`scripts/bootstrap-backend.sh` → `terraform init` → import RG → `terraform apply` →
set GitHub secrets + `production` env → push (CI builds `:latest`) →
`gh workflow run frontend-deploy.yml` (front) → `gh workflow run deploy-aks.yml -f action=up`.
