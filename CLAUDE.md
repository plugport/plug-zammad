# plug-zammad

Zammad on Azure Container Apps, exposed at `https://operations.plugport.no`. Internal support / ticketing tool for Plug.

---

## 1. Architecture

Zammad is a Rails application split into several long-running processes, a search engine, a cache, and a one-off init job. On Azure Container Apps each process runs as its own Container App in resource group `rg-plug-zammad` (subscription `sub-plug-zammad`). Image pin: `zammad/zammad:7.0.x` (latest stable 7.x). Architecture mirrors the upstream `zammad-docker-compose` services.

| Container App | Role | Replicas |
|---|---|---|
| `ca-plug-zammad-web` | Rails (Puma) + **nginx sidecar** (asset caching, attachment streaming, websocket upgrade routing) | 1–3 (HTTP-scaled) |
| `ca-plug-zammad-websocket` | WebSocket server for live agent UI | 1–2 |
| `ca-plug-zammad-worker` | Sidekiq background workers (mail, search indexing, webhooks) | 1–4 (queue-scaled) |
| `ca-plug-zammad-scheduler` | Recurring jobs (escalation timers, report generation) | 1 (singleton) |
| `ca-plug-zammad-opensearch` | OpenSearch single-node, internal-only ingress | 1 |
| `ca-plug-zammad-memcached` | Memcached — required by Zammad for containerised cache sharing (`MEMCACHE_SERVERS`) | 1 |
| `cajob-plug-zammad-init` | **Container Apps Job** — runs `rake db:migrate` on each version bump. Not long-running. | — |

Data plane:

| Resource | Service | Notes |
|---|---|---|
| `pg-plug-zammad` | Azure DB for PostgreSQL Flexible Server | App DB. 7-day PITR. Private endpoint. |
| `cache-plug-zammad` | Azure Cache for Redis (Basic C0/C1) | Sidekiq queue + Rails cache. TLS only. |
| `st-plug-zammad` | Storage Account → Azure Files (SMB share `zammad-storage`) | Attachments. Mounted into `ca-plug-zammad-{web,worker}` at `/opt/zammad/storage` via Container Apps `AzureFile` volume. GRS. Blob is **not** natively mountable on Container Apps — Files is the supported path. |
| `kv-plug-zammad` | Azure Key Vault | All long-lived secrets (DB password, Redis key, Entra client secret, SMTP creds). Referenced from Container Apps as secret refs. |
| `crplugport` | Azure Container Registry | Lives in a different subscription. `sp-plug-zammad` has `AcrPull` cross-sub. |

Traffic flow:

```
                                 operations.plugport.no
                                          │
                                          ▼
                          ┌──────────────────────────────┐
   Entra ID (OIDC)  ◄──── │  Container Apps ingress      │  TLS: managed cert
                          │  (HSTS, CSP, X-Frame-Options)│  (Path A — Let's Encrypt)
                          └─────────────┬────────────────┘
                                        │
   ╔════════════════════════════════════╪═══════════════════════════════════════╗
   ║ vnet-plug-zammad (workload-profile environment)                            ║
   ║                                    │                                       ║
   ║  ┌─────────────────────────┬───────┴────────┬──────────────────────────┐   ║
   ║  ▼                         ▼                ▼                          ▼   ║
   ║ ca-plug-zammad-web   ca-plug-zammad-       ca-plug-zammad-       ca-plug-  ║
   ║ (Rails + nginx       websocket             opensearch            zammad-   ║
   ║  sidecar)                                  (internal)            memcached ║
   ║   │  │  │  │              │                ▲                          ▲   ║
   ║   │  │  │  └─ AzureFile ──┼─► st-plug-zammad (zammad-storage share)   │   ║
   ║   │  │  └─ memcached ─────┼──────────────────────────────────────────►┤   ║
   ║   │  └─ redis ────────────┼─► cache-plug-zammad                       │   ║
   ║   └─ psql ─► [Private EP] ────► pg-plug-zammad (Flexible Server)      │   ║
   ║                            │                                          │   ║
   ║                            ▼                                          │   ║
   ║                 ca-plug-zammad-worker  +  ca-plug-zammad-scheduler ───┘   ║
   ║                            │                                              ║
   ║                  ┌─────────┴──────────┐                                   ║
   ║                  │ cajob-plug-zammad- │  (one-off; runs before each       ║
   ║                  │ init               │   long-running app update)        ║
   ║                  └────────────────────┘                                   ║
   ╚════════════════════════════════════════════════════════════════════════════╝
                                        │
                                        └──► SMTP (TBD — tracked in Linear, see §11)
```

