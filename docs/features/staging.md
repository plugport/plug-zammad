# Staging strategy

Hybrid model — daily ops uses Container Apps revisions (blue/green); Zammad version bumps spin up a short-lived parallel stack.

## Why hybrid

Container Apps revisions share the underlying Postgres and OpenSearch state. The moment a new revision runs `rake db:migrate`, the old revision can no longer talk to the same database — schema rollback via revisions is an illusion.

For day-to-day config / overlay / env-var changes the schema is stable, so revisions work fine. For Zammad version bumps that touch the schema we need a real second stack with its own Postgres.

## When to use which path

| Change | Path | Why |
|---|---|---|
| Env-var tweak, sidecar config, nginx rule | Revisions | No schema change |
| Plug-overlay code change at same Zammad image | Revisions | No schema change |
| Replica/CPU/memory sizing | Revisions | No schema change |
| Zammad patch (`7.0.4 → 7.0.5`) | **Ephemeral staging** | Migrations may run |
| Zammad minor (`7.0 → 7.1`) | **Ephemeral staging** | Migrations almost certain |
| Zammad major (`7 → 8`) | **Ephemeral staging** + extra dry-run window | Breaking changes possible |

## Revisions path

```bash
# Build and push the new image
docker build -t crplugport.azurecr.io/zammad:<sha> .
docker push crplugport.azurecr.io/zammad:<sha>

# Roll a new revision at 0% traffic
az containerapp update -n ca-prd-zammad-web -g rg-prd-zammad \
  --image crplugport.azurecr.io/zammad:<sha> \
  --revision-suffix <sha>

# Smoke-test the new revision via its preview FQDN
curl -I https://ca-prd-zammad-web--<sha>.<env>.azurecontainerapps.io/

# Promote to 100%
az containerapp ingress traffic set -n ca-prd-zammad-web -g rg-prd-zammad \
  --revision-weight <sha>=100

# Rollback if needed
az containerapp revision activate -n ca-prd-zammad-web -g rg-prd-zammad --revision <previous>
```

## Ephemeral staging path

Terraform `module.staging` lives at `infra/modules/staging` (to be authored). It provisions, on demand:

- `pg-stg-zammad` (Flexible Server, restored from the latest PITR snapshot of prod)
- `ca-prd-zammad-{web,websocket,worker,scheduler,opensearch,memcached}-staging`
- `cajob-stg-zammad-init`
- The same Key Vault references and VNet integration as prod

### Runbook

```bash
# 1. Spin up
cd infra
terraform init
terraform apply -target=module.staging \
  -var="zammad_image=crplugport.azurecr.io/zammad:<sha>" \
  -var="pitr_restore_point=$(date -u +%FT%TZ)"

# 2. Run migrations on staging
az containerapp job start -n cajob-stg-zammad-init -g rg-prd-zammad

# 3. Smoke tests
./scripts/smoke-test.sh https://ca-stg-zammad-web.<env>.azurecontainerapps.io

# 4. If green: deploy to prod via the normal CI/CD pipeline.
# If red: investigate, fix the image, re-apply step 1 with a new tag.

# 5. Tear down (always — staging is not a permanent environment)
terraform destroy -target=module.staging
```

### Cost

Staging in the off state: ~0 NOK. During a typical version-bump test (≈2–4 hours active): roughly 50–200 NOK per run, dominated by the Flexible Server SKU. Tear-down is the most important step of the runbook.

### What staging does *not* test

- Real prod traffic patterns (volume, agent concurrency, search load).
- SMTP delivery to real recipients (unless we configure a staging SMTP and a sandbox domain).
- Entra SSO against the prod App Registration — staging should use a separate App Registration with a different redirect URI (`https://ca-stg-zammad-web.<env>.azurecontainerapps.io/auth/microsoft_office365_v2/callback`).

These are accepted gaps. Adding a permanent always-on staging environment is intentionally out of scope; the cost/benefit doesn't justify it for an internal helpdesk.
