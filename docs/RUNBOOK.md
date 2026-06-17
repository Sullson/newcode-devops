# RUNBOOK — from zero to live

Copy-paste guide to take this repo from nothing to a live site, then (optionally) prove the AKS path.
Everything runs from the repo root unless noted. Commands are 1:1 — adjust only the REAL values.

**Mental model**
- The **persistent** infra (always-on front on Azure Static Web Apps, DNS, ACR, Key Vault, identities,
  Cloudflare tunnel) is created **once** and stays up. Standing cost ≈ $5/mo (ACR Basic).
- The **ephemeral** AKS cluster + Grafana/Prometheus exist only during a proof run (`deploy_aks=true`)
  and are torn back down (`deploy_aks=false`) — never a full destroy, so the front survives.
- The **first** `terraform apply` is run **locally** (you, via `az login`), because it creates the very
  identity GitHub Actions later uses. After that, everything runs from GitHub Actions.

---

## 0. Prerequisites

Accounts (all you already have): **Azure** subscription, **Cloudflare** with the `msulawiak.pl` zone
active, **Tailscale** tailnet, **GitHub** account `sullson`.

CLIs on your machine:

```bash
az version          # Azure CLI
terraform version   # >= 1.7
gh --version        # GitHub CLI (logged in: gh auth login)
node -v             # 20.x   (for the local site preview / build)
git --version
# docker — optional, only for the local container test in step 9
```

---

## 1. Confirm the personal facts (no placeholders left)

The CV ships filled in with real facts — there are **no `{{TODO}}` placeholders to replace**. Before
going public, confirm none slipped into the content files (this should print nothing — `CLAUDE.md` and
`SECURITY.md` only *describe* the marker convention, so scope the check to where facts actually live):

```bash
grep -rn "{{TODO" app/src README.md LICENSE SLO.md    # expect: no output
```

If you're **forking this for your own CV**, swap the personal facts (name, contact, Calendly/LinkedIn,
years of Azure/K8s, alert channel) in `app/src/pages/index.astro`, `README.md`, `LICENSE`, `SLO.md`.
These are content only — none are secrets.

Sanity-check the site still builds:

```bash
cd app && npm install && npm run build && cd ..
```

---

## 2. Local environment (`.env` — gitignored, real values safe here)

```bash
cp .env.example .env
# edit .env and set the 4 REAL values:
#   ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, TF_VAR_cloudflare_account_id, CLOUDFLARE_API_TOKEN
```

- `ARM_SUBSCRIPTION_ID` / `ARM_TENANT_ID`: Azure portal → Subscriptions / Microsoft Entra ID.
- `TF_VAR_cloudflare_account_id`: Cloudflare dashboard → right sidebar "Account ID".
- `CLOUDFLARE_API_TOKEN`: Cloudflare → My Profile → API Tokens → Create. Scopes:
  **Zone → DNS → Edit** (on `msulawiak.pl`) **+ Account → Cloudflare Tunnel → Edit**.

Load it:

```bash
az login
az account set --subscription "$ARM_SUBSCRIPTION_ID"   # if you have several
set -a; source .env; set +a
```

---

## 3. Bootstrap the Terraform state backend (once)

```bash
bash scripts/bootstrap-backend.sh
```

Creates the resource group, the state storage account (`stnewcodecvtf`), the `tfstate` container, and
**grants your user `Storage Blob Data Contributor`** on it (the account has shared-key access disabled,
so AAD data-plane access is required; subscription Owner alone is not enough). It waits ~30s for RBAC to
propagate.

---

## 4. First apply — the persistent infra (local)

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply        # deploy_aks defaults to false -> persistent only, NO cluster
```

This creates: Static Web App (front), Cloudflare DNS + tunnel, ACR, Key Vault, the GitHub-OIDC identity,
the app identity, Log Analytics. **No AKS, no Grafana** (those are ephemeral). Review the plan, type `yes`.

Grab the outputs you'll need for GitHub secrets:

```bash
terraform -chdir=terraform output
terraform -chdir=terraform output -raw gh_oidc_client_id   # -> AZURE_CLIENT_ID
terraform -chdir=terraform output -raw swa_api_key          # -> SWA_DEPLOY_TOKEN (sensitive)
terraform -chdir=terraform output -raw swa_default_hostname # the SWA host the front DNS points at
```

---

## 5. Tailscale OAuth client + ACL

GitHub Actions joins the tailnet ephemerally and installs the operator that fronts the PRIVATE AKS API.

1. Tailscale admin console → **Settings → OAuth clients → Generate**. Scopes: `devices:write` and
   `auth_keys`. Tag it `tag:ci`. Save the **client id** and **secret** (for step 6).
2. Tailscale admin console → **Access controls** — make sure these tags exist and CI may use the operator
   proxy. Starter snippet (adjust to your ACL):

```jsonc
"tagOwners": {
  "tag:ci":           ["autogroup:admin"],
  "tag:k8s-operator": ["autogroup:admin"]
},
"grants": [
  {
    "src": ["tag:ci"],
    "dst": ["tag:k8s-operator"],
    "app": { "tailscale.com/cap/kubernetes": [{ "impersonate": { "groups": ["system:masters"] } }] }
  }
]
```

> This is the fiddliest part. If `deploy-aks` later can't reach the cluster, it's almost always the ACL
> grant or the operator hostname — see Troubleshooting.

---

## 6. Create the GitHub repo and set secrets

> Do these in order: create the repo, set secrets + environment, **then** push — so the first workflow
> run already has its secrets.

```bash
# (git init / first commit — do when you're ready; see step 7)
gh repo create sullson/newcode-devops --public --disable-wiki

