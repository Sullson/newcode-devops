# Evidence

This directory holds **timestamped proof that the on-demand AKS deploy really works**. The cluster is
not running 24/7 (see the cost rationale in [../architecture.md](../architecture.md)) - so instead of a
live link, the proof of a real deploy is captured here and committed.

## What lands here

The `deploy-aks` workflow ([`.github/workflows/deploy-aks.yml`](../../.github/workflows/deploy-aks.yml))
stands up the cluster, deploys the `cv-site` Helm release into namespace `cv` over the Tailscale API
proxy, verifies it, commits one proof file here, and then **destroys the cluster**.

Each run writes a single combined markdown file `aks-proof-<timestamp>.md` (timestamp is UTC ISO-8601,
e.g. `aks-proof-2026-06-17T05-12-44Z.md`). The name is unique per run, so the directory is an
append-only audit trail. Each file contains:

| Section | What it proves |
|---|---|
| Header | commit + image tag, app URL, `/healthz` HTTP status, and that teardown runs in the final step |
| `cosign verify` | the image's keyless signature was verified **before** deploy (supply-chain gate) |
| `kubectl get pods,svc -n cv` | workloads scheduled and healthy |
| `helm status cv-site` | the release deployed successfully |

The cluster teardown runs in the workflow's final `always()` step, after the proof is committed - so it
executes on every run (success or failure) and is visible in the run logs. It is **not** a full
`terraform destroy`: it is `terraform apply -var deploy_aks=false`, which removes only the ephemeral AKS
cluster and its cluster-bound dependents. The always-on front (SWA, DNS, ACR, Key Vault, identities,
monitoring, the Cloudflare tunnel) is persistent and is deliberately left running.

## Why evidence instead of a permanent link

- The **always-on** CV lives at `newcode.msulawiak.pl` (Azure Static Web Apps, free tier) - that is the
  durable surface.
- The **AKS** path exists to prove the full platform end-to-end, not to serve traffic. Running it idle
  would cost money and keep infrastructure standing for no reason. The captured evidence + clean teardown
  is itself the demonstration: reproducible-from-zero infrastructure, not pets.

> No secret values appear in any evidence file. Outputs are sanitized; tokens, client-ids, and IPs of
> private resources are never captured here.
