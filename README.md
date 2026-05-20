# plug-zammad

Self-hosted [Zammad](https://zammad.org/) helpdesk for Plug, deployed on Azure Container Apps and exposed at **[operations.plugport.no](https://operations.plugport.no)**. Authentication via Microsoft Entra ID (OIDC SSO).

## Status

🚧 Bootstrap phase. `CLAUDE.md` and supporting docs landed; Terraform and GitHub Actions workflows are next. See the [Zammad project on Linear](https://linear.app/plugport/project/zammad-bf0065c652a2) for the active issue list.

## Repo contents

| Path | What |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Engineering source of truth — architecture, commands, CI/CD, Azure resources, SSO, DNS, sizing, networking. |
| [`docs/claude-md-bootstrap.md`](docs/claude-md-bootstrap.md) | The original bootstrap brief used to produce `CLAUDE.md`. |
| [`docs/features/`](docs/features/) | Feature-specific runbooks (SSO, DNS+TLS, storage, post-install, staging). |
| [`.env.example`](.env.example) | Documented Zammad environment variables (Docker variants). |

Terraform and CI workflow files will land under `infra/` and `.github/workflows/` once the first deploy issue is picked up.

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
