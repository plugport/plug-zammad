# plug-zammad

Self-hosted [Zammad](https://zammad.org/) helpdesk for Plug, deployed on Azure and exposed at **`operations.plugport.no`**.

## Status

🚧 Bootstrap phase. No code yet. See [DA Zammad project on Linear](https://linear.app/plugport/project/zammad-bf0065c652a2) for the work plan.

## Quick links

| | |
|---|---|
| Linear project | `Dataplattform` → `Zammad` (issue prefix `DA-`) |
| Production URL | `https://operations.plugport.no` |
| Azure tenant | Plug (subsidiary of Eviny) |
| Identity | Microsoft Entra ID (OIDC SSO) |
| DNS | Managed in [`evinyacp/eviny-dns`](https://github.com/evinyacp/eviny-dns) (Terraform) |
| Sister project (reference) | [`plugport/plug-analytics`](https://github.com/plugport/plug-analytics) |

## Conventions

This repo follows the same engineering process as `plug-analytics`:

- Conventional Commits, English on GitHub, Norwegian OK on Linear
- Every PR links to a Linear issue (`fixes DA-XX`)
- Squash-merge with `gh pr merge --squash --delete-branch`, never push to `main` directly
- No `Co-Authored-By` line in commits
- Same Claude Code plugin set (`superpowers`, `frontend-design`, `plug-brand-design`, `code-simplifier`, `claude-md-management`)

A complete `CLAUDE.md` will be added as the first PR. The prompt that bootstraps it lives in [`docs/claude-md-bootstrap.md`](docs/claude-md-bootstrap.md) — paste it into a Claude Code session in the repo root and follow along.
