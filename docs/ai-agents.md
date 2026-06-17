# AI agents — SDLC crew & nightly AI security review

This is the **lite** showcase of an AI-agent-driven SDLC, adapted for this repo. It is direct evidence
of AI-agent experience for an agentic-AI employer. It is also honest about scope: see
[**What is live here vs the full platform**](#what-is-live-here-vs-the-full-platform) at the bottom.

---

## The 6-role GitHub SDLC agent crew

A small crew of single-purpose agents drives work through GitHub, using **labels as a state machine** —
the issue/PR label *is* the state, so there is no hidden orchestration state and every transition is
auditable in the GitHub timeline.

| Role | Trigger (state) | Job | Hands off to |
|---|---|---|---|
| **Planner** | new Issue labeled `state:plan` | Turn the request into a concrete, scoped task plan + acceptance criteria | Coder |
| **Coder** | `state:code` | Implement the plan on a branch, open a PR | Reviewer |
| **Reviewer** | PR labeled `state:review` | Review diff for correctness + the repo conventions (minimal, facts-only, zero-secrets, SHA-pins) | Fix or Closer |
| **Fix** | `state:fix` | Apply review findings / fix failing checks | Reviewer (re-review) |
| **Closer** | `state:done` | Merge when green + approved, tidy up, write the manifest/changelog entry | — |
| **CI-poke** | checks stuck/failed | Nudge or re-run CI, surface the failure back as `state:fix` | Fix |

Properties that make it credible rather than a gimmick:
- **Deterministic gates are authoritative.** Agents propose; the CI gates (gitleaks, Trivy, cosign
  verify, `terraform validate`, `helm lint`, dependency-review) decide. An agent cannot merge red.
- **Label = state** means no separate database; GitHub is the source of truth and humans can intervene
  at any transition by moving a label.
- **Human approval is a hard stop.** Nothing merges or pushes to `main` without explicit human approval
  (the repo rule in [CLAUDE.md](../CLAUDE.md)).
- **Single responsibility per role** keeps each agent's prompt tight and its blast radius small.

---

## Nightly AI security review

A scheduled job that pairs **deterministic scanning** with **LLM triage** so the model adds judgment,
not noise:

1. **Deterministic pass** (the facts): run SAST + dependency/secret/image scanning on the current
   `main` — Trivy, gitleaks, dependency review. Pure tools, reproducible, no model.
2. **LLM triage** (the judgment): feed the raw findings to an LLM that deduplicates, ranks by real
   exploitability *in this repo's context*, drops false positives, and explains the *why* + a concrete
   remediation. The model never *invents* a vulnerability — it only triages what the deterministic pass
   surfaced.
3. **Output = a GitHub Issue**: a single, prioritized, human-readable security Issue (or none if clean),
   labeled for the SDLC crew (`state:plan`) so a real fix can flow through the same pipeline.

Why this split: deterministic tools are trustworthy but verbose and context-blind; an LLM is great at
context and prioritization but must not be the source of truth for *whether* something is a finding. The
LLM triages; the scanners detect.

---

## What is live here vs the full platform

**Wired live in this repo:**
- `.github/workflows/security-nightly.yml` — the deterministic-scan → LLM-triage → Issue flow above.
- **Renovate** (`dependencyDashboardApproval: true`) — dependency intelligence with human approval.
- The repo conventions the agents enforce (minimal, facts-only, zero-secrets, SHA-pinned actions) are
  real and gated in CI.

**Separate platform (not in this repo):**
- The full 6-role crew runs on a separate multi-agent SDLC platform I built and operate. This repo
  demonstrates the *methodology and the live security-nightly slice*; it does not vendor the whole platform.

This is deliberate: it shows I can both **operate** a real agentic platform and **right-size** what
belongs in a given repo.
