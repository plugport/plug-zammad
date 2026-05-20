# DA-90: Dockerfile + CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the four files in `plugport/plug-zammad` that build the Plug Zammad image and deploy it to the six already-live Container Apps + init Job — `Dockerfile`, `.dockerignore`, `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`.

**Architecture:** Plug's Dockerfile is a thin wrapper around the upstream-canonical `ghcr.io/zammad/zammad` image. The same image runs every role — the role-specific command (`zammad-railsserver`, `zammad-websocket`, `zammad-scheduler`, `zammad-init`, `zammad-nginx`) is set per Container App in Terraform (`evinyacp/az-0265-infra` → `infrastructure/apps.tf`). CI lints + builds on every push; deploy runs only on `main` and uses OIDC against `az-0265-sp` to push to `crprdzammad` and roll the apps.

**Tech Stack:** Docker, GitHub Actions, `azure/login@v3`, Azure CLI `az containerapp`, Buildx (linux/amd64), upstream image `ghcr.io/zammad/zammad:7.0.1-0045`.

---

## Validated context (don't re-derive)

| Fact | Source |
|---|---|
| Upstream-canonical image: `ghcr.io/zammad/zammad` | `zammad/zammad-docker-compose/docker-compose.yml` (`IMAGE_REPO` default) |
| Newest immutable patch tag: `7.0.1-0045` | Docker Hub API, 2026-05-20 |
| Upstream default pin: `7.0.1-0040` | `zammad/zammad-docker-compose/.env.dist` |
| Entrypoint commands accepted by the image | `docker-compose.yml`: `zammad-init`, `zammad-railsserver`, `zammad-scheduler`, `zammad-websocket`, `zammad-nginx`. There is no separate `zammad-worker` — worker-pool split is via `ZAMMAD_PROCESS_*_WORKERS` env vars (set in apps.tf, not here). |
| Auth identifiers | `az-0265-sp` app ID `a7141a4c-8174-491f-960b-a9b4eedac81a`, tenant `12f1bdca-9eec-45f6-a63e-2061b957e8ee`, sub `7ffb20c8-2855-49e4-99f0-23ea9bcb706e` |
| ACR | `crprdzammad.azurecr.io` (same workload sub, `az-0265-sp` has AcrPush, `mi-prd-zammad-apps` has AcrPull) |
| Federated cred subjects already on `az-0265-sp` | `repo:plugport/plug-zammad:ref:refs/heads/main` and `repo:plugport/plug-zammad:pull_request` |

## File responsibilities

| File | Responsibility |
|---|---|
| `Dockerfile` | Thin `FROM ghcr.io/zammad/zammad:7.0.1-0045` with OCI labels. No Plug overlays yet. |
| `.dockerignore` | Keep build context tiny — exclude `.git`, `docs/`, `*.md`, CI files. |
| `.github/workflows/ci.yml` | PRs to `main` + pushes to feature branches: yamllint, gitleaks, actionlint, commitlint, `docker buildx build` for `linux/amd64`, smoke check the resulting image. No deploy. |
| `.github/workflows/deploy.yml` | Pushes to `main` + manual dispatch: OIDC login, `az acr login`, build/push with SHA tag, run `cajob-prd-zammad-init` and **wait**, then `az containerapp update` per long-running app (web, websocket, worker, scheduler). `memcached` + `opensearch` keep their upstream images and are not touched. Final verify: `curl -I` against the env default domain. |

---

### Task 1: Move Linear DA-90 to In Progress

**Files:** none (Linear API)

- [ ] **Step 1: Update DA-90 status**

Use the Linear MCP tool: `save_issue` with `id: "DA-90"`, `state: "In Progress"`. Add a starting-work comment listing the four files to land.

---

### Task 2: Create feature branch

**Files:** none (git)

- [ ] **Step 1: Branch from main**

```bash
cd /Users/eyvind/plug-zammad
git checkout -b eyvind/da-90-dockerfile-ci
```

Expected: `Switched to a new branch 'eyvind/da-90-dockerfile-ci'`.

---

### Task 3: Write Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Write Dockerfile**

```dockerfile
# Plug Zammad — thin wrapper around the upstream image.
# Per-role command (zammad-railsserver, zammad-websocket, zammad-scheduler,
# zammad-init, zammad-nginx) is set per Container App in
# evinyacp/az-0265-infra/infrastructure/apps.tf, not here.
ARG ZAMMAD_VERSION=7.0.1-0045
FROM ghcr.io/zammad/zammad:${ZAMMAD_VERSION}

LABEL org.opencontainers.image.title="plug-zammad" \
      org.opencontainers.image.source="https://github.com/plugport/plug-zammad" \
      org.opencontainers.image.vendor="Plug" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
```

