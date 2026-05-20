# DNS + TLS — operations.plugport.no

Path A (Container Apps managed certificate) is the active path. Path B (Azure Front Door + WAF) is documented as a future option below.

## Path A — current

### Step 1. DNS

`plugport.no` is managed in [`evinyacp/eviny-dns`](https://github.com/evinyacp/eviny-dns) (Terraform).

```hcl
# In modules/plugport-no/main.tf (or equivalent)
resource "azurerm_dns_cname_record" "operations" {
  name                = "operations"
  zone_name           = "plugport.no"
  resource_group_name = "rg-eacp-dns"
  ttl                 = 3600
  record              = "ca-prd-zammad-web.<env>.azurecontainerapps.io"
}

resource "azurerm_dns_txt_record" "operations_asuid" {
  name                = "asuid.operations"
  zone_name           = "plugport.no"
  resource_group_name = "rg-eacp-dns"
  ttl                 = 3600

  record {
    value = "<custom-domain-verification-id from Container App>"
  }
}
```

PR workflow:

1. Branch off `main` in `evinyacp/eviny-dns`.
2. Open PR. Required: code owner approval from `@evinyacp/az-eacp-owner`.
3. Merge via **Squash and merge** (not merge commit).
4. `terraform apply` runs automatically after merge.

### Step 2. Get the verification ID

```bash
az containerapp show -n ca-prd-zammad-web -g rg-prd-zammad \
  --query properties.customDomainVerificationId -o tsv
```

Paste that into the `azurerm_dns_txt_record.operations_asuid` block before opening the PR.

### Step 3. Bind the custom domain

Azure Portal → `ca-prd-zammad-web` → **Custom domains** → **Add custom domain**.

- Domain: `operations.plugport.no`
- Validation: TXT (already added in step 1)
- Certificate: **Managed certificate** (Azure issues a Let's Encrypt cert and rotates it automatically)

Bind.

### Step 4. Verify

```bash
dig +short operations.plugport.no
# expect: ca-prd-zammad-web.<env>.azurecontainerapps.io.
#         <ip>

curl -Iv https://operations.plugport.no
# expect: HTTP/2 200, Server: nginx, Strict-Transport-Security header present,
#         valid Let's Encrypt certificate chain.
```

### Step 5. Security headers

Zammad's bundled nginx config emits sensible defaults. If overrides are needed (e.g. stricter CSP for embedded views):

- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Frame-Options: DENY`
- `Content-Security-Policy: <document any deviations from Zammad's default here>`

Test with [securityheaders.com](https://securityheaders.com/?q=operations.plugport.no) after any change.

## Path B — future option (Front Door + WAF)

When we want centralised rate-limiting, geo-fencing, or WAF rules, swap to Azure Front Door in front of the Container App. Tracked as a Linear issue under the `Zammad` project (open when needed).

High-level steps (for context only — do not implement until the issue is picked up):

1. Stand up `afd-prd-zammad` (Front Door Premium) with origin `ca-prd-zammad-web.<env>.azurecontainerapps.io`.
2. Add custom domain `operations.plugport.no` to Front Door — re-validate via TXT (a fresh `_dnsauth.operations` token).
3. Move the CNAME in `eviny-dns` from the Container App FQDN to the Front Door endpoint.
4. Configure WAF managed rule sets (OWASP, bot protection) and custom rules (rate-limit `/api/*`, geo-fence to Europe, require Entra ID for `/admin/*`).
5. Lock the Container App's ingress to accept traffic only via Front Door (`X-Azure-FDID` validation in nginx).
6. Verify with `curl -Iv https://operations.plugport.no` — expect the Front Door cert chain rather than Let's Encrypt.

## Troubleshooting

- **Cert stuck "Provisioning" beyond 24h**: most often the `asuid.<host>` TXT or the CNAME hasn't propagated. Re-check `dig`.
- **HTTP 404 after binding**: the Container App ingress is on the wrong port or the FQDN was bound to the wrong revision. Confirm via `az containerapp ingress show`.
- **HSTS preloading**: do not enable `preload` until we are confident in long-term HTTPS — once preloaded, rollback requires a removal request that takes weeks.
