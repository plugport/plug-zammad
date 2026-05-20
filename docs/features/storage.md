# Attachment storage — Azure Files (SMB)

Zammad stores ticket attachments in one of three places, selected at runtime via `Setting.set('storage_provider', '<value>')`. We use the **`File`** provider, backed by a mounted Azure Files share.

## Why Azure Files, not Blob

Azure Container Apps supports two storage volume types: `EmptyDir` and `AzureFile`. **Blob storage is not natively mountable on Container Apps** — it would require a blobfuse2 sidecar (unofficial) or NFS Blob (preview, regional). Azure Files (SMB) is the supported path, and Zammad's `File` provider treats the mount as an ordinary filesystem.

We accept the trade-offs:

- Higher per-GB cost than Blob (~3–4×).
- POSIX advisory locks (`flock`) do **not** propagate reliably over SMB. Zammad does not depend on advisory locks for attachment writes, but any future feature that does would need verification before relying on it.
- 10–50 ms latency vs local disk. Acceptable for attachment read/write; would be terrible for database files.

## Resource layout

| Resource | Purpose |
|---|---|
| `stprdzammad` | Storage Account (GRS) |
| `stprdzammad/zammad-storage` | File share — mounted into `ca-prd-zammad-{web,worker}` at `/opt/zammad/storage` |

The mount is declared on the Container Apps environment as a named storage definition, then referenced from each app's `template.volumes`.

```hcl
# Sketch (full Terraform lives under infra/)
resource "azurerm_container_app_environment_storage" "zammad" {
  name                         = "zammad-storage"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = azurerm_storage_account.st.name
  share_name                   = "zammad-storage"
  access_mode                  = "ReadWrite"
  access_key                   = azurerm_storage_account.st.primary_access_key  # via Key Vault
}
```

## Post-deploy step

After the first boot, tell Zammad to use the filesystem:

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rails r "Setting.set('storage_provider', 'File')"
```

Existing tickets keep their attachments where they were. New attachments land under `/opt/zammad/storage/<hash-tree>/`.

## Migrating existing attachments

If we ever migrate from `DB` to `File` (or vice versa), use Zammad's built-in migration rake task:

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  -- rake zammad:store:migrate FROM=DB TO=File
```

Run this on a quiet window — it streams every attachment row, so it can take minutes to hours depending on volume.

## Backups

The Storage Account is GRS, replicating to the paired region. We also enable a **daily file-share snapshot** with 14-day retention:

```bash
az storage share-rm snapshot -n zammad-storage --storage-account stprdzammad
```

Schedule via Azure Backup → backup policy `bp-prd-zammad-fileshare`. RPO target: 24h. Combined with Postgres 7-day PITR, total RTO for a full restore is well under 4h.

## Escape valves

If attachment throughput becomes a bottleneck (file-share IOPS saturation or `flock`-dependent feature needs) we have two clean exits:

1. **S3 + MinIO sidecar**: stand up a MinIO Container App fronting the same Storage Account as Blob, point Zammad's `S3_URL` at it, run `rake zammad:store:migrate FROM=File TO=S3`.
2. **NFS Blob (preview)**: drop SMB for NFS-mounted Blob if Microsoft promotes it out of preview in the right region.

Both are tracked as future Linear issues — pick one if telemetry shows we need it.
