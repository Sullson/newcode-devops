# Repo working rules

These rules govern any change to this repo, by a human or an AI assistant. They exist because the repo
is a public CV — sloppiness here is visible to the target employer.

## Core conventions

- **Minimal, no overengineering.** Write the least code that is correct and production-credible. No
  speculative features, no boilerplate bloat. A short comment only where it explains *why* a non-obvious
  choice exists — never to narrate *what* the code does.
- **Facts only in docs.** Do not invent the author's bio, years of experience, employers, photo, or
  contact details. Mark every unknown personal fact with a clear placeholder, e.g.
  `{{TODO: real years of Azure experience}}`. You *may* state as fact anything true about this repo's
  own architecture — it is real and built here.
- **Zero secret values.** Never write a real key, token, password, client-id, tenant-id, or
  subscription-id. Use `${{ secrets.* }}`, Terraform variables, or the literal `REPLACE_ME`. A leaked
  value is a project-level failure. gitleaks gates this pre-commit and in CI.
- **Pin versions.** Pin tool/provider/action versions. GitHub Actions are pinned by commit SHA with a
  `# vX.Y.Z` comment; for actions without a known-good SHA, pin `@<tag>` and add
  `# TODO: ratchet to SHA (Renovate)`.
- **English.** The site and target company operate in English; all comments and docs are in English.

## Git identity & commits

- Commit author identity: **`Sullson`**. The email is configured locally and is never written into this public repo.
- **Never** add Claude / Anthropic as a co-author. Never add a `Co-Authored-By` trailer referencing an
  AI assistant. No "Generated with" links.
- **Never commit or push without explicit approval.** Make the change, show it, wait for the go-ahead.
- A question ("can we…?", "how would you…?") is **not** an instruction to do it. Answer first; act only
  when told to act.

## AI-assisted SDLC methodology (this is also the proof of "AI coding tools" skill)

This repo is built with an AI-assisted workflow, used deliberately and visibly so the methodology
itself is evidence for an agentic-AI employer:

- **Spec-first.** Each component starts from a tight written contract (shared constants, file list,
  constraints). The assistant builds to the contract; it does not improvise architecture.
- **Small, reviewable units.** Work is decomposed into independent components, each producing a small
  set of files with a manifest, so every change is human-reviewable.
- **Deterministic gates over vibes.** Correctness is enforced by tools, not trust: gitleaks, Trivy,
  cosign verify, `terraform validate`, `helm lint`, dependency-review. The AI proposes; the gates dispose.
- **Facts-vs-placeholders discipline.** The assistant is explicitly forbidden from inventing personal
  facts and must emit `{{TODO}}` markers instead — keeping the public artifact honest.
- **Agentic SDLC, separately.** A fuller multi-agent GitHub SDLC (role-based crew + nightly AI security
  review) is documented in [`docs/ai-agents.md`](docs/ai-agents.md); what is *wired live in this repo*
  vs what exists as a separate platform is stated there honestly.

When acting as an AI assistant on this repo: follow the conventions above, prefer the smallest correct
change, and surface uncertainty as a `{{TODO}}` rather than a confident guess.
