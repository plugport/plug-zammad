# Post-install runbook

Most "post-install settings" for Zammad are now applied automatically by the upstream entrypoint script — see CLAUDE.md §5 for the up-to-date command list. This page documents the **remaining manual steps** for first-deploy and per-version-bump runs.

## Order of operations (first deploy)

1. Provision Azure resources via Terraform in [`evinyacp/az-0265-infra`](https://github.com/evinyacp/az-0265-infra) (not this repo — see CLAUDE.md §14 for the hybrid-repo model).
2. Build + push the Zammad image from this repo's `Dockerfile` (which pins `ghcr.io/zammad/zammad:7.0.1-0045`) to `crprdzammad.azurecr.io/zammad:<sha>`. The `deploy.yml` workflow does this on push to `main`.
3. Run the migrations job — populates the schema and the default `Setting` rows. The workflow does this via:

   ```bash
   az containerapp job update -n cajob-prd-zammad-init -g rg-prd-zammad \
     --image crprdzammad.azurecr.io/zammad:<sha>
   az containerapp job start  -n cajob-prd-zammad-init -g rg-prd-zammad
   ```

   Important: `az containerapp job start --image` silently replaces the entire container template (args/env/secrets/cpu/memory). Always `job update --image` first, then `job start` without `--image`. See [DA-107](https://linear.app/plugport/issue/DA-107) for the upstream Azure CLI bug.

4. Roll the four long-running apps to the new image (web, websocket, worker, scheduler). The deploy workflow does this — `ca-prd-zammad-web` is multi-container (Rails + nginx sidecar) and uses an atomic `--yaml` update so both containers flip in one revision. `opensearch` and `memcached` run upstream images and are not part of the per-deploy roll.

5. Apply the remaining manual Settings below. The previously-documented `Setting.set('es_url', ...)` is no longer needed — the entrypoint sets it automatically from `ELASTICSEARCH_HOST`/`ELASTICSEARCH_PORT` env vars (set on every Zammad-image container by `apps.tf`).

## Manual Settings

Run these in any order via the Rails console inside the web container. They are idempotent.

```bash
# Tell Zammad to store attachments on the mounted Azure Files share
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('storage_provider', 'File')"

# Public hostname (used in outbound mail, SSO callback URLs, etc.)
# Update this to operations.plugport.no once DA-92 lands the custom domain.
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('fqdn', 'operations.plugport.no')"

# Force HTTPS scheme in generated URLs
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('http_type', 'https')"
```

The initial search index is built by `cajob-prd-zammad-init` itself (the entrypoint's `zammad-init` dispatch handles `db:seed` + ES setup). Only run a manual rebuild after a Zammad version bump whose release notes flag a mapping change — see the version-bump runbook below.

## SSO setup (admin UI)

Once the app is up and the Settings above are in place:

1. Sign in to `https://operations.plugport.no` (or the env default domain until DA-92 lands) as the initial admin user. Zammad creates one on first boot; check the deploy logs for the password, then change it.
2. Go to **Settings → Security → Third Party Applications → Microsoft (Office 365)**.
3. Paste App ID, Tenant ID, and Client Secret. Retrieve the secret from Key Vault:

   ```bash
   az keyvault secret show \
     --vault-name kv-prd-zammad-ne \
     --name entra-zammad-client-secret \
     --query value -o tsv
   ```
4. Enable **Automatic account link on initial sign-in**, matched on email. Save.
5. Sign out, sign back in via the Microsoft button, confirm your user is linked.
6. Disable local password login: **Settings → Security → Base → Third-party login only**.

See `docs/features/sso-entra.md` for the longer SSO walkthrough.

## Version-bump runbook

For every `7.x.y → 7.x.z` deploy:

```bash
# 1. Spin up ephemeral staging from a PITR snapshot, smoke-test there first.
#    (See docs/features/staging.md)

# 2. Once green in staging, run the prod migration job. The deploy.yml
#    workflow does this automatically on push-to-main, but for a manual
#    out-of-band bump:
az containerapp job update -n cajob-prd-zammad-init -g rg-prd-zammad \
  --image crprdzammad.azurecr.io/zammad:<new-sha>
az containerapp job start  -n cajob-prd-zammad-init -g rg-prd-zammad

# 3. Roll the long-running apps via the normal deploy pipeline
#    (push to main, or `gh workflow run deploy.yml --ref main`).

# 4. Re-apply the searchindex rebuild only if release notes flag a mapping
#    change. Manual until DA-106 lands the dedicated reindex job:
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rake zammad:searchindex:rebuild
```

## Break-glass admin

Keep one local-password admin account active **even after** turning on "Third-party login only". Document its credentials in 1Password under the `Plug Zammad` shared vault. Reason: if Entra is unavailable, the operator still needs to log in to investigate.
