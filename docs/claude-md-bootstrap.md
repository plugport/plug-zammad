# CLAUDE.md bootstrap prompt — plug-zammad

Paste the prompt below into a Claude Code session at the root of this repo. It is self-contained: Claude does not need any other file in context to follow it. After the session, you should have a complete `CLAUDE.md` plus the supporting docs it references.

The prompt assumes the same plugin set as `plug-analytics`: `superpowers`, `frontend-design`, `plug-brand-design`, `code-simplifier`, `claude-md-management`. Install them with `/plugin install <name>@claude-code-plugins` before you start if they are not already enabled.

---

## Prompt (copy from here to end of file)

````markdown
# Goal

Bootstrap this repository (`plugport/plug-zammad`) as a working Plug engineering project. The end state of this session is a complete `CLAUDE.md` at the repo root that:

1. Matches the engineering process used in the sister project `plugport/plug-analytics` (the conventions in this prompt are non-negotiable copies of those).
2. Adapts the architecture / commands / Azure sections to **Zammad on Azure, exposed at `operations.plugport.no`**.
3. Documents the **CI/CD flow**, **Entra ID SSO setup**, and **DNS + TLS** for that URL.

Use the skill `superpowers:brainstorming` **before** writing any file — most of the variable sections require decisions you cannot guess. Use `superpowers:writing-plans` if the brainstorm produces more than five sub-tasks.

Do not commit or open a PR in this session. Write the files only.

# Non-negotiable conventions — copy verbatim, do not "improve"

## Model

- Main agent (interactive): always `claude-opus-4-7`.
- Subagents (Agent tool):
  - `opus` → code review, debugging, novel reasoning, architecture decisions.
  - `sonnet` → mechanical execution from a precise prompt (plan execution, string substitutions, applying a diff).
  - `haiku` → search / read / summarize (`Explore` agent, grep-style lookups).
- Rule of thumb: if a junior dev could do it following your instructions literally, Sonnet is enough. If it needs judgment, Opus.

## Git

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

## Linear

This project is pinned to:

- **Workspace**: Plugport (the same Linear org as `plug-analytics`)
- **Team**: `Dataplattform` — ID `ca2acb0a-804f-482d-af55-6afcd9bde58c`, key prefix `DA`
- **Project**: `Zammad` — ID `9706db9e-9f1c-43ae-9102-0b87f6b43ee5`, URL https://linear.app/plugport/project/zammad-bf0065c652a2

**Every issue Claude creates in this repo's context must be created in the `Zammad` project under the `Dataplattform` team.** Do not file Zammad work in any other team or project.

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