R=sullson/newcode-devops

# 4 values you already have locally
gh secret set AZURE_SUBSCRIPTION_ID -R $R --body "$ARM_SUBSCRIPTION_ID"
gh secret set AZURE_TENANT_ID       -R $R --body "$ARM_TENANT_ID"
gh secret set CF_ACCOUNT_ID         -R $R --body "$TF_VAR_cloudflare_account_id"
gh secret set CLOUDFLARE_API_TOKEN  -R $R --body "$CLOUDFLARE_API_TOKEN"

# 2 outputs from step 4
gh secret set AZURE_CLIENT_ID    -R $R --body "$(terraform -chdir=terraform output -raw gh_oidc_client_id)"
gh secret set SWA_DEPLOY_TOKEN   -R $R --body "$(terraform -chdir=terraform output -raw swa_api_key)"

# 2 from Tailscale (step 5)
gh secret set TS_OAUTH_CLIENT_ID -R $R --body "REPLACE_ME_ts_client_id"
gh secret set TS_OAUTH_SECRET    -R $R --body "REPLACE_ME_ts_secret"

# Protection gate used by infra/deploy-aks jobs (environment: production)
gh api -X PUT repos/$R/environments/production >/dev/null
```

`GITHUB_TOKEN` is automatic — do not set it. After the first push, **Settings → Actions → General →
Workflow permissions → Read and write + "Allow GitHub Actions to create and approve pull requests"**
(needed for Renovate; the API doesn't toggle this, do it in the UI).

---

## 7. Push the code (when you say go — not done yet)

```bash
git init -b main
git add -A
git commit -m "Initial public scaffold: Azure/AKS DevOps CV"   # commit under your own git identity (configured locally)
git remote add origin git@github.com:sullson/newcode-devops.git
git push -u origin main
```

The push triggers `ci.yml` (build + scan + sign the image) and `frontend-deploy.yml` (publish the static
site to SWA). Watch them:

```bash
gh run watch -R sullson/newcode-devops
```

---

## 8. Verify the live front

```bash
curl -I https://newcode.msulawiak.pl        # expect HTTP 200
```

If the custom domain isn't serving yet, bind it on the Static Web App side (DNS already points there from
Terraform): Azure portal → Static Web App `swa-newcode-cv` → Custom domains → add `newcode.msulawiak.pl`
and complete validation. (One-time; can also be codified later with `azurerm_static_web_app_custom_domain`.)

---

## 9. (Optional) Prove the AKS path

Local container smoke test (no cloud):

```bash
docker build -t cv-site app
docker run --rm -p 8080:8080 cv-site
curl localhost:8080/healthz                 # 200
```

Full on-demand AKS proof (stands up a real cluster, deploys via Helm over Tailscale, captures evidence,
tears the cluster back down):

```bash
gh workflow run deploy-aks.yml -R sullson/newcode-devops
gh run watch -R sullson/newcode-devops
```

After it finishes, the proof file appears in `docs/evidence/aks-proof-<timestamp>.md` (committed by the
workflow). The cluster + Grafana are gone; the front stays up.

---

## 10. Day-2

- **Update the site:** edit `app/`, `git push` → `frontend-deploy` republishes.
- **Release a versioned image:** create a GitHub Release → `ci.yml` promotes the tested image to `:latest`.
- **Dependencies:** Renovate opens a weekly "Dependency Dashboard" issue; tick what to upgrade.
- **Security:** `security-nightly` opens/updates one `security` issue; Trivy findings also land in
  **Security → Code scanning**.
- **Tear everything down for good** (only if you truly want it gone):
  `terraform -chdir=terraform destroy` — removes the persistent infra too. The state storage RG
  (`rg-newcode-cv` was reused) and tfstate remain unless you delete them manually. If you ran with
  `kv_purge_protection=true`, the Key Vault stays soft-deleted (name reserved, un-purgeable) for
  `soft_delete_retention_days` — recreating `kv-newcode-cv` must wait out that window.

---

## Troubleshooting (the known gotchas)

| Symptom | Cause / fix |
|---|---|
| `terraform init` fails with `AuthorizationPermissionMismatch` | RBAC on the state storage not propagated yet, or you skipped the role grant. Re-run `bootstrap-backend.sh` (idempotent) and wait a minute. |
| First local `apply` fails on auth | You must be `az login`'d. `use_oidc` is env-driven now — do **not** export `ARM_USE_OIDC` locally. |
| `apply` fails on Cloudflare | `CLOUDFLARE_API_TOKEN` not exported, or token missing the Tunnel/DNS scopes. Re-`source .env`. |
| SWA can't be created in `swedencentral` | Expected — SWA Free is region-limited; Terraform pins it to `westeurope` on purpose. |
| `deploy-aks` can't reach the cluster | Tailscale ACL grant for `tag:ci` → operator, or the operator hostname. The kubeconfig server uses TF output `tailscale_operator_hostname` (default `aks-newcode-cv-operator`); it must match `operatorConfig.hostname` set during the operator install. |
| cloudflared / tunnel 502 when AKS is down | Expected — the `aks.` host points at a tunnel with no connector until a proof run is live. |
| Renovate never opens PRs | Enable "Allow GitHub Actions to create and approve pull requests" in Settings (UI only). |
| Trivy fails the CI build | Working as intended — HIGH/CRITICAL with an available fix blocks merge. Bump the dep (Renovate) or justify. |
