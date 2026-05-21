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
- `azurerm_container_app.secret.key_vault_secret_id` is a static URI string — Terraform sees no implicit dep on the underlying `azapi_resource "Microsoft.KeyVault/vaults/secrets@..."`. When introducing a new KV secret via the azapi control plane *and* referencing it from a Container App in the same apply, you must add explicit `depends_on = [azapi_resource.secret_*]` to the Container App, or the apply races and Azure rejects the secret-block update with `Unable to get value using Managed identity ... for secret <name>`. See DA-91 (PR #30).

### Linear

- Workspace `Plugport`, team `Dataplattform` (ID `ca2acb0a-804f-482d-af55-6afcd9bde58c`), project `Zammad` (ID `9706db9e-9f1c-43ae-9102-0b87f6b43ee5`).
- Active workflow:

```
DA-84 ACP order               ✅ Done
DA-86 Terraform network       ✅ Done
DA-87 Identity supplement     ✅ Done (MI, federated cred, AcrPush all in place)
DA-88 Terraform data          ✅ Done
DA-89 Terraform apps          ✅ Done
DA-90 Dockerfile + CI         ✅ Done (PR #9, #11, #12: Dockerfile, ci.yml, deploy.yml — green E2E)
DA-96 apps.tf container state ✅ Done (infra PRs #10, #11, #12, #13: command/env/secrets/registry/FQDN)
DA-92 Custom domain + TLS     ✅ Done (operations.plugport.no bound 2026-05-21, DigiCert managed cert, Zammad fqdn+http_type set)
DA-93 SSO go-live             ✅ Done (Entra app reg + SSO sign-in + Third-party-login-only live; break-glass via Rails-exec, formell 1Password-vei sporet i DA-121)
DA-91 Azure OpenAI            ✅ Done (infra live, worker rolled — manual Setting.set still pending per ai.md)
DA-85 SMTP decision           🟡 In Refinement
DA-95 Eviny escalations       🔵 In Progress (samleboks)
```

### What's next

Zammad is **live** at https://ca-prd-zammad-web.orangemoss-71bfd191.norwayeast.azurecontainerapps.io/ — `<title>Zammad Helpdesk</title>`, healthy revision on `crprdzammad.azurecr.io/zammad:<sha>`, `/api/v1/getting_started` returns 200. Six long-running Container Apps + the init job all carry the real Zammad image and Plug's env/secret refs.

Next up:
- **DA-92** — custom domain `operations.plugport.no` + DigiCert-issued managed cert on `ca-prd-zammad-web`. ACA managed certs are issued by DigiCert (CN `GeoTrust TLS RSA CA G1`), NOT Let's Encrypt — verified live 2026-05-21 after binding. ~180-day validity, Azure auto-renews ~45 days before expiry as long as the CNAME + asuid TXT records stay in `eviny-dns`. See `docs/features/dns-tls.md`.
- **DA-93** — Entra SSO go-live: app reg in the Eviny tenant, OmniAuth `microsoft_office365` (NOT `_v2`) configured in Zammad admin UI, auto-link enabled, sign-in confirmed end-to-end. Still pending: break-glass local-password admin documented + 1Password entry, then flip "Third-party login only". See `docs/features/sso-entra.md`.

Lower-priority follow-ups, no Linear issues yet:
- nginx sidecar on `ca-prd-zammad-web` — needs sidecar-aware `az containerapp update --container-name` loop in `deploy.yml`.
- Persistent storage for the opensearch app (Azure Files mount on `/usr/share/elasticsearch/data`). Zammad reindexes from Postgres on restart, so this is durability/perf, not correctness.

---

## 1. Architecture

### Design principles

**Upgrade-friendliness is load-bearing.** Zammad ships ~monthly. Every version bump must be:

1. **A single value change** — bump `ZAMMAD_VERSION` in `Dockerfile`, push, deploy.
2. **No image surgery** — the `Dockerfile` is a thin wrapper (`FROM ghcr.io/zammad/zammad:${ZAMMAD_VERSION}` + LABELs). Never add `RUN`, `COPY`, or anything that modifies the upstream image. If a Zammad-version-specific patch is unavoidable, file it upstream first.
3. **Customization lives at runtime** — Plug-specific config goes via env vars (`apps.tf` `env`), Container Apps secret refs (KV), volume mounts (AzureFile shares), or Rails `Setting.set` in Postgres. Never bake it into the image.
4. **No coupling to internal upstream paths** that aren't part of Zammad's docker contract. If we depend on `/opt/zammad/<x>`, it must be a path Zammad documents as part of its container contract (volumes, env vars, dispatcher commands). When in doubt, check `zammad/zammad-docker-compose`.
5. **One source of truth per concern.** The Container App spec (apps.tf) owns runtime; the upstream image owns Zammad itself; secrets live in Key Vault; long-lived state lives in Postgres or Azure Files. No layered overrides between these.

Why: a custom Dockerfile that gets stale across Zammad versions becomes an integration-test burden, blocks security patches behind manual diff work, and makes rollback fragile. The pre-existing `nginx sidecar startup` regression (DA-117) is a cautionary tale — we depended on cross-container behaviour that upstream solves via a shared docker volume and we missed mirroring on Container Apps.

### Process layout

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
                          │  (HSTS, CSP, X-Frame-Options)│  (Path A — DigiCert via ACA)
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

# Bump the init job image, then start it (passing --image to job start
# clobbers the rest of the template — see §7).
az containerapp job update -n cajob-prd-zammad-init -g rg-prd-zammad --image crprdzammad.azurecr.io/zammad:<sha>
az containerapp job start  -n cajob-prd-zammad-init -g rg-prd-zammad
```

Post-install / post-version-bump (Rails runner via `exec`). See `docs/features/post-install.md` for the full runbook. Two gotchas learned at DA-92 binding:

- `az containerapp exec` uses `--command "..."` (not `-- <cmd>`); the latter errors with "unrecognized arguments".
- `--command "rails r ..."` returns `ClusterExecFailure code: 500` from the cluster exec API even when the connection succeeds. Fall back to **interactive shell** (drop the `--command` flag entirely, then run the commands at the prompt).
- Inside the container, `rails` isn't on `PATH` — use `cd /opt/zammad && bundle exec rails r "..."`.

```bash
# Open an interactive shell into the web container
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad --container web
# ...then inside the shell:
cd /opt/zammad
bundle exec rails r "Setting.set('storage_provider', 'File')"
bundle exec rails r "Setting.set('fqdn', 'operations.plugport.no')"
bundle exec rails r "Setting.set('http_type', 'https')"
# Verify:
bundle exec rails r "puts Setting.get('fqdn'); puts Setting.get('http_type')"
exit  # then Ctrl+D to close az exec
```

Note: `es_url` is auto-set by the upstream entrypoint from `ELASTICSEARCH_HOST`/`PORT` env vars (set in apps.tf via `local.opensearch_host`). Override only if you need to point Rails at a different ES instance than the init bootstrap.

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
4. **Deploy** — strict order. See `deploy.yml` for the exact commands; two non-obvious moves:
   1. **Init job:** `az containerapp job update --image ...` first, **then** `az containerapp job start` *without* `--image`. Passing `--image` to `job start` silently replaces the entire container template (args/env/secrets/cpu/memory) for that execution — observed live, the job reports `Succeeded` in 30s while doing nothing. `job update` persists the image into the spec (terraform `lifecycle.ignore_changes` on `container[0].image` keeps it from drifting state), and a plain `job start` then uses the full template.
   2. **Long-running apps:** `az containerapp update --image` per app — this one only patches the image and preserves args/env. Order: web → websocket → worker → scheduler. `memcached` and `opensearch` keep upstream images and are not updated here.
5. **Verify** — don't just check `200/302`. Container Apps falls back to the previous healthy revision when the new revision has no healthy replicas, and the helloworld fallback image serves 200 with `x-powered-by: Express`. Assert that the revision with `trafficWeight=100, healthState=Healthy` is on the SHA we just pushed AND that the response has no `x-powered-by` header.

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

Zammad requires Entra ID login for all users. OIDC via Zammad's built-in Microsoft OmniAuth strategy. The strategy is named `microsoft_office365` (no `_v2` suffix — early drafts of this doc said v2 but that name doesn't exist in the codebase) and the admin-UI label is just **Microsoft**.

### Tenant

Plug users (`@plugport.no`) are native in the **Eviny AS** Entra tenant (`12f1bdca-9eec-45f6-a63e-2061b957e8ee`), not B2B guests from a separate Plug tenant. App Registration goes in the Eviny tenant.

### App Registration

- **Name**: `Plug Zammad`
- **App (client) ID**: `6a0ccd3c-7548-4339-ba04-4c8a11ddd7c2`
- **Account types**: Accounts in this organizational directory only
- **Redirect URI (Web)**: `https://operations.plugport.no/auth/microsoft_office365/callback` — Zammad's hard-coded OmniAuth callback path; do not change.

Created via `az ad app create` + `az ad sp create` (Plug users can do this without elevated roles).

### Client secret

- Created with 24-month expiry. Linear reminder issue in `Zammad` project, due two weeks before expiry.
- Stored in Key Vault as `kv-prd-zammad-ne/entra-zammad-client-secret`.
- Written via ARM control plane (`az rest ... PUT .../Microsoft.KeyVault/vaults/.../secrets/...`) because the vault has `public_network_access_enabled = false`. Same azapi pattern as DA-91.
- **Not** surfaced as a runtime env var. Zammad's Microsoft strategy is configured in the admin UI (Settings → Security → Third-party Applications → Microsoft). At initial setup, retrieve the secret from KV (or read from the worker container's env if you don't have Secrets User role on the vault) and paste it into the admin form. Rotation = `az ad app credential reset --append` → new value → KV PUT → paste again.

### API permissions

Microsoft Graph delegated:

| Permission | Purpose |
|---|---|
| `openid` | OIDC sign-in |
| `profile` | Name claim |
| `email` | Email claim (Zammad user identifier) |
| `User.Read` | Read signed-in user's basic profile |

Admin consent **requires `Application Administrator` / `Cloud Application Administrator` / `Global Administrator`** in the Eviny tenant. Plug users don't have these by default — escalate to Eviny IT via samleboks (`az ad app permission admin-consent --id <appId>`), or test first whether the tenant allows user-level consent for these basic scopes (it usually does).

### Optional: group claim

To map AD groups → Zammad roles automatically, enable groups claim (Security groups → ID + access token). Mapping handled either by a Ruby post-login hook (path documented in `docs/features/sso-entra.md`) or kept manual in Zammad admin.

### Zammad configuration

In Zammad admin → Settings → Security → Third-party Applications → **Microsoft**:

- Paste App ID, App Secret, App Tenant ID
- Save
- Also enable `auth_third_party_auto_link_at_inital_login` (note Zammad's upstream typo: "inital"). Without it, the first SSO sign-in fails with `422 Email address X is already used for another user` because Zammad tries to create a new user instead of linking the Microsoft identity to the existing local admin.
- Once SSO works end-to-end **and** a break-glass local-password admin is in place (see `docs/features/sso-entra.md` §6): Settings → Security → Base → "Third-party login only" to disable local password form.

### Prerequisite: HTTPS scheme through nginx sidecar

OIDC requires `https://` in the `redirect_uri` Entra receives back from the OAuth callback. That depends on Rails generating HTTPS URLs, which depends on `X-Forwarded-Proto: https` reaching Rails. Both are wired up in `apps.tf`: `NGINX_SERVER_SCHEME=https` on the nginx sidecar + `127.0.0.1` in `RAILS_TRUSTED_PROXIES` (the nginx-to-Rails localhost hop). Don't remove either without checking — DA-119 was filed and fixed exactly this regression.

### Full walkthrough

See `docs/features/sso-entra.md`.

## 9. DNS + TLS

**Path A** — Container Apps managed certificate (DigiCert, ~180-day validity, auto-renewed by Azure). Path B (Front Door + WAF) is tracked as a future option, see `docs/features/dns-tls.md`.

### DNS

`plugport.no` lives in `evinyacp/eviny-dns` (Terraform). To add `operations.plugport.no`:

1. Branch `eviny-dns` from `main`.
2. Add `operations` CNAME → `ca-prd-zammad-web.<env>.azurecontainerapps.io` and `asuid.operations` TXT (validation token from Azure).
3. PR → owner approval from `@evinyacp/az-eacp-owner` → **Squash and merge**. `terraform apply` runs post-merge.
4. Verify: `dig +short operations.plugport.no`.

### TLS

1. Azure Portal → `ca-prd-zammad-web` → Custom domains → Add custom domain → `operations.plugport.no`.
2. Validation via the `asuid.operations` TXT added above.
3. Select **Managed certificate** → Azure issues a DigiCert cert (`GeoTrust TLS RSA CA G1` chain) and rotates automatically ~45 days before the ~180-day expiry.
4. Bind the domain.

### Verification commands

```bash
dig +short operations.plugport.no
curl -Iv https://operations.plugport.no
```

Expect HTTP 200 and a DigiCert-issued certificate.

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
- **Inter-app traffic — use HTTP port 80, NOT `target_port`.** Container Apps' internal ingress for HTTP apps listens on port 80 (HTTPS on 443) at the `<app>.internal.<env-default-domain>` address. Envoy then forwards to the container's `target_port` *inside the pod*. Calling `http://<app>:9200` (target_port directly) does NOT reach Envoy — there's no listener on that port at the env's internal address, and curl times out after 30s. Real example: opensearch's `target_port = 9200`, but `ELASTICSEARCH_HOST=<fqdn>` + `ELASTICSEARCH_PORT=80` is the correct form (set in `local.zammad_common_env`). The MS Learn docs example confirms — `http://my-backend-api` (no port, defaults to 80). Found via DA-110 after four wrong fixes; documented in case future opensearch/memcached-like services tempt us to "just use the target port".
- **Inter-app DNS — short name OR full FQDN, both resolve for HTTP. TCP is short-name-only.** Per `ingress-overview`: HTTP-ingress accepts "FQDN, app name, Dapr service invocation, or custom domain". But TCP-ingress (transport=tcp) is documented differently — "accessible to other container apps in the same environment via its **name** … and **exposed port number**". The `<app>.internal.<env-default-domain>` form does NOT work for TCP from inside the env; use the short app name only. Real example (DA-112): memcached needs `MEMCACHE_SERVERS=ca-prd-zammad-memcached:11211`, NOT the FQDN. For TCP you must also set `exposed_port` explicitly in `apps.tf` — the azurerm provider leaves it at 0 otherwise, and Envoy doesn't bind a listener.
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
