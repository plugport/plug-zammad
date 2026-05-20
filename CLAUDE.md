# plug-zammad

Zammad on Azure Container Apps, exposed at `https://operations.plugport.no`. Internal support / ticketing tool for Plug.

---

## 0. Live status (snapshot 2026-05-20)

A truthful snapshot of where the deployment actually stands today, so a new session can pick up without guessing. Update this section as facts move.

### Identities and locations

| Item | Value |
|---|---|
| Workload subscription | `az-0265-online-plugas-prd-prd-ammad` (ID `7ffb20c8-2855-49e4-99f0-23ea9bcb706e`; "ammad" typo is locked by Eviny ACP, ignore — use the ID) |
| Region | `norwayeast` (migrated from `westeurope` after AKS capacity error in WEU on 2026-05-20) |
| Resource group | `rg-prd-zammad` |
| AAD owners group | `az-0265-owners` (Eyvind is a member) |
| Service principal | `az-0265-sp` (app ID `a7141a4c-8174-491f-960b-a9b4eedac81a`, OIDC pre-wired by ACP) |
| Tenant | `eviny.no` (ID `12f1bdca-9eec-45f6-a63e-2061b957e8ee`) |

### Repos

| Repo | Owns |
|---|---|
| `plugport/plug-zammad` (this repo) | Dockerfile, CI/CD, app overlays, all docs |
| `evinyacp/az-0265-infra` | All Terraform (flat layout under `infrastructure/`) |
| `evinyacp/eviny-dns` | DNS for `plugport.no` (PRs need `@evinyacp/az-eacp-owner` review) |

### Live Azure resources

| Resource | Status |
|---|---|
| `vnet-prd-zammad` (`10.40.0.0/16`) + `snet-apps`, `snet-data`, 2 NSGs | ✅ Live |
| `pg-prd-zammad-ne` (Postgres FS 16, GP_Standard_D2ds_v4) | ✅ Live with PE |
| `cache-prd-zammad-ne` (Redis Standard C0) | ✅ Live with PE |
| `stprdzammadne` (Storage Account + file share `zammad-storage`) | ✅ Live with PE |
| `kv-prd-zammad-ne` (Key Vault Standard, RBAC) | ✅ Live with PE; 4 secrets via ARM-plane |
| `mi-prd-zammad-apps` (user-assigned MI) | ✅ Live, has Secrets User on KV |
| `log-prd-zammad` (Log Analytics) | ✅ Live |
| `cae-prd-zammad` (Container Apps env) | ✅ Live; default domain `orangemoss-71bfd191.norwayeast.azurecontainerapps.io` |
| 6 Container Apps + `cajob-prd-zammad-init` | ✅ Live, all on placeholder helloworld image |
| 5 Private DNS zones + VNet-links | ✅ Live |
| `crprdzammad` ACR (Standard tier, `crprdzammad.azurecr.io`) | ✅ Live; `az-0265-sp` has AcrPush, `mi-prd-zammad-apps` has AcrPull |
| Federated credentials on `az-0265-sp` | ✅ Live for `evinyacp/az-0265-infra` (ACP-original) and `plugport/plug-zammad` (added 2026-05-20: subjects `:ref:refs/heads/main` and `:pull_request`) |

### Bootstrap-prompt corrections (for future reference)

The original bootstrap prompt in `docs/claude-md-bootstrap.md` named several things that turned out to be fictional or wrong once ACP delivered the real environment. The corrections, all already applied here:

| Bootstrap name | Real value |
|---|---|
| `sub-plug-zammad` | `az-0265-online-plugas-prd-prd-ammad` (ACP-issued) |
| `sp-plug-zammad` | `az-0265-sp` (ACP-pre-wired with OIDC) |
| `crplugport` ACR | Not a real registry. Plug's pattern is one ACR per workload (see `crpluganalytics` in `plug-analytics`). We use `crprdzammad` in the workload sub. |
| `westeurope` region | Migrated to `norwayeast` after AKS capacity error. Norway East is also Eviny ACP default. |

### Open infra constraints (sticky)