- [ ] **Step 2: Verify the image tag exists**

```bash
docker manifest inspect ghcr.io/zammad/zammad:7.0.1-0045 >/dev/null && echo OK
```
Expected: `OK`. (If Docker Hub is preferred, `docker.io/zammad/zammad:7.0.1-0045` mirrors the same content.)

---

### Task 4: Write .dockerignore

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: Write .dockerignore**

```
# VCS
.git
.gitignore
.gitattributes

# Docs / markdown
docs/
*.md
README*
LICENSE*
CHANGELOG*

# CI + tooling
.github/
.claude/
.vscode/
.idea/

# Local env
.env
.env.*
!.env.example

# OS junk
.DS_Store
Thumbs.db
```

---

### Task 5: Write .github/workflows/ci.yml

**Files:**
- Create: `.github/workflows/ci.yml`

Triggers: `pull_request` to `main` (full pipeline) + `push` on any branch except `main` (same minus PR comment). No deploy.

- [ ] **Step 1: Write the file**

```yaml
name: ci

on:
  pull_request:
    branches: [main]
  push:
    branches-ignore: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: yamllint
        uses: ibiqlik/action-yamllint@v3
        with:
          file_or_dir: .github/workflows
          strict: true

      - name: actionlint
        uses: raven-actions/actionlint@v2

      - name: gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: commitlint (conventional commits)
        if: github.event_name == 'pull_request'
        uses: wagoid/commitlint-github-action@v6
        with:
          configFile: ${{ github.workspace }}/.github/commitlint.config.cjs

  build:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image (linux/amd64, no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: false
          load: true
          tags: plug-zammad:ci-${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke check — image labels + binaries present
        run: |
          docker image inspect plug-zammad:ci-${{ github.sha }} \
            --format '{{ index .Config.Labels "org.opencontainers.image.title" }}' \
            | grep -q '^plug-zammad$'
          docker run --rm --entrypoint /bin/bash plug-zammad:ci-${{ github.sha }} -c \
            'test -d /opt/zammad && command -v ruby && command -v bundle'
```

- [ ] **Step 2: Add commitlint config (referenced by the workflow)**

Create `.github/commitlint.config.cjs`:

```js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'refactor', 'test',
      'build', 'ci', 'chore', 'perf', 'style',
    ]],
    'header-max-length': [2, 'always', 72],
  },
};
```

---

### Task 6: Write .github/workflows/deploy.yml

**Files:**
- Create: `.github/workflows/deploy.yml`

Triggers: `push` to `main` + manual `workflow_dispatch`.

Auth: OIDC via `azure/login@v3`. The federated credential subjects `:ref:refs/heads/main` and `:pull_request` are already provisioned on `az-0265-sp`. No client secret.

Deploy order (strict): build/push → init job (wait for success) → web → websocket → worker → scheduler → verify.

`memcached` and `opensearch` keep their upstream images; not touched here.

- [ ] **Step 1: Write the file**

```yaml
name: deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  id-token: write   # required for OIDC federation to Entra ID

concurrency:
  group: deploy-prod
  cancel-in-progress: false   # never cancel a deploy mid-flight

env:
  AZURE_CLIENT_ID: a7141a4c-8174-491f-960b-a9b4eedac81a
  AZURE_TENANT_ID: 12f1bdca-9eec-45f6-a63e-2061b957e8ee
  AZURE_SUBSCRIPTION_ID: 7ffb20c8-2855-49e4-99f0-23ea9bcb706e
  RG: rg-prd-zammad
  ACR: crprdzammad
  IMAGE: crprdzammad.azurecr.io/zammad

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ env.AZURE_CLIENT_ID }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: ACR login
        run: az acr login -n "$ACR"

      - name: Build and push image
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: true
          tags: |
            ${{ env.IMAGE }}:${{ github.sha }}
            ${{ env.IMAGE }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run init job (db:migrate) and wait
        env:
          SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
          EXEC_NAME=$(az containerapp job start \
            -n cajob-prd-zammad-init -g "$RG" \
            --image "$IMAGE:$SHA" \
            --query name -o tsv)
          echo "Started init execution: $EXEC_NAME"
          # Poll up to 20 min
          for i in $(seq 1 80); do
            STATUS=$(az containerapp job execution show \
              -n cajob-prd-zammad-init -g "$RG" \
              --job-execution-name "$EXEC_NAME" \
              --query properties.status -o tsv)
            echo "[$i/80] status=$STATUS"
            case "$STATUS" in
              Succeeded) echo "init job succeeded"; exit 0 ;;
              Failed|Cancelled|Degraded)
                echo "init job ended in $STATUS"
                az containerapp job execution show \
                  -n cajob-prd-zammad-init -g "$RG" \
                  --job-execution-name "$EXEC_NAME" -o json
                exit 1 ;;
            esac
            sleep 15
          done
          echo "init job timed out after 20 min"; exit 1

      - name: Roll long-running apps
        env:
          SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
          for APP in ca-prd-zammad-web ca-prd-zammad-websocket \
                     ca-prd-zammad-worker ca-prd-zammad-scheduler; do
            echo "::group::Update $APP"
            az containerapp update \
              -n "$APP" -g "$RG" \
              --image "$IMAGE:$SHA"
            echo "::endgroup::"
          done

      - name: Verify web endpoint
        run: |
          set -euo pipefail
          FQDN=$(az containerapp show -n ca-prd-zammad-web -g "$RG" \
            --query properties.configuration.ingress.fqdn -o tsv)
          echo "Checking https://$FQDN/"
          # Allow a brief warm-up
          for i in $(seq 1 12); do
            CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://$FQDN/" || echo "000")
            echo "[$i/12] HTTP $CODE"
            if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
              exit 0
            fi
            sleep 10
          done
          echo "web endpoint never returned 200/302"; exit 1
```

