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
  `AZURE_SUBSCRIPTION_ID`, `CF_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `SWA_DEPLOY_TOKEN`)
  and a `production` environment.

## Not done yet ⏳
- **The AKS live window has never been run.** `deploy-aks` (up/down, daily 10:00–13:00
  Europe/Warsaw + manual) needs Tailscale, which is **not** configured:
  1. A Tailscale **OAuth client** tagged `tag:ci` (scope `devices:write`).
  2. An **ACL** with `tagOwners` for `tag:ci` + `tag:k8s-operator`, and a grant giving
     `tag:ci` the `tailscale.com/cap/kubernetes` cap impersonating `system:masters` on
     `tag:k8s-operator`. (Snippet in [RUNBOOK.md](RUNBOOK.md).)
  3. GitHub secrets `TS_OAUTH_CLIENT_ID` + `TS_OAUTH_SECRET`.
  Then: `gh workflow run deploy-aks.yml -f action=up`. During the window
  `aks-newcode.msulawiak.pl` (app) and `grafana-newcode.msulawiak.pl` (anonymous
  Grafana) go live; the front's "LIVE" badge lights up automatically.
- **`docs/evidence/` is still empty** — the first successful `deploy-aks` up-run commits
  the first `aks-proof-*.md`.

## Gotchas / decisions for whoever resumes
- **First `terraform apply` needs an RG import.** `scripts/bootstrap-backend.sh` creates
  `rg-newcode-cv` (to host the state account); Terraform also manages that RG, so import
  it before the first apply or it errors "already exists":
  `terraform -chdir=terraform import azurerm_resource_group.rg /subscriptions/<sub>/resourceGroups/rg-newcode-cv`.
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