- `az-0265-sp` lacks `Microsoft.Network/ddosProtectionPlans/join/action` on the centralised `eacp-ddos-norwayeast` plan. The VNet was therefore created by **local apply as Eyvind** (user has MG-inherited join). Subsequent applies work because `ignore_changes = [ddos_protection_plan]` keeps Terraform from touching that attribute. See DA-95.
- `CI - Terraform Plan` workflow in `evinyacp/az-0265-infra` returns `startup_failure` on every PR-time trigger. `CD - Terraform Apply` on push-to-main works. We post `terraform plan` output as a PR comment manually; see `docs/features/infra-runbook.md`. See DA-95.
- KV `public_network_access_enabled = false`. `azurerm_key_vault_secret` (data plane) is unreachable from CI runners and dev laptops. Secrets are written via `azapi_resource` against the ARM control plane (DELETE via that endpoint is not supported — use `terraform state rm` for renames). See DA-95.
- Postgres FS soft-delete is 7 days; Storage account soft-delete ~14 days; Key Vault purge-protected with 90-day soft-delete. The four `-ne`-suffixed resources exist because their pre-migration WEU siblings still hold the names.

### Linear

- Workspace `Plugport`, team `Dataplattform` (ID `ca2acb0a-804f-482d-af55-6afcd9bde58c`), project `Zammad` (ID `9706db9e-9f1c-43ae-9102-0b87f6b43ee5`).
- Active workflow:

```
DA-84 ACP order               ✅ Done
DA-86 Terraform network       ✅ Done
DA-87 Identity supplement     ✅ Done (MI, federated cred, AcrPush all in place)
DA-88 Terraform data          ✅ Done
DA-89 Terraform apps          ✅ Done (resources scaffolded — but containers are still aci-helloworld placeholders, see DA-96)
DA-90 Dockerfile + CI         🟣 In Review (PR #9 merged: Dockerfile + ci.yml + deploy.yml; DoD#2 blocked by DA-96)
DA-96 apps.tf container state 🟡 In Refinement (command/env/secrets/volumes — blocks DA-90 DoD#2, DA-92, DA-93)
DA-91 Azure OpenAI            🟡 In Refinement (blocked by DA-90)
DA-92 Custom domain + TLS     🟡 In Refinement (blocked by DA-96 → DA-90)
DA-93 SSO go-live             🟡 In Refinement (blocked by DA-92)
DA-85 SMTP decision           🟡 In Refinement
DA-95 Eviny escalations       🔵 In Progress (samleboks)
```

### What's next

DA-90 app-repo files merged in PR #9 (`Dockerfile` pins `ghcr.io/zammad/zammad:7.0.1-0045`; `ci.yml`, `deploy.yml`, `.yamllint`, `.github/commitlint.config.cjs`, `.dockerignore`). CI is green. First deploy on `main` revealed that the Container Apps are bare `aci-helloworld` placeholders (`command: null, env: null, secrets: []`) — the Zammad image was started with no command and the init job hung on the default-CMD `zammad-railsserver` until the 20-min poll timed out.

That makes the next step **DA-96** in `evinyacp/az-0265-infra/infrastructure/apps.tf`: per-app `command` + `args` (e.g. `zammad-init`, `zammad-railsserver`, `zammad-scheduler`, `zammad-websocket`, `zammad-nginx` sidecar), the env-var → KV secret-ref wiring from §6, the `/opt/zammad/storage` Azure Files mount, and `mi-prd-zammad-apps` bound as the AcrPull + KV-secrets identity on each app.

Once DA-96 lands, re-run `deploy.yml` via `workflow_dispatch` against `main`. Expected: init job reaches `Succeeded`, the four long-running apps roll to `crprdzammad.azurecr.io/zammad:<sha>`, and `curl -I https://ca-prd-zammad-web.orangemoss-71bfd191.norwayeast.azurecontainerapps.io/` returns 200/302. That closes DA-90 DoD#2 and unblocks DA-92 (custom domain) → DA-93 (SSO).

---

## 1. Architecture

Zammad is a Rails application split into several long-running processes, a search engine, a cache, and a one-off init job. On Azure Container Apps each process runs as its own Container App in resource group `rg-prd-zammad` (subscription `az-0265-online-plugas-prd-prd-ammad` — name set by Eviny ACP; the typo `ammad` is locked, use the subscription **ID** as source of truth in scripts). Image pin: `ghcr.io/zammad/zammad:7.0.1-0045` (upstream-canonical via `IMAGE_REPO` default in `zammad/zammad-docker-compose/.env.dist`; Docker Hub `zammad/zammad` mirrors the same content). Architecture mirrors the upstream `zammad-docker-compose` services.