## 2. Model

- Main agent (interactive): always `claude-opus-4-7`.
- Subagents (Agent tool):
  - `opus` → code review, debugging, novel reasoning, architecture decisions.
  - `sonnet` → mechanical execution from a precise prompt (plan execution, string substitutions, applying a diff).
  - `haiku` → search / read / summarize (`Explore` agent, grep-style lookups).
- Rule of thumb: if a junior dev could do it following your instructions literally, Sonnet is enough. If it needs judgment, Opus.

## 3. Git

- Do not add `Co-Authored-By` lines in commits.
- All text on GitHub in **English** (commits, comments, PRs, code, docs).
- Linear text may be **Norwegian**.
- Do not use git worktrees — work directly on the main repo.
- Conventional Commits (`feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `chore`, `perf`, `style`). First line < 72 chars. Imperative mood. Body answers *why*.
- Branch naming: `<username>/<issue-id>-<short-desc>` (e.g. `eyvind/da-12-entra-oidc`). Copy from Linear with `Cmd+Shift+.` if possible.
- One PR per logical unit of work. Amend + force-push for fixes, do not stack `fix(...)` commits.
- Every PR must link to a Linear issue with a magic word: `fixes DA-XX`, `closes DA-XX`, or `resolves DA-XX` on its own line in the body.
- PR workflow (single-developer):
  1. Branch from `main` → push → `gh pr create`
  2. `gh pr checks <n> --watch` — never merge with failing or pending checks
  3. `gh pr merge --squash --delete-branch`
- For changes to `evinyacp/eviny-dns`: requires code owner approval (`@evinyacp/az-eacp-owner`), always **Squash and merge** (not merge commit). `terraform apply` runs automatically after merge.

## 4. Linear

- **Workspace**: Plugport
- **Team**: `Dataplattform` — ID `ca2acb0a-804f-482d-af55-6afcd9bde58c`, key prefix `DA`
- **Project**: `Zammad` — ID `9706db9e-9f1c-43ae-9102-0b87f6b43ee5`, URL https://linear.app/plugport/project/zammad-bf0065c652a2

**Every issue created in this repo's context must live in the `Zammad` project under the `Dataplattform` team.** Do not file Zammad work in any other team or project.

Mandatory fields per issue:
- Type label (`Bug` / `Feature` / `Improvement` / `Refactor`)
- Impact label (`1 - High` / `2 - Medium` / `3 - Low`)
- Priority set (0=None, 1=Urgent, 2=High, 3=Medium, 4=Low)
- Project = `Zammad`

Statuses: `Triage → Refinement → Scoped → Icebox → Planned → In Progress → Paused → In Review → Done`.

Claude's responsibility:
- When starting work on an issue, **IMMEDIATELY** set its status to `In Progress`.
- Post progress comments at start, milestones, decisions, blockers, end of session (bullet format with ✅/⏳). The issue alone should tell a future session where things stand.
- PR/code ready → `In Review`. Complete → `Done`. Title/description outdated → update.

Sandbox / no-MCP fallback: use the REST/GraphQL API with `$LINEAR_API_KEY` from `.sandbox.env`. Always literal newlines in markdown, never escaped `\n`.

## 5. Commands

Local dev (docker compose, mirrors prod env vars):

```bash
docker compose up -d                       # spin up Zammad + Postgres + Redis + OpenSearch
docker compose logs -f zammad-web          # tail web logs
docker compose exec zammad-web rails c     # Rails console
docker compose down -v                     # tear down + drop volumes
```

Azure (against `sub-plug-zammad`):

```bash
az account set --subscription sub-plug-zammad
az containerapp list -g rg-plug-zammad -o table
az containerapp revision list -n ca-plug-zammad-web -g rg-plug-zammad -o table
az containerapp update -n ca-plug-zammad-web -g rg-plug-zammad --image crplugport.azurecr.io/zammad:<sha>
az containerapp revision activate -n ca-plug-zammad-web -g rg-plug-zammad --revision <previous>   # rollback
az containerapp logs show -n ca-plug-zammad-web -g rg-plug-zammad --follow

# Run the migrations job before bumping long-running apps
az containerapp job start -n cajob-plug-zammad-init -g rg-plug-zammad
```

Post-install / post-version-bump (Rails console via `exec`). See `docs/features/post-install.md` for the full runbook:

```bash
az containerapp exec -n ca-plug-zammad-web -g rg-plug-zammad \
  -- rails r "Setting.set('es_url', 'http://ca-plug-zammad-opensearch:9200')"
az containerapp exec -n ca-plug-zammad-web -g rg-plug-zammad \
  -- rails r "Setting.set('storage_provider', 'File')"
az containerapp exec -n ca-plug-zammad-web -g rg-plug-zammad \
  -- rails r "Setting.set('fqdn', 'operations.plugport.no')"
az containerapp exec -n ca-plug-zammad-web -g rg-plug-zammad \
  -- rails r "Setting.set('http_type', 'https')"
```

Postgres:

```bash
az postgres flexible-server connect -n pg-plug-zammad -u zammad -d zammad_production
```

PR shortcuts:

```bash
gh pr create --fill --web
gh pr checks --watch
gh pr merge --squash --delete-branch
```

## 6. Azure resources

All resources live in resource group `rg-plug-zammad` inside subscription `sub-plug-zammad`, region `West Europe`. ACR `crplugport` is **cross-subscription**; `sp-plug-zammad` is granted `AcrPull` on it.

| Resource | Role | FQDN / identifier | Produces (env var → secret ref) |
|---|---|---|---|
| `ca-plug-zammad-web` | Rails web | `ca-plug-zammad-web.<env>.azurecontainerapps.io` (also `operations.plugport.no` via custom domain) | — |
| `ca-plug-zammad-websocket` | WebSocket server | internal | — |
| `ca-plug-zammad-worker` | Sidekiq workers | internal | — |
| `ca-plug-zammad-scheduler` | Cron / scheduler | internal | — |
| `ca-plug-zammad-opensearch` | Search backend | `ca-plug-zammad-opensearch:9200` (internal) | URL configured at runtime via `Setting.set('es_url', ...)` — **not** an env var |
| `ca-plug-zammad-memcached` | Memcached | `ca-plug-zammad-memcached:11211` (internal) | `MEMCACHE_SERVERS=ca-plug-zammad-memcached:11211` |
| `cajob-plug-zammad-init` | Container Apps Job — migrations | — | invoked as `az containerapp job start` before each version bump |
| `vnet-plug-zammad` | VNet for Container Apps env + private endpoints | subnets: `snet-apps` (delegated to Container Apps), `snet-data` (Postgres PE) | Private DNS zone `privatelink.postgres.database.azure.com` linked |
| `pg-plug-zammad` | App database | `pg-plug-zammad.postgres.database.azure.com` (resolved via Private DNS to `snet-data`) | `POSTGRES_HOST`, `POSTGRES_PASS` ← `kv-plug-zammad/postgres-password` |
| `cache-plug-zammad` | Redis | `cache-plug-zammad.redis.cache.windows.net:6380` | `REDIS_URL` ← `kv-plug-zammad/redis-url` |
| `st-plug-zammad` | Azure Files (`zammad-storage` share) | `st-plug-zammad.file.core.windows.net` | mounted at `/opt/zammad/storage`; storage provider set at runtime via `Setting.set('storage_provider', 'File')` |
| `kv-plug-zammad` | Secrets store | `kv-plug-zammad.vault.azure.net` | all secret refs |
| `log-plug-zammad` | Log Analytics workspace | — | Container Apps + Postgres + Redis diagnostic logs |
| `sp-plug-zammad` | Service principal (CI/CD) | — | federated credentials only, no client secret |
| `crplugport` | ACR (cross-sub) | `crplugport.azurecr.io` | image registry |

## 7. CI/CD

GitHub Actions workflows live in `.github/workflows/`. Authenticate to Azure via **workload identity federation** with service principal `sp-plug-zammad` — no long-lived secrets in GitHub.

### Triggers

- `push` to feature branches → lint + test + container build (no deploy).
- `pull_request` to `main` → same checks + `az containerapp update --dry-run` output as PR comment.
- `push` to `main` → deploy to production.
- Manual dispatch → re-deploy current `main` (rollback safety net).

### Stages

1. **Validate** — `yamllint`, `terraform fmt -check`, `helm lint` (if any), `gitleaks`, Conventional Commits lint.
2. **Build** — container image built from `zammad/zammad:7.0.x` (pinned to a specific patch) + Plug overlays, tagged with `${{ github.sha }}` and pushed to `crplugport.azurecr.io/zammad:<sha>`.
3. **Test** — health-check the built image (`docker run --rm <img> rails runner 'puts "ok"'`), run config-validation scripts.
4. **Deploy** — strict order:
   1. `az containerapp job start -n cajob-plug-zammad-init -g rg-plug-zammad --image crplugport.azurecr.io/zammad:<sha>` and wait for it to succeed (runs `rake db:migrate`). Long-running apps must **not** start on the new image until migrations finish.
   2. `az containerapp update -n ca-plug-zammad-web -g rg-plug-zammad --image crplugport.azurecr.io/zammad:<sha>`. Wait for new revision to become healthy.
   3. Repeat the update for `websocket`, `worker`, `scheduler`, `memcached` (memcached only on infra changes).
5. **Verify** — hit `https://operations.plugport.no/api/v1/users/me` with a service-account token → expect HTTP 200. Hit `/` → expect HTTP 200 + expected HTML title.

### Secrets in CI

- Workload identity federation between GitHub Actions and Entra ID. `sp-plug-zammad` is scoped to `rg-plug-zammad` only (Contributor) + `AcrPush` on `crplugport`.
- Container Apps reads runtime secrets from `kv-plug-zammad` via secret references — never from GitHub Actions.

### Log monitoring policy

After every push to `main`, check the CI/CD workflow logs for warnings and deprecation notices — not just pass/fail. Proactively flag issues and create Linear issues in the `Zammad` project for upcoming breaking changes. Examples:

- Deprecation warnings from `az` CLI, `gh`, `actions/*` versions
- Zammad upstream deprecation notes in container build logs
- Security advisories in `audit-ci` output
- Performance regressions in build/deploy duration

### Rollback

- Container Apps revisions are immutable: `az containerapp revision activate -n <app> -g rg-plug-zammad --revision <previous>`.
- For Zammad **version upgrades**, the rollback path is not the revision — it is the Postgres PITR + ephemeral staging dry-run. See `docs/features/staging.md`.

## 8. SSO (Entra ID)

Zammad requires Entra ID login for all users. OIDC via Zammad's built-in Microsoft (Office 365) v2 strategy.

### App Registration

Created in the Plug Entra tenant:

- **Name**: `Plug Zammad`
- **Account types**: Accounts in this organizational directory only
- **Redirect URI (Web)**: `https://operations.plugport.no/auth/microsoft_office365_v2/callback` — this is Zammad's hard-coded OmniAuth callback path; do not change.

Captured values:
- Application (client) ID — public, can be referenced in code/docs.
- Directory (tenant) ID — public.

### Client secret

- Created with 24-month expiry. Linear reminder issue in `Zammad` project, due two weeks before expiry.
- Stored in Key Vault as `entra-zammad-client-secret`.
- **Not** surfaced as a runtime env var. Zammad's Microsoft (Office 365) v2 strategy is configured in the admin UI (Settings → Security → Third Party Applications). At initial setup, retrieve the secret from Key Vault and paste it into the admin form. Rotation = retrieve new secret → paste again.

### API permissions

Microsoft Graph delegated:

| Permission | Purpose |
|---|---|
| `openid` | OIDC sign-in |
| `profile` | Name claim |
| `email` | Email claim (Zammad user identifier) |
| `User.Read` | Read signed-in user's basic profile |

Admin consent granted for the tenant.

### Optional: group claim

To map AD groups → Zammad roles automatically, enable groups claim (Security groups → ID + access token). Mapping handled either by a Ruby post-login hook (path documented in `docs/features/sso-entra.md`) or kept manual in Zammad admin.

### Zammad configuration

In Zammad admin → Settings → Security → Third Party Applications → Microsoft (Office 365):

- Paste App ID, App Secret, Tenant ID
- Enable automatic account link on initial sign-in, matched on email
- Once SSO works end-to-end: Admin → Settings → Security → Base → "Third-party login only" to disable local password form

### Full walkthrough

See `docs/features/sso-entra.md`.

## 9. DNS + TLS

**Path A** — Container Apps managed certificate (Let's Encrypt). Path B (Front Door + WAF) is tracked as a future option, see `docs/features/dns-tls.md`.

### DNS

`plugport.no` lives in `evinyacp/eviny-dns` (Terraform). To add `operations.plugport.no`:

1. Branch `eviny-dns` from `main`.
2. Add `operations` CNAME → `ca-plug-zammad-web.<env>.azurecontainerapps.io` and `asuid.operations` TXT (validation token from Azure).
3. PR → owner approval from `@evinyacp/az-eacp-owner` → **Squash and merge**. `terraform apply` runs post-merge.
4. Verify: `dig +short operations.plugport.no`.

### TLS

1. Azure Portal → `ca-plug-zammad-web` → Custom domains → Add custom domain → `operations.plugport.no`.
2. Validation via the `asuid.operations` TXT added above.
3. Select **Managed certificate** → Azure issues Let's Encrypt cert and rotates automatically.
4. Bind the domain.

### Verification commands

```bash
dig +short operations.plugport.no
curl -Iv https://operations.plugport.no
```

Expect HTTP 200 and a Let's Encrypt-issued certificate.

### Security headers

Zammad sends:

- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Frame-Options: DENY`
- `Content-Security-Policy` — Zammad default; document any overrides in `docs/features/dns-tls.md`.

## 10. Backups + monitoring

### Backups

- **Postgres**: 7-day point-in-time restore on Flexible Server. Geo-redundant backup storage.
- **Attachments** (`st-plug-zammad` Azure Files share): GRS replication (West Europe → North Europe). File-share-level snapshot daily, retained 14 days.
- **Target**: RTO 4h / RPO 1h.

### Monitoring

- Container Apps + Postgres + Redis diagnostic logs → `log-plug-zammad` (Log Analytics workspace).
- Alerts (Action Group → Plug oncall):
  - Container App health probe failures > 2 in 5 min
  - Postgres CPU > 80% for 10 min
  - Redis cache evictions > threshold
  - SSO sign-in failure rate spike
- Dashboards: Azure Workbook `wb-plug-zammad-overview` (latency, error rate, queue depth).

## 11. Staging strategy

Hybrid model:

- **Daily ops** — config changes, env-var tweaks, Plug overlays at the *same* Zammad version: use Container Apps revisions for blue/green. New revision takes 0% traffic by default; promote via `--traffic-weight latest=100`.
- **Zammad version bumps** (any 7.x.y → 7.x.z with `db:migrate`, or 7 → 8): spin up ephemeral staging via Terraform `module.staging` — restores latest Postgres PITR snapshot into `pg-plug-zammad-staging`, brings up `ca-plug-zammad-staging`, runs smoke tests, tears down.

Full runbook: `docs/features/staging.md`.

SMTP for outbound mail is **TBD** — tracked as Linear issue under the `Zammad` project. Default `.env.example` documents the env-var contract; production will not deliver mail until the decision is made and secrets are populated.

## 12. Sizing baseline

Initial Container App sizing for a ~40-agent install. Re-tune after the first month of telemetry.

| Container App | CPU | Memory | Replicas | Notes |
|---|---|---|---|---|
| `ca-plug-zammad-web` | 2.0 | 4 Gi | 1–3 (HTTP-scaled) | Rails + nginx sidecar |
| `ca-plug-zammad-websocket` | 1.0 | 2 Gi | 1–2 | |
| `ca-plug-zammad-worker` | 2.0 | 4 Gi | 1–4 (queue-scaled) | Sidekiq spawns several processes per replica |
| `ca-plug-zammad-scheduler` | 0.5 | 1 Gi | 1 (singleton) | |
| `ca-plug-zammad-opensearch` | 2.0 | 4 Gi | 1 | Single-node; persistent storage on attached volume |
| `ca-plug-zammad-memcached` | 0.25 | 0.5 Gi | 1 | Stateless cache |
| `cajob-plug-zammad-init` | 1.0 | 2 Gi | job | Migrations only |

Total baseline ≈ **7.75 CPU / 15.5 Gi**. Zammad's documented minimum is 2 CPU + 6 GB for the app and an additional 4 GB for Elasticsearch on the same host — this layout splits those budgets across dedicated apps for blast-radius isolation.

## 13. Networking

Container Apps must reach Postgres Flexible Server over a private endpoint, so the environment runs in a custom VNet (workload-profile environment is required for VNet + private endpoint support).

- **VNet**: `vnet-plug-zammad` (`10.40.0.0/16`).
  - `snet-apps` (`/23`, delegated to `Microsoft.App/environments`) — Container Apps environment subnet.
  - `snet-data` (`/27`) — Private Endpoints for `pg-plug-zammad`.
- **Private DNS zones** linked to the VNet:
  - `privatelink.postgres.database.azure.com` — resolves `pg-plug-zammad.postgres.database.azure.com` to the PE in `snet-data`.
- **Egress**: outbound NAT via a Container Apps environment outbound IP. Use that IP for any allowlisting (M365 SMTP relay, external webhooks).
- **Reference**: [Microsoft Learn — Use private endpoints with Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint).

## 14. Plugins + Available skills

Required Claude Code plugins:

```
/plugin install superpowers
/plugin install claude-md-management@claude-code-plugins
```

Optional:

```
/plugin install code-simplifier@claude-code-plugins
```

`plug-brand-design` skill is **not** used in this repo. Zammad has its own theming system.

## 15. Mandatory use of skills + Recommended workflow

If there is greater than 1% chance a skill applies, USE it — before any response, including clarifying questions.

Priority order:
1. **Process skills first** (`superpowers:brainstorming`, `superpowers:systematic-debugging`) — these determine *how* to approach work.
2. **Implementation skills** (`test-driven-development`, `executing-plans`, `subagent-driven-development`, `verification-before-completion`).

These thoughts mean STOP and check skills anyway:
- "This is just a simple question"
- "I need more context first"
- "This skill is overkill"

### Recommended workflow

`brainstorming` → `writing-plans` → `executing-plans` / `subagent-driven-development` → `test-driven-development` → `verification-before-completion` → `requesting-code-review` → `finishing-a-development-branch`.
