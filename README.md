# plug-zammad

Self-hosted [Zammad](https://zammad.org/) helpdesk for Plug, deployed on Azure Container Apps. Will be exposed at **[operations.plugport.no](https://operations.plugport.no)** once DA-92 (custom domain) lands; currently reachable at the env default domain.

## Status

✅ Live on Container Apps as of 2026-05-20. Image is built and deployed end-to-end by the workflows in this repo. Next: custom domain (DA-92) → Entra SSO (DA-93). Active issue list: [Zammad project on Linear](https://linear.app/plugport/project/zammad-bf0065c652a2).

## Repo contents

| Path | What |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Engineering source of truth — architecture, commands, CI/CD, Azure resources, SSO, DNS, sizing, networking. |
| [`Dockerfile`](Dockerfile) | Thin wrapper around `ghcr.io/zammad/zammad:7.0.1-0045`. Per-role command is set per Container App in `evinyacp/az-0265-infra/infrastructure/apps.tf`. |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | Lint (yamllint, actionlint, gitleaks, commitlint) + image build on every PR and feature push. |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | OIDC-auth to Azure, build/push to `crprdzammad`, run init job, roll long-running apps, verify endpoint. Runs on push-to-main + `workflow_dispatch`. |
| [`docs/claude-md-bootstrap.md`](docs/claude-md-bootstrap.md) | The original bootstrap brief used to produce `CLAUDE.md`. |
| [`docs/features/`](docs/features/) | Feature-specific runbooks (SSO, DNS+TLS, storage, post-install, staging). |
| [`docs/superpowers/plans/`](docs/superpowers/plans/) | Implementation plans for non-trivial work, kept for traceability. |
| [`.env.example`](.env.example) | Documented Zammad environment variables (Docker variants). |

Terraform lives in [`evinyacp/az-0265-infra`](https://github.com/evinyacp/az-0265-infra) — see CLAUDE.md §14 for the hybrid-repo model.

## Local development

Mirrors the production stack via the upstream `zammad-docker-compose` repo.

```bash
git clone https://github.com/plugport/plug-zammad.git
cd plug-zammad
cp .env.example .env.local
docker compose up -d
open http://localhost:8080
```

Tail logs: `docker compose logs -f zammad-railsserver`. Rails console: `docker compose exec zammad-railsserver rails c`.

## Production access

`https://operations.plugport.no` — sign in with your Plug Entra ID account. Local password login is disabled; all access goes through SSO.

## Quick links

| | |
|---|---|
| Linear project | `Dataplattform` → `Zammad` (issue prefix `DA-`) |
| Production URL | https://operations.plugport.no |
| Azure tenant | Plug (subsidiary of Eviny) |
| Identity | Microsoft Entra ID (OIDC SSO) |
| DNS | Managed in [`evinyacp/eviny-dns`](https://github.com/evinyacp/eviny-dns) (Terraform) |

## Conventions

See `CLAUDE.md` §3 (Git) and §4 (Linear) for the full process. Highlights:

- Conventional Commits, English on GitHub, Norwegian allowed on Linear.
- Every PR links to a Linear issue with a magic word (`fixes DA-XX`).
- Squash-merge with `gh pr merge --squash --delete-branch`; never push to `main` directly.
- No `Co-Authored-By` line in commits.