| Container App | Role | Replicas |
|---|---|---|
| `ca-prd-zammad-web` | Rails (Puma) + **nginx sidecar** (asset caching, attachment streaming, websocket upgrade routing) | 1–3 (HTTP-scaled) |
| `ca-prd-zammad-websocket` | WebSocket server for live agent UI | 1–2 |
| `ca-prd-zammad-worker` | Sidekiq background workers (mail, search indexing, webhooks) | 1–4 (queue-scaled) |
| `ca-prd-zammad-scheduler` | Recurring jobs (escalation timers, report generation) | 1 (singleton) |
| `ca-prd-zammad-opensearch` | OpenSearch single-node, internal-only ingress | 1 |
| `ca-prd-zammad-memcached` | Memcached — required by Zammad for containerised cache sharing (`MEMCACHE_SERVERS`) | 1 |
| `cajob-prd-zammad-init` | **Container Apps Job** — runs `rake db:migrate` on each version bump. Not long-running. | — |

Data plane:

| Resource | Service | Notes |
|---|---|---|
| `pg-prd-zammad-ne` | Azure DB for PostgreSQL Flexible Server | App DB. 7-day PITR. Private endpoint. |
| `cache-prd-zammad-ne` | Azure Cache for Redis (Basic C0/C1) | Sidekiq queue + Rails cache. TLS only. |
| `stprdzammadne` | Storage Account → Azure Files (SMB share `zammad-storage`) | Attachments. Mounted into `ca-prd-zammad-{web,worker}` at `/opt/zammad/storage` via Container Apps `AzureFile` volume. GRS. Blob is **not** natively mountable on Container Apps — Files is the supported path. |
| `kv-prd-zammad-ne` | Azure Key Vault | All long-lived secrets (DB password, Redis key, Entra client secret, SMTP creds). Referenced from Container Apps as secret refs. |
| `crprdzammad` | Azure Container Registry | Lives in **this** subscription (own ACR per workload, same pattern as `crpluganalytics`). `az-0265-sp` gets `AcrPush` + `AcrPull` via Terraform. |

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
   ╔══════════════════════════════════════╪═══════════════════════════════════════╗
   ║ vnet-prd-zammad (workload-profile Container Apps environment)               ║
   ║                                      │                                      ║
   ║   ┌──────────────┬──────────────┬────┴─────────┬──────────────┐             ║
   ║   ▼              ▼              ▼              ▼              ▼             ║
   ║  ca-prd-     ca-prd-zammad- ca-prd-zammad- ca-prd-zammad- ca-prd-zammad-    ║
   ║  zammad-web  websocket      opensearch     memcached      worker/scheduler  ║
   ║  (+nginx)                   (internal)                                      ║
   ║   │  │  │  │      │              ▲              ▲              │            ║
   ║   │  │  │  └── AzureFile mount ──┼──► stprdzammadne (zammad-storage share)    ║
   ║   │  │  └── memcached ───────────┼──────────────┘              │            ║
   ║   │  └── redis ──────────────────┼──► cache-prd-zammad-ne                      ║
   ║   └── psql ──► [Private EP] ─────┼──► pg-prd-zammad-ne (Flexible Server)       ║
   ║                                  │                              │            ║
   ║                                  ▼                              │            ║
   ║                            cajob-prd-zammad-init (one-off, runs before      ║
   ║                            long-running app updates / version bumps)        ║
   ╚══════════════════════════════════════════════════════════════════════════════╝
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

Azure (against `az-0265-online-plugas-prd-prd-ammad`):

```bash
az account set --subscription az-0265-online-plugas-prd-prd-ammad
az containerapp list -g rg-prd-zammad -o table
az containerapp revision list -n ca-prd-zammad-web -g rg-prd-zammad -o table
az containerapp update -n ca-prd-zammad-web -g rg-prd-zammad --image crprdzammad.azurecr.io/zammad:<sha>
az containerapp revision activate -n ca-prd-zammad-web -g rg-prd-zammad --revision <previous>   # rollback
az containerapp logs show -n ca-prd-zammad-web -g rg-prd-zammad --follow

# Run the migrations job before bumping long-running apps
az containerapp job start -n cajob-prd-zammad-init -g rg-prd-zammad
```

