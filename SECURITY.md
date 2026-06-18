# Security & Threat Model

This repo is **public**. Treat everything in it as world-readable forever. The design goal: the whole
repo is safe to publish, and the same controls protect *confidential client data* (e.g. legal documents
in an agentic-AI product) in production.

## Reporting

Found something? Open a private security advisory on this repo's GitHub **Security** tab.
Do not open a public issue for a vulnerability.

---

## 1. Zero secret values in a public repo

The hard rule for this repo: **no real key, token, password, client-id, tenant-id, or subscription-id
ever appears in a file.** Placeholders only (`REPLACE_ME`, `${{ secrets.* }}`, TF variables, `{{TODO}}`).

How secrets are actually delivered without committing them:

| Secret | Mechanism | Where it lives | In repo? |
|---|---|---|---|
| Azure ARM auth (CI) | **GitHub OIDC workload-identity federation** → `id-gh-oidc-newcode-cv` | Federated creds on a user-assigned MI; GitHub mints a short-lived token per run | No SP secret anywhere |
| App → Key Vault | **Workload Identity** (`id-cv-app`) federated to k8s SA `cv-site` | Token projected into the pod by AKS; MI granted Key Vault RBAC | No |
| In-cluster secrets (e.g. cloudflared tunnel token) | **Azure Key Vault + Secrets Store CSI Driver** via `SecretProviderClass` | Key Vault `kv-newcode-cv` (RBAC mode); mounted at runtime | No |
| Tailscale CI join | **OAuth client, `tag:ci`**, ephemeral node | GitHub Actions secret, consumed at runtime | Referenced as `${{ secrets.* }}` only |
| Any other CI value | **GitHub Environments / Actions secrets** | GitHub | Referenced as `${{ secrets.NAME }}` |

Enforcement:
- **gitleaks** as a **pre-commit hook** (local) *and* as a **CI gate** - a commit with a detectable
  secret fails before merge.
- Code review + the `.gitignore` rules (no `*.tfvars` except `*.example`, no `*.tfstate`, no `.env`).
- TF state lives in Azure (`stnewcodecvtf/tfstate/cv.tfstate`), never in the repo - and state can
  contain sensitive values, so it stays in a private storage account with RBAC.

---

## 2. Identity & least privilege

- **No long-lived credentials.** CI authenticates to Azure with OIDC; tokens are short-lived and
  scoped to the run. No service-principal client secret to leak or rotate.
- **Two distinct managed identities**, separated by blast radius:
  - `id-gh-oidc-newcode-cv` - used by CI to provision/deploy. Holds **Contributor on `rg-newcode-cv`**
    (it creates all the infra), AcrPush, and - only while a cluster exists - AKS RBAC Cluster Admin.
    This is least-privilege at the **resource-group blast radius**, not minimal permissions: a
    provisioning identity needs broad rights *within its RG*, and it holds none outside it.
  - `id-cv-app` - used by the running app to read its own secrets from Key Vault. Federated to the
    `cv-site` k8s ServiceAccount; it cannot deploy anything.
- **Key Vault in RBAC mode** - access is role assignments, not access policies, each scoped to the
  minimum: the **app** gets *Key Vault Secrets User* (read) and the **deployer** *Key Vault Secrets
  Officer* (write the tunnel token). Neither holds Key Vault Administrator.

---

## 3. Supply chain integrity

- **Image scanning**: Trivy on every build - `severity HIGH,CRITICAL`, `--ignore-unfixed`,
  `--exit-code 1` (a fixable high/critical fails the build).
- **Signing**: images **signed with cosign keyless** (OIDC/Sigstore, no private key stored) and
  **verified at deploy** before they reach the cluster.
- **Every third-party action is pinned to a commit SHA** with a `# vX.Y.Z` comment, so a hijacked
  upstream tag can't inject code into a build. The highest-blast-radius ones - `actions/checkout`
  (every job) and `hashicorp/setup-terraform` (the Azure-OIDC / state jobs) - matter most here. Renovate
  (`pinDigests: true` in `renovate.json`) opens PRs to bump the SHAs as new versions ship.
- **Renovate** with `dependencyDashboardApproval: true` - dependency bumps are explicit, reviewed,
  not auto-merged blindly.
- **`actions/dependency-review`** on PRs flags vulnerable/incompatible-licensed deps before merge.

---

## 4. Network posture - outbound-only

Every connection to the cluster is initiated from inside it:

- **The AKS API server is private.** CI reaches it only by joining the **tailnet** (`tag:ci`,
  ephemeral) and going through the **Tailscale Operator's API-server proxy**. The kubeconfig CI uses
  points at a tailnet address, not a public IP.
- **App ingress is outbound-only** via **Cloudflare Tunnel** (`cloudflared` dials out). The only way
  in is the tunnel the cluster opened itself, so there's nothing listening for it to scan.
- Combined with default-deny NetworkPolicy (below) - **enforced** by the Azure CNI Overlay + Cilium
  data plane (`terraform/aks.tf`), not merely declared - east-west traffic is locked down too.

---

## 5. Tenant isolation (confidential client data)

Agentic-AI for legal work implies multiple clients' confidential data on shared infrastructure. The
isolation model demonstrated here:

- **Namespace per tenant** - demo namespaces `tenant-a` and `tenant-b` (plus the app namespace `cv`).
- **Default-deny NetworkPolicy, enforced** - each tenant namespace gets an all-ingress/all-egress
  default-deny, made real by the Cilium data plane (§4, not just declared). A pod in `tenant-a` cannot
  reach a pod in `tenant-b` - no implicit cross-tenant traffic. The **scoped-allow** companion (open
  only required flows, e.g. DNS) is wired for the live app namespace `cv`
  (`helm/cv-site/templates/networkpolicy.yaml`); the tenant demo namespaces ship default-deny only.
- **Per-tenant Key Vault scoping & per-workload identity - the production pattern, not fanned out here.**
  In production each tenant's workload identity is federated to its own ServiceAccount and granted Key
  Vault RBAC on only its own secrets, so one tenant's compromise cannot read another's. This repo wires
  that identity path for the single app identity `id-cv-app` (Key Vault Secrets User on `kv-newcode-cv`);
  the per-tenant fan-out is the documented extension - consistent with §6 ("a demo of the pattern").

See the policies in [`helm/cv-site/templates/`](helm/cv-site/templates/) and the namespace/NetworkPolicy
definitions referenced by the chart.

---

## 6. Honest scope

This is a portfolio, and it's clear about scope: the tenant namespaces are a **demo** of the isolation
pattern, not a multi-tenant SaaS control plane. The controls themselves (OIDC, Key Vault + CSI,
default-deny, signed images, outbound-only networking) are real and run on this repo's own deployment.

Deliberate demo trade-offs - each a one-line change for production, not an oversight:

- **Key Vault purge protection is off by default** (`var.kv_purge_protection`): it is irreversible and
  would lock the vault name for the soft-delete window after a teardown, which fights an ephemeral demo.
  Production sets it `true`. Soft delete itself is on (7-day retention).
- **Key Vault and ACR keep public endpoints**, gated by RBAC + AAD data-plane auth - the first apply
  runs from a laptop, CI writes the tunnel token from a hosted runner, and the CSI driver reads over the
  public endpoint. Private endpoints + VNet/private DNS are the production step, not built here.
- **ACR is Basic** (~$5/mo): image integrity comes from CI **Trivy + cosign**, not Premium-only ACR
  content trust / quarantine / geo-replication / Defender scanning.