Note: the worker Container App (`ca-prd-zammad-worker`) is rolled even though no `zammad-worker` command exists upstream — the per-app command lives in `apps.tf` and uses `zammad-scheduler` with `ZAMMAD_PROCESS_*_WORKERS` env-var split. The deploy workflow only updates the image, not the command, so it's image-agnostic.

---

### Task 7: Commit, push, open PR

- [ ] **Step 1: Stage and commit**

```bash
git add Dockerfile .dockerignore .github/workflows/ci.yml \
        .github/workflows/deploy.yml .github/commitlint.config.cjs \
        docs/superpowers/plans/2026-05-20-da-90-dockerfile-ci.md
git status   # sanity-check
git commit -m "$(cat <<'EOF'
feat: add Dockerfile and CI/CD workflows for Container Apps deploy

Pin upstream image to ghcr.io/zammad/zammad:7.0.1-0045. CI lints and
builds; deploy authenticates via OIDC as az-0265-sp, pushes to
crprdzammad, runs cajob-prd-zammad-init for db:migrate, then rolls the
four long-running apps (web, websocket, worker, scheduler). memcached
and opensearch keep their upstream images and are not touched here.

fixes DA-90
EOF
)"
```

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin eyvind/da-90-dockerfile-ci
gh pr create --fill --base main
```

- [ ] **Step 3: Watch checks**

```bash
gh pr checks --watch
```
If anything fails, fix in-place (amend + force-push), not stacked `fix(...)` commits per CLAUDE.md §3.

- [ ] **Step 4: Merge (only after checks are green)**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 5: Verify the deploy workflow on main succeeded**

```bash
gh run watch                              # interactive, or:
gh run list --workflow deploy.yml --limit 1
```

- [ ] **Step 6: Move Linear DA-90 → Done**

Use Linear MCP `save_issue` with `id: "DA-90"`, `state: "Done"`. Add a closing comment with the merged PR link and the SHA tag now running in prod.

---

## Self-review

1. **Spec coverage** (CLAUDE.md §0 six-step list):
   - Step 1 (verify latest tag) → done in pre-plan validation (7.0.1-0045 ✅)
   - Step 2 (Dockerfile) → Task 3 ✅
   - Step 3 (.dockerignore) → Task 4 ✅
   - Step 4 (ci.yml) → Task 5 ✅
   - Step 5 (deploy.yml) → Task 6 ✅
   - Step 6 ("after DA-90: DA-92") → out of scope, separate plan
2. **Placeholder scan:** no TBDs, no "implement later". All commands and file contents are literal.
3. **Type/name consistency:** app names (`ca-prd-zammad-{web,websocket,worker,scheduler}`), job (`cajob-prd-zammad-init`), RG (`rg-prd-zammad`), ACR (`crprdzammad`), SP IDs — all sourced from CLAUDE.md §0 and used verbatim.

## Known follow-ups (NOT in this PR)

- CLAUDE.md §1 still describes the upstream image as `zammad/zammad` (Docker Hub). Upstream canonical is `ghcr.io/zammad/zammad`. Worth a one-line docs cleanup in a separate PR, low priority.
- CI smoke-check is intentionally minimal (`bash -c 'test -d /opt/zammad && command -v ruby'`). A `rails runner 'puts "ok"'` check needs DB connectivity and isn't viable in CI. Real verification lives in the deploy workflow's web-endpoint curl step.