Post-install / post-version-bump (Rails console via `exec`). See `docs/features/post-install.md` for the full runbook:

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('es_url', 'http://ca-prd-zammad-opensearch:9200')"
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('storage_provider', 'File')"
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('fqdn', 'operations.plugport.no')"
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('http_type', 'https')"
```

Postgres:

```bash
az postgres flexible-server connect -n pg-prd-zammad-ne -u zammad -d zammad_production
```

PR shortcuts:

```bash
gh pr create --fill --web
gh pr checks --watch
gh pr merge --squash --delete-branch
```

## 6. Azure resources

All resources live in resource group `rg-prd-zammad` inside subscription `az-0265-online-plugas-prd-prd-ammad` (Eviny ACP-managed; display-name typo locked — use subscription ID in CI/CD), region `Norway East`. AAD owners group: `az-0265-owners`. Service principal: `az-0265-sp` (pre-wired with OIDC by ACP). ACR `crprdzammad` lives in the same subscription; `az-0265-sp` gets `AcrPush` (CI build) and `AcrPull` (deploys) via Terraform.

| Resource | Role | FQDN / identifier | Produces (env var → secret ref) |
|---|---|---|---|
| `ca-prd-zammad-web` | Rails web | `ca-prd-zammad-web.<env>.azurecontainerapps.io` where `<env>` is `cae-prd-zammad`'s default domain (currently `orangemoss-71bfd191.norwayeast`). Also `operations.plugport.no` via custom domain. | — |
| `ca-prd-zammad-websocket` | WebSocket server | internal | — |
| `ca-prd-zammad-worker` | Sidekiq workers | internal | — |
| `ca-prd-zammad-scheduler` | Cron / scheduler | internal | — |
| `ca-prd-zammad-opensearch` | Search backend | `ca-prd-zammad-opensearch:9200` (internal) | URL configured at runtime via `Setting.set('es_url', ...)` — **not** an env var |
| `ca-prd-zammad-memcached` | Memcached | `ca-prd-zammad-memcached:11211` (internal) | `MEMCACHE_SERVERS=ca-prd-zammad-memcached:11211` |
| `cajob-prd-zammad-init` | Container Apps Job — migrations | — | invoked as `az containerapp job start` before each version bump |
| `vnet-prd-zammad` | VNet for Container Apps env + private endpoints | subnets: `snet-apps` (delegated to Container Apps), `snet-data` (Postgres PE) | Private DNS zone `privatelink.postgres.database.azure.com` linked |
| `pg-prd-zammad-ne` | App database | `pg-prd-zammad-ne.postgres.database.azure.com` (resolved via Private DNS to `snet-data`) | `POSTGRES_HOST`, `POSTGRES_PASS` ← `kv-prd-zammad-ne/postgres-password` |
| `cache-prd-zammad-ne` | Redis | `cache-prd-zammad-ne.redis.cache.windows.net:6380` | `REDIS_URL` ← `kv-prd-zammad-ne/redis-url` |
| `stprdzammadne` | Azure Files (`zammad-storage` share) | `stprdzammadne.file.core.windows.net` | mounted at `/opt/zammad/storage`; storage provider set at runtime via `Setting.set('storage_provider', 'File')` |
| `kv-prd-zammad-ne` | Secrets store | `kv-prd-zammad-ne.vault.azure.net` | all secret refs |
| `log-prd-zammad` | Log Analytics workspace | — | Container Apps + Postgres + Redis diagnostic logs |
| `az-0265-sp` | Service principal (CI/CD) | — | federated credentials only, no client secret |
| `crprdzammad` | ACR (same sub) | `crprdzammad.azurecr.io` | image registry |

## 7. CI/CD

Hybrid repo model — see §16. App + Dockerfile + deploy workflows live in **this repo** (`plugport/plug-zammad`); Terraform lives in **`evinyacp/az-0265-infra`**. Both repos share `az-0265-sp` via federated OIDC credentials (one per repo).

GitHub Actions workflows in this repo live in `.github/workflows/`. Authenticate to Azure via **workload identity federation** with service principal `az-0265-sp` — no long-lived secrets in GitHub.

### Triggers

- `push` to feature branches → lint + test + container build (no deploy).
- `pull_request` to `main` → same checks + `az containerapp update --dry-run` output as PR comment.
- `push` to `main` → deploy to production.
- Manual dispatch → re-deploy current `main` (rollback safety net).

### Stages

1. **Validate** — `yamllint`, `terraform fmt -check`, `helm lint` (if any), `gitleaks`, Conventional Commits lint.
2. **Build** — container image built from `ghcr.io/zammad/zammad:7.0.1-0045` (pinned in `Dockerfile` via `ARG ZAMMAD_VERSION`), tagged with `${{ github.sha }}` and pushed to `crprdzammad.azurecr.io/zammad:<sha>`.
3. **Test** — health-check the built image (`docker run --rm <img> rails runner 'puts "ok"'`), run config-validation scripts.
4. **Deploy** — strict order:
   1. `az containerapp job start -n cajob-prd-zammad-init -g rg-prd-zammad --image crprdzammad.azurecr.io/zammad:<sha>` and wait for it to succeed (runs `rake db:migrate`). Long-running apps must **not** start on the new image until migrations finish.
   2. `az containerapp update -n ca-prd-zammad-web -g rg-prd-zammad --image crprdzammad.azurecr.io/zammad:<sha>`. Wait for new revision to become healthy.
   3. Repeat the update for `websocket`, `worker`, `scheduler`, `memcached` (memcached only on infra changes).
5. **Verify** — hit `https://operations.plugport.no/api/v1/users/me` with a service-account token → expect HTTP 200. Hit `/` → expect HTTP 200 + expected HTML title.

