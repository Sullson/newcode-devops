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
  - `id-gh-oidc-newcode-cv` — used by CI to provision/deploy. Scoped to `rg-newcode-cv`.
  - `id-cv-app` — used by the running app to read its own secrets from Key Vault. Federated to the
    `cv-site` k8s ServiceAccount; it cannot deploy anything.
- **Key Vault in RBAC mode** — access is role assignments, not access policies; each identity gets the
  minimum (the app gets *get/list secrets* on only what it needs).

---

## 3. Supply chain integrity

- **Image scanning**: Trivy on every build — `severity HIGH,CRITICAL`, `--ignore-unfixed`,
  `--exit-code 1` (a fixable high/critical fails the build).
- **Signing**: images **signed with cosign keyless** (OIDC/Sigstore, no private key stored) and
  **verified at deploy** before they reach the cluster.
- **Actions pinned by commit SHA** with a `# vX.Y.Z` comment — not floating tags. Stops a hijacked
  upstream tag from injecting code into CI.
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
- Combined with default-deny NetworkPolicy (below), east-west traffic is also locked down.

This means port-scanning the cluster's public surface finds nothing, because there is no public surface.

---

## 5. Tenant isolation (confidential client data)

Agentic-AI for legal work implies multiple clients' confidential data on shared infrastructure. The
isolation model demonstrated here:

- **Namespace per tenant** — demo namespaces `tenant-a` and `tenant-b` (plus the app namespace `cv`).
- **Default-deny NetworkPolicy** in each tenant namespace: all ingress *and* egress denied by default,
  then a narrow scoped-allow policy opens only required flows. A pod in `tenant-a` cannot reach a pod
  in `tenant-b` — no implicit cross-tenant traffic.
- **Per-tenant Key Vault scoping** — each tenant's secrets are scoped so a tenant's workload identity
  can read only its own Key Vault entries. One tenant's compromise does not expose another's data.
- **Workload Identity per workload** — no shared cluster-wide credential; each SA gets its own
  federated identity with least privilege.

See the policies in [`helm/cv-site/templates/`](helm/cv-site/templates/) and the namespace/NetworkPolicy
definitions referenced by the chart.

---

## 6. What this is *not*

This is a portfolio. It is honest about scope: tenant namespaces are a **demo** of the isolation
pattern, not a multi-tenant SaaS control plane. The controls (OIDC, Key Vault + CSI, default-deny,
signed images, zero inbound) are real and applied to this repo's own deployment.
