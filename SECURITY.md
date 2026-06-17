# Security & Threat Model

This repo is **public**. Treat everything in it as world-readable forever. The design goal is that a
clone of this repo gives an attacker **no secret material and no inbound path** to anything — and that
the same controls would protect *confidential client data* (e.g. legal documents in an agentic-AI
product) in production.

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
- **gitleaks** as a **pre-commit hook** (local) *and* as a **CI gate** — a commit with a detectable
  secret fails before merge.
- Code review + the `.gitignore` rules (no `*.tfvars` except `*.example`, no `*.tfstate`, no `.env`).
- TF state lives in Azure (`stnewcodecvtf/tfstate/cv.tfstate`), never in the repo — and state can
  contain sensitive values, so it stays in a private storage account with RBAC.

---

## 2. Identity & least privilege

- **No long-lived credentials.** CI authenticates to Azure with OIDC; tokens are short-lived and
  scoped to the run. No service-principal client secret to leak or rotate.
- **Two distinct managed identities**, separated by blast radius:
  - `id-gh-oidc-newcode-cv` — used by CI to provision/deploy. Holds **Contributor on `rg-newcode-cv`**
    (it creates all the infra), AcrPush, and — only while a cluster exists — AKS RBAC Cluster Admin.
    This is least-privilege at the **resource-group blast radius**, not minimal permissions: a
    provisioning identity needs broad rights *within its RG*, and it holds none outside it.
  - `id-cv-app` — used by the running app to read its own secrets from Key Vault. Federated to the
    `cv-site` k8s ServiceAccount; it cannot deploy anything.
- **Key Vault in RBAC mode** — access is role assignments, not access policies, each scoped to the
  minimum: the **app** gets *Key Vault Secrets User* (read) and the **deployer** *Key Vault Secrets
  Officer* (write the tunnel token). Neither holds Key Vault Administrator.

---

## 3. Supply chain integrity

- **Image scanning**: Trivy on every build — `severity HIGH,CRITICAL`, `--ignore-unfixed`,
  `--exit-code 1` (a fixable high/critical fails the build).
- **Signing**: images **signed with cosign keyless** (OIDC/Sigstore, no private key stored) and
  **verified at deploy** before they reach the cluster.
- **Actions are pinned, not floating.** The two highest-blast-radius actions — `actions/checkout`
  (every job) and `hashicorp/setup-terraform` (the Azure-OIDC / state jobs) — are pinned by **commit
  SHA** with a `# vX.Y.Z` comment, which stops a hijacked upstream tag from injecting code into the
  highest-value paths. The rest are pinned to **release tags** (never `@main`/latest), each carrying
  `# TODO: ratchet to SHA`, and Renovate's `pinDigests: true` (`renovate.json`) opens PRs to convert
  them to digests. Result: the universal and the most-privileged actions are hard-pinned today; the
  remainder are tag-pinned and ratcheting to digests — not floating to `latest`.
- **Renovate** with `dependencyDashboardApproval: true` — dependency bumps are explicit, reviewed,
  not auto-merged blindly.
- **`actions/dependency-review`** on PRs flags vulnerable/incompatible-licensed deps before merge.

---

## 4. Network posture — no open ports

The cluster exposes **zero inbound ports to the internet**:

- **AKS API server is PRIVATE** — there is no public control-plane endpoint. CI reaches it only by
  joining the **tailnet** (`tag:ci`, ephemeral) and going through the **Tailscale Operator's
  API-server proxy**. The kubeconfig CI uses points at a tailnet address, not a public IP.
- **App ingress is outbound-only** via **Cloudflare Tunnel** (`cloudflared` dials out). No
  LoadBalancer Service, no public Ingress controller, no NodePort. The only "way in" is a tunnel the
  cluster itself opened.
- Combined with default-deny NetworkPolicy (below) — **enforced** by the Azure CNI Overlay + Cilium
  data plane (`terraform/aks.tf`), not merely declared — east-west traffic is also locked down.

This means port-scanning the cluster's public surface finds nothing, because there is no public surface.

---

## 5. Tenant isolation (confidential client data)

Agentic-AI for legal work implies multiple clients' confidential data on shared infrastructure. The
isolation model demonstrated here:

- **Namespace per tenant** — demo namespaces `tenant-a` and `tenant-b` (plus the app namespace `cv`).
- **Default-deny NetworkPolicy, enforced** — each tenant namespace gets an all-ingress/all-egress
  default-deny, made real by the Cilium data plane (§4, not just declared). A pod in `tenant-a` cannot
  reach a pod in `tenant-b` — no implicit cross-tenant traffic. The **scoped-allow** companion (open
  only required flows, e.g. DNS) is wired for the live app namespace `cv`
  (`helm/cv-site/templates/networkpolicy.yaml`); the tenant demo namespaces ship default-deny only.
- **Per-tenant Key Vault scoping & per-workload identity — the production pattern, not fanned out here.**
  In production each tenant's workload identity is federated to its own ServiceAccount and granted Key
  Vault RBAC on only its own secrets, so one tenant's compromise cannot read another's. This repo wires
  that identity path for the single app identity `id-cv-app` (Key Vault Secrets User on `kv-newcode-cv`);
  the per-tenant fan-out is the documented extension — consistent with §6 ("a demo of the pattern").

See the policies in [`helm/cv-site/templates/`](helm/cv-site/templates/) and the namespace/NetworkPolicy
definitions referenced by the chart.

---

## 6. What this is *not*

This is a portfolio. It is honest about scope: tenant namespaces are a **demo** of the isolation
pattern, not a multi-tenant SaaS control plane. The controls (OIDC, Key Vault + CSI, default-deny,
signed images, zero inbound) are real and applied to this repo's own deployment.

Deliberate demo trade-offs — each a one-line change for production, not an oversight:

- **Key Vault purge protection is off by default** (`var.kv_purge_protection`): it is irreversible and
  would lock the vault name for the soft-delete window after a teardown, which fights an ephemeral demo.
  Production sets it `true`. Soft delete itself is on (7-day retention).
- **Key Vault and ACR keep public endpoints**, gated by RBAC + AAD data-plane auth — the first apply
  runs from a laptop, CI writes the tunnel token from a hosted runner, and the CSI driver reads over the
  public endpoint. Private endpoints + VNet/private DNS are the production step, not built here.
- **ACR is Basic** (~$5/mo): image integrity comes from CI **Trivy + cosign**, not Premium-only ACR
  content trust / quarantine / geo-replication / Defender scanning.
