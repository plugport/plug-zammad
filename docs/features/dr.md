# Disaster recovery runbook

What we back up, where it lives, how to restore. Targets (per CLAUDE.md §10): **RTO 4 h, RPO 1 h**.

## What's backed up

| Asset | Mechanism | Retention | Geo |
|---|---|---|---|
| Postgres (`pg-prd-zammad-ne`) | Azure DB for PostgreSQL Flexible Server built-in PITR + full backups | 7 days | GRS — backups replicate NE → NW |
| Azure Files share `zammad-storage` (Zammad attachments) | Recovery Services Vault `rsv-prd-zammad`, policy `bp-prd-zammad-files-daily-14d` | 14 daily snapshots | RSV is GeoRedundant (NE → NW) |
| Azure Files share `opensearch-data` (ES index) | Same RSV / policy as above | 14 daily snapshots | GRS |
| Key Vault (`kv-prd-zammad-ne`) | KV soft-delete + purge protection | 90 days | KV replicates per-region by default |
| Container Apps revisions | Built-in revision history | N/A — only image is reconstructible from ACR | n/a |
| Container images (`crprdzammad`) | ACR Standard tier | Indefinite (no retention policy set) | LRS |

## Verifying backups are running

Run this from a host with the firewall opened to the state SA (see `infra-runbook.md` step 2):

```bash
# Postgres: confirm at least one Full backup, GRS enabled, 7-day retention
az postgres flexible-server backup list -n pg-prd-zammad-ne -g rg-prd-zammad
az postgres flexible-server show -n pg-prd-zammad-ne -g rg-prd-zammad \
  --query '{retentionDays: backup.backupRetentionDays, geo: backup.geoRedundantBackup, earliestRestore: backup.earliestRestoreDate}' \
  -o table

# Files shares: confirm both are Protected against the RSV with the daily-14d policy
az backup item list --resource-group rg-prd-zammad --vault-name rsv-prd-zammad \
  --backup-management-type AzureStorage --workload-type AzureFileShare -o table

# First scheduled snapshot fires at 03:00 Oslo; until then status is `IRPending`
# (Initial Replication Pending) which is normal.
```

State as of 2026-05-20:
- Postgres has at least one automatic Full backup, retention 7d, GRS enabled, `earliestRestoreDate` ~6 h ago.
- Both Files shares are protected by RSV (status `Healthy`), `IRPending` until 03:00 Oslo.

## Postgres point-in-time restore

PITR clones the server into a new Flexible Server resource. The original keeps running. After validation you cut over by repointing `POSTGRESQL_HOST` (in `apps.tf` locals) — or you swap the DNS A record on the private endpoint, depending on situation.

```bash
# Pick a target server name (must be globally unique, lowercase, hyphens OK)
TARGET=pg-prd-zammad-restoretest

# Restore point — must be within retention (last 7 days) and >= earliestRestoreDate.
# Format: YYYY-MM-DDTHH:MM:SSZ
POINT=$(date -u -v -30M +%Y-%m-%dT%H:%M:%SZ)  # 30 minutes ago

az postgres flexible-server restore \
  --resource-group rg-prd-zammad \
  --name "$TARGET" \
  --source-server pg-prd-zammad-ne \
  --restore-time "$POINT"
```

Restore typically takes 10–20 min. The new server inherits the source's SKU, storage, and network config. It does NOT inherit the Private Endpoint — you'll get a public-facing server unless you add a PE post-restore.

Smoke-test the restore:

```bash
# Connect from a network with line-of-sight to the new server (PE-less servers are
# reachable on the public endpoint once you add your IP to the FW)
az postgres flexible-server firewall-rule create \
  --resource-group rg-prd-zammad \
  --name "$TARGET" \
  --rule-name allow-my-ip \
  --start-ip-address "$(curl -s ifconfig.me)" \
  --end-ip-address   "$(curl -s ifconfig.me)"

az postgres flexible-server connect -n "$TARGET" -d zammad_production -u zammad_admin
# At the psql prompt:
#   SELECT count(*) FROM users;
#   SELECT max(updated_at) FROM tickets;
```

Verify row counts match expectations + `updated_at` reaches the restore point.

**Tear down** after validation:

```bash
az postgres flexible-server delete --resource-group rg-prd-zammad --name "$TARGET" --yes
```

## Azure Files restore

File-share restores happen via the RSV portal or `az backup` CLI. Two paths:

1. **Full share restore** — overwrite the share's contents with a snapshot.
2. **Item-level restore** — pick specific files/folders to recover.

```bash
# List available recovery points for the share
az backup recoverypoint list --resource-group rg-prd-zammad --vault-name rsv-prd-zammad \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --container-name 'StorageContainer;storage;rg-prd-zammad;stprdzammadne' \
  --item-name 'AzureFileShare;<friendlyName>' -o table

# Restore to a new share (safer than overwrite — surfaces the snapshot for inspection)
az backup restore restore-azurefileshare \
  --resource-group rg-prd-zammad --vault-name rsv-prd-zammad \
  --rp-name <recovery-point-name> \
  --source-storage-account-id /subscriptions/<sub>/resourceGroups/rg-prd-zammad/providers/Microsoft.Storage/storageAccounts/stprdzammadne \
  --source-file-share zammad-storage \
  --target-storage-account stprdzammadne \
  --target-file-share zammad-storage-restored \
  --resolve-conflict Overwrite
```

## Key Vault recovery

KV is purge-protected. A "deleted" KV is recoverable for 90 days:

```bash
az keyvault list-deleted --subscription <sub>
az keyvault recover --name kv-prd-zammad-ne --subscription <sub>
```

Same for individual secrets — they get soft-deleted and can be recovered via `az keyvault secret recover` within the retention window.

## Container images

ACR has no retention policy and stores all pushed tags indefinitely. To roll back to a known-good image:

```bash
az acr repository show-tags --name crprdzammad --repository zammad --orderby time_desc -o table

# Roll a single app
az containerapp update -n ca-prd-zammad-web -g rg-prd-zammad \
  --image crprdzammad.azurecr.io/zammad:<known-good-sha>
```

For the multi-container web app (Rails + nginx sidecar), use `--yaml` to update both atomically — same pattern as `deploy.yml`'s "Roll long-running apps" step.

## End-to-end recovery scenario

Worst case — `rg-prd-zammad` accidentally deleted (PE soft-delete kicks in for KV; Postgres has 7-day soft-delete; Storage account 14-day):

1. `az group create -n rg-prd-zammad -l norwayeast` + restore Terraform state from the backend SA (`az02654r55kbtfst`).
2. KV: `az keyvault recover --name kv-prd-zammad-ne`. Secrets come back with it.
3. Postgres: recover the original soft-deleted server, OR PITR-restore into a new server from the GRS-replicated backup.
4. Storage account: recover from soft-delete; both Files shares (and their snapshots) come back with the SA.
5. Run `terraform plan` to see what else needs rebuilding; expect Container Apps, VNet, ACR to all be missing.
6. `terraform apply` rebuilds infra. Container images are still in ACR (assuming ACR wasn't in the same RG — it is, so this requires ACR to be restored too. **TODO: consider moving ACR to a separate RG for defense-in-depth.**).
7. Trigger `deploy.yml workflow_dispatch` on `main` to roll the latest known-good image.

**Restore drills**: run a Postgres PITR + Files restore once per quarter, document timing in this file under "Last verified".

## Last verified

- 2026-05-20 — config inspected, snapshots scheduled, no restore drill performed yet. **TODO: run drill before going to general production.**