### Secrets in CI

- Workload identity federation between GitHub Actions and Entra ID. `az-0265-sp` has Owner on the workload subscription (ACP-issued) and additionally `AcrPush` on `crprdzammad`; the apps' user-assigned managed identity (`mi-prd-zammad-apps`) carries `AcrPull` for runtime image pulls.
- Container Apps reads runtime secrets from `kv-prd-zammad-ne` via secret references — never from GitHub Actions.

### Log monitoring policy

After every push to `main`, check the CI/CD workflow logs for warnings and deprecation notices — not just pass/fail. Proactively flag issues and create Linear issues in the `Zammad` project for upcoming breaking changes. Examples:

- Deprecation warnings from `az` CLI, `gh`, `actions/*` versions
- Zammad upstream deprecation notes in container build logs
- Security advisories in `audit-ci` output
- Performance regressions in build/deploy duration

### Rollback

- Container Apps revisions are immutable: `az containerapp revision activate -n <app> -g rg-prd-zammad --revision <previous>`.
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
2. Add `operations` CNAME → `ca-prd-zammad-web.<env>.azurecontainerapps.io` and `asuid.operations` TXT (validation token from Azure).
3. PR → owner approval from `@evinyacp/az-eacp-owner` → **Squash and merge**. `terraform apply` runs post-merge.
4. Verify: `dig +short operations.plugport.no`.

### TLS

1. Azure Portal → `ca-prd-zammad-web` → Custom domains → Add custom domain → `operations.plugport.no`.
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
- **Attachments** (`stprdzammadne` Azure Files share): GRS replication (Norway East → Norway West, the regional pair). File-share-level snapshot daily, retained 14 days.
- **Target**: RTO 4h / RPO 1h.

### Monitoring

- Container Apps + Postgres + Redis diagnostic logs → `log-prd-zammad` (Log Analytics workspace).
- Alerts (Action Group → Plug oncall):
  - Container App health probe failures > 2 in 5 min
  - Postgres CPU > 80% for 10 min
  - Redis cache evictions > threshold
  - SSO sign-in failure rate spike
- Dashboards: Azure Workbook `wb-prd-zammad-overview` (latency, error rate, queue depth).

## 11. Staging strategy

Hybrid model:

