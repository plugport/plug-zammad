# Post-install runbook

Every Container Apps deploy that introduces a fresh Zammad install or a version bump needs a handful of Rails-console settings to be written to the database. They are **not** environment variables — Zammad reads them from its `Setting` table at runtime.

## Order of operations (first deploy)

1. Provision Azure resources via Terraform (`infra/`).
2. Push the pinned `zammad/zammad:7.0.x` image to `crplugport.azurecr.io`.
3. Run the migrations job — populates the schema and the default `Setting` rows.
   ```bash
   az containerapp job start -n cajob-prd-zammad-init -g rg-prd-zammad
   ```
4. Start the long-running apps (`web`, `websocket`, `worker`, `scheduler`, `opensearch`, `memcached`). The deploy pipeline does this automatically; manual is `az containerapp update --image ... ` per app.
5. Apply the post-install Settings (below). Without these Zammad will not find the search backend, will write attachments into the DB, and will emit wrong URLs in mail.

## Settings to apply

```bash
# Point Zammad at our OpenSearch container
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('es_url', 'http://ca-prd-zammad-opensearch:9200')"

# Tell Zammad to store attachments on the mounted Azure Files share
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('storage_provider', 'File')"

# Public hostname (used in outbound mail, SSO callback URLs, etc.)
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('fqdn', 'operations.plugport.no')"

# Force HTTPS scheme in generated URLs
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('http_type', 'https')"

# Build the initial search index — required after enabling Elasticsearch
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rake zammad:searchindex:rebuild
```

## SSO setup (admin UI)

Once the app is up and the Settings above are in place:

1. Sign in to `https://operations.plugport.no` as the initial admin user (Zammad creates one on first boot; check the deploy logs for the password, then change it).
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

# 2. Once green in staging, run the prod migration job FIRST
az containerapp job start -n cajob-prd-zammad-init -g rg-prd-zammad \
  --image crplugport.azurecr.io/zammad:<new-sha>

# 3. Then roll the long-running apps via the normal CI/CD pipeline

# 4. Re-apply the searchindex rebuild only if release notes flag a mapping change
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rake zammad:searchindex:rebuild
```

## Break-glass admin

Keep one local-password admin account active **even after** turning on "Third-party login only". Document its credentials in 1Password under the `Plug Zammad` shared vault. Reason: if Entra is unavailable, the operator still needs to log in to investigate.