Sandbox / no-MCP fallback (or when the MCP doesn't surface `Dataplattform`): use the REST/GraphQL API with `$LINEAR_API_KEY` from `.sandbox.env`. Always literal newlines in markdown, never escaped `\n`.

## Plugins

Required Claude Code plugins (install via marketplace if not already present):

```
/plugin install superpowers
/plugin install frontend-design@claude-code-plugins   # only if any UI work is needed
/plugin install claude-md-management@claude-code-plugins
```

Optional but recommended:

```
/plugin install code-simplifier@claude-code-plugins
```

`plug-brand-design` lives at `.claude/skills/plug-brand-design/` in `plug-analytics`. Copy that directory into this repo **only if** the Zammad UI is going to be re-themed in Plug brand colors. Zammad has its own theming system, so usually you leave the default and skip this skill.

## Mandatory use of skills

If there is greater than 1% chance a skill applies, USE it — before any response, including clarifying questions.

Priority order:
1. **Process skills first** (`superpowers:brainstorming`, `superpowers:systematic-debugging`) — these determine *how* to approach work.
2. **UI skills** (`plug-brand-design`, `frontend-design`) — only if there is actual UI work.
3. **Implementation skills** (`test-driven-development`, `executing-plans`, `subagent-driven-development`, `verification-before-completion`).

These thoughts mean STOP and check skills anyway:
- "This is just a simple question"
- "I need more context first"
- "This skill is overkill"

## Recommended workflow

`brainstorming` → `writing-plans` → `executing-plans` / `subagent-driven-development` → `test-driven-development` → `verification-before-completion` → `requesting-code-review` → `finishing-a-development-branch`.

# Variable — interview the user before writing these sections

Do not guess. Ask each question, wait for an answer, then write.

1. **Deployment target.** Azure Container Apps, AKS, App Service, or VM? Zammad's upstream supports Docker Compose, Kubernetes (Helm chart), and bare-metal. Container Apps is the path of least resistance if no advanced K8s features are needed.
2. **Postgres.** Azure Database for PostgreSQL Flexible Server (recommended for backups, HA), or in-cluster?
3. **Search engine.** Zammad **requires** Elasticsearch or OpenSearch for ticket search. Options: Elastic Cloud, Azure-hosted via Bitnami chart, or self-managed in-cluster. (Azure does not have a first-party Elasticsearch service.)
4. **Redis.** Azure Cache for Redis or in-cluster? Zammad uses Redis for background jobs (Sidekiq).
5. **Object storage.** S3-compatible bucket for attachments. Azure Blob Storage via the S3 emulator extension, or use a managed S3-compatible service?
6. **SMTP.** Outbound mail for ticket notifications. Azure Communication Services Email, SendGrid, or relay via Microsoft 365?
7. **Secrets strategy.** Inline Container App secrets (same pattern as `ca-plug-analytics`), or dedicated Key Vault? Note: `plug-analytics` does not have a Key Vault — it uses inline Container App secrets. Match unless there is a strong reason to diverge.
8. **Zammad version.** Pin to a specific minor (recommended: latest stable that has at least 6 months of upstream support remaining).
9. **Resource Group / naming prefix.** Suggested: `rg-zammad`, `ca-zammad` (or `aks-zammad` if AKS), `pg-zammad`, `cache-zammad`.
10. **Backups.** Postgres point-in-time restore window, attachment backup target, RTO/RPO targets.

# CI/CD pipeline — the section CLAUDE.md must document

Whatever the deployment target, `CLAUDE.md` must include a **CI/CD** section that describes the pipeline at a level a new contributor can navigate. After brainstorming the deployment target above, design a pipeline and document it. Include at minimum:

## Triggers

- `push` to feature branches → lint + test + container build (no deploy).
- `pull_request` to `main` → same checks + plan output as PR comment (Terraform plan, Helm diff, or `az containerapp update --dry-run`).
- `push` to `main` → deploy to production.
- Manual dispatch → re-deploy current `main` (rollback safety net).

## Stages

1. **Validate** — lint (`yamllint`, `terraform fmt -check`, `helm lint`), secret scan (`gitleaks`), commit-message lint (Conventional Commits).
2. **Build** — container image built from Zammad upstream + Plug overlays, tagged with `${{ github.sha }}` and pushed to ACR (`crplugport.azurecr.io`).
3. **Test** — health-check the built image (`docker run --rm <img> rails runner 'puts "ok"'`), run any config-validation scripts.
4. **Deploy** — apply Terraform / Helm / `az containerapp update`. Wait for revision to become healthy. Run smoke tests against the new revision.
5. **Verify** — hit `/api/v1/users/me` with a service-account token, assert HTTP 200. Hit `/` and assert HTTP 200 + expected HTML title.

## Secrets in CI

- Workload identity federation between GitHub Actions and Entra ID (no long-lived secrets in GitHub). Service principal `sp-plug-zammad` with role assignments scoped to the Zammad RG only.
- Container Apps secrets injected from Container App configuration (inline) — never from GitHub Actions.

## Log monitoring policy

After every push to `main`, Claude must check the CI/CD workflow logs for warnings and deprecation notices — not just pass/fail. Proactively flag issues and create Linear issues in the `Zammad` project for upcoming breaking changes. Examples:

- Deprecation warnings from `az` CLI, `gh`, `actions/*` versions
- Zammad upstream deprecation notes in container build logs
- Security advisories in `audit-ci` output
- Performance regressions in build/deploy duration

## Rollback

- Container Apps: revisions are immutable; rollback = `az containerapp revision activate <previous-revision>`.
- AKS / Helm: `helm rollback zammad <revision>`.
- Postgres schema migrations from Zammad upgrades: always test in a `zammad-staging` Container App before promoting to prod. Plug-analytics does not have a staging environment — Zammad warrants one because schema migrations are irreversible.

Match this to the chosen deployment target in `CLAUDE.md`.

# Entra ID SSO — must be documented in CLAUDE.md

Zammad must require Entra ID login for all users. Use OIDC (simpler and better-supported than SAML for new setups).

## App Registration

1. In Entra ID admin center → Microsoft Entra ID → App registrations → New registration.
2. Name: `Plug Zammad`.
3. Supported account types: **Accounts in this organizational directory only** (Plug tenant).
4. Redirect URI: **Web** → `https://operations.plugport.no/auth/microsoft_office365_v2/callback`. (This is Zammad's hard-coded OmniAuth callback path for the Microsoft Entra strategy. Do not change it.)
5. After creation, capture:
   - **Application (client) ID**
   - **Directory (tenant) ID**

## Client secret

- Certificates & secrets → New client secret → 24 months expiry. Add a Linear reminder in the `Zammad` project to rotate two weeks before expiry.
- Store the secret value as a Container App secret named `entra_zammad_client_secret`. Reference it in Zammad's environment as `MICROSOFT_OFFICE365_V2_CLIENT_SECRET`.

## API permissions

Required Microsoft Graph delegated permissions:

| Permission | Type | Why |
|---|---|---|
| `openid` | Delegated | OIDC sign-in |
| `profile` | Delegated | Name claim |
| `email` | Delegated | Email claim (used by Zammad as the user identifier) |
| `User.Read` | Delegated | Read the signed-in user's basic profile |

Grant admin consent for the tenant after adding.

## Token configuration — group claim (optional, recommended)

To map AD groups to Zammad roles automatically:

1. Token configuration → Add groups claim → Security groups → ID token + Access token.
2. In Zammad admin → Settings → Security → Third-party Applications → Microsoft → enable the integration and paste client ID / secret / tenant ID.
3. Map groups: Zammad does not have native group-claim → role mapping in the OmniAuth strategy. Use one of:
   - Add a post-login hook (Ruby) that reads `auth.extra.raw_info.groups` and sets Zammad roles. Document the hook file path in `CLAUDE.md`.
   - Or accept that role assignment is manual in Zammad admin for new users (simpler, fine for low user counts).

## Zammad configuration

In Zammad: **Admin → Settings → Security → Third Party Applications**:

- Enable **Microsoft (Office 365)** authentication.
- Paste **App ID**, **App Secret**, **Tenant ID**.
- Set **automatic account link on initial sign-in** = on, matched on email.
- Disable the local password login form once SSO is verified working end-to-end (Admin → Settings → Security → Base → "Third-party login only").

## Service principal for CI/CD

Separate from the user-facing app:

- Service principal `sp-plug-zammad` with federated credentials trusting `repo:plugport/plug-zammad:ref:refs/heads/main`.
- Role assignments scoped to `rg-zammad` only:
  - `Contributor` (or narrower if AKS chosen)
  - `AcrPush` on `crplugport`
- No client secrets — federated credentials only.

# DNS + TLS — operations.plugport.no

## DNS record

`plugport.no` is managed in `evinyacp/eviny-dns` (Terraform). To add the operations subdomain:

1. Clone `evinyacp/eviny-dns`, branch off `main`.
2. In the `plugport.no` zone module, add a CNAME (or A) record:
   - `operations` → the Azure Container App's default FQDN (`ca-zammad.<env>.azurecontainerapps.io`) if using Container Apps managed certs.
   - Or `operations` → Azure Front Door endpoint if fronting with Front Door + WAF.
3. Commit, push, open PR. Required: code owner approval from `@evinyacp/az-eacp-owner`. Use **Squash and merge** (not merge commit). `terraform apply` runs automatically post-merge.
4. Verify the record propagated: `dig +short operations.plugport.no`.

## TLS certificate

Two paths, pick during brainstorming:

**Path A — Container Apps managed certificate (free, simple):**
1. In Azure Portal, navigate to the Container App → Custom domains → Add custom domain.
2. Domain: `operations.plugport.no`. Verification will require a TXT record (`asuid.operations`) which Azure issues — also add that via the eviny-dns repo.
3. Select **Managed certificate**. Azure issues a Let's Encrypt cert and rotates it automatically.
4. Bind the domain.

**Path B — Azure Front Door + WAF (recommended if you want centralized rate-limiting, WAF rules, geo-fencing):**
1. Stand up Front Door in front of the Container App.
2. Add custom domain to Front Door, validation via DNS TXT, use the Front Door managed cert.
3. CNAME `operations.plugport.no` → Front Door endpoint.
4. Configure WAF rules: block traffic outside Europe, rate-limit `/api/*`, require Entra ID for `/admin`.

Document the chosen path in `CLAUDE.md` and link the eviny-dns PR in the project history.

## HSTS / security headers

Once TLS is live, ensure Zammad sends:

- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Frame-Options: DENY`
- `Content-Security-Policy` — Zammad has a sensible default; document any overrides.

Set in the Container App ingress or in Front Door rules depending on the chosen path.

# Output

Write the following files. Do not commit, do not open a PR — just the files. Use English everywhere.

## `CLAUDE.md` at repo root

Structure (sections in this order):

1. **Architecture** — Zammad components (web, websocket, worker, scheduler), the chosen deployment target's mapping (`ca-zammad-web`, etc.), data stores, traffic flow diagram in ASCII or Mermaid.
2. **Model** — paste the Model section above verbatim, swap `plug-analytics` references for `plug-zammad`.
3. **Git** — paste verbatim.
4. **Linear** — paste verbatim. Pin the Dataplattform team ID and Zammad project ID.
5. **Commands** — Docker compose for local dev, `az containerapp` / `helm` / `terraform` shortcuts for deploy, `gh` shortcuts for PRs.
6. **Azure resources** — list every resource in `rg-zammad` with role, FQDN, and which env vars / secrets it produces.
7. **CI/CD** — the pipeline described above, with the actual workflow file paths (`.github/workflows/*.yml`) once they exist. Include the log monitoring policy verbatim.
8. **SSO (Entra ID)** — the App Registration, redirect URI, secrets storage, Zammad config steps. Link to the `Plug Zammad` app in Entra by Application ID.
9. **DNS + TLS** — the chosen path (A or B), the eviny-dns PR link, the verification commands (`dig`, `curl -Iv https://operations.plugport.no`).
10. **Backups + monitoring** — RTO/RPO, where Postgres backups live, attachment backup target, what dashboards exist.
11. **UI/UX Principles** — only include if any Plug-branded UI is being built (likely none — Zammad has its own theming).
12. **Plugins + Available skills** — same tables as `plug-analytics`.
13. **Mandatory use of skills + Recommended workflow** — paste verbatim.

## Supplementary files (only if needed)

- `docs/features/<area>.md` — per-feature docs (SSO, Backups, Search) only if a feature has enough detail to warrant a dedicated file. Don't create empty stubs.
- `.env.example` — every env var Zammad needs, with comments. Include `MICROSOFT_OFFICE365_V2_CLIENT_ID/SECRET`, `POSTGRES_*`, `ELASTICSEARCH_URL`, `REDIS_URL`, `S3_*`, `SMTP_*`.

# Do not

- Do not skip `superpowers:brainstorming` — this is project bootstrap, not a trivial task.
- Do not file issues in any Linear team or project other than `Dataplattform / Zammad`.
- Do not change the team ID or project ID without explicit user approval.
- Do not add `Co-Authored-By` lines in any example or template.
- Do not recommend git worktrees anywhere.
- Do not write "TODO" where you should ask the user — ask.
- Do not commit or open a PR in this bootstrap session — produce the files only.
- Do not paste Entra ID client secret values in `CLAUDE.md` — only the App ID and the env var names.
````