- **Daily ops** — config changes, env-var tweaks, Plug overlays at the *same* Zammad version: use Container Apps revisions for blue/green. New revision takes 0% traffic by default; promote via `--traffic-weight latest=100`.
- **Zammad version bumps** (any 7.x.y → 7.x.z with `db:migrate`, or 7 → 8): spin up ephemeral staging via Terraform `module.staging` — restores latest Postgres PITR snapshot into `pg-stg-zammad`, brings up `ca-stg-zammad`, runs smoke tests, tears down.

Full runbook: `docs/features/staging.md`.

SMTP for outbound mail is **TBD** — tracked as Linear issue under the `Zammad` project. Default `.env.example` documents the env-var contract; production will not deliver mail until the decision is made and secrets are populated.

## 12. Sizing baseline

Initial Container App sizing for a ~40-agent install. Re-tune after the first month of telemetry.

| Container App | CPU | Memory | Replicas | Notes |
|---|---|---|---|---|
| `ca-prd-zammad-web` | 2.0 | 4 Gi | 1–3 (HTTP-scaled) | Rails + nginx sidecar |
| `ca-prd-zammad-websocket` | 1.0 | 2 Gi | 1–2 | |
| `ca-prd-zammad-worker` | 2.0 | 4 Gi | 1–4 (queue-scaled) | Sidekiq spawns several processes per replica |
| `ca-prd-zammad-scheduler` | 0.5 | 1 Gi | 1 (singleton) | |
| `ca-prd-zammad-opensearch` | 2.0 | 4 Gi | 1 | Single-node; persistent storage on attached volume |
| `ca-prd-zammad-memcached` | 0.25 | 0.5 Gi | 1 | Stateless cache |
| `cajob-prd-zammad-init` | 1.0 | 2 Gi | job | Migrations only |

Total baseline ≈ **7.75 CPU / 15.5 Gi**. Zammad's documented minimum is 2 CPU + 6 GB for the app and an additional 4 GB for Elasticsearch on the same host — this layout splits those budgets across dedicated apps for blast-radius isolation.

## 13. Networking

Container Apps must reach Postgres Flexible Server over a private endpoint, so the environment runs in a custom VNet (workload-profile environment is required for VNet + private endpoint support).

- **VNet**: `vnet-prd-zammad` (`10.40.0.0/16`).
  - `snet-apps` (`/23`, delegated to `Microsoft.App/environments`) — Container Apps environment subnet.
  - `snet-data` (`/27`) — Private Endpoints for `pg-prd-zammad-ne`.
- **Private DNS zones** linked to the VNet:
  - `privatelink.postgres.database.azure.com` — resolves `pg-prd-zammad-ne.postgres.database.azure.com` to the PE in `snet-data`.
- **Egress**: outbound NAT via a Container Apps environment outbound IP. Use that IP for any allowlisting (M365 SMTP relay, external webhooks).
- **Reference**: [Microsoft Learn — Use private endpoints with Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint).

## 14. Repos and ownership

Hybrid model — two repos, one workload.

| Repo | Owns | Workflows |
|---|---|---|
| `plugport/plug-zammad` (this repo) | `Dockerfile`, Plug overlays, `docs/`, `CLAUDE.md`, `.env.example`, app deploy CI | `.github/workflows/ci.yml`, `.github/workflows/deploy.yml` |
| `evinyacp/az-0265-infra` | All Terraform — flat layout under `infrastructure/`, scaffolded by Eviny ACP | `plan.yml` (plan-on-PR) + `apply.yml` (apply-on-main). **Currently broken — DA-95.** Local `terraform apply` is the interim path; see `docs/features/infra-runbook.md`. |
| `evinyacp/eviny-dns` | DNS zone `plugport.no` (Terraform) | post-merge `terraform apply` |

Cross-repo coupling:
- App deploy in this repo calls `az containerapp update` against resources whose Terraform lives in `az-0265-infra`. The contract is the resource names (`ca-prd-zammad-*`, `cajob-prd-zammad-init`).
- Both repos authenticate as `az-0265-sp` via federated OIDC credentials — separate `subject` per repo. Adding a new repo to this trust requires a new federated credential.
- The DNS PR in `evinyacp/eviny-dns` is opened from this repo's context (custom-domain bind for `operations.plugport.no`).

## 15. Plugins + Available skills

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

## 16. Mandatory use of skills + Recommended workflow

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
