# SSO — Entra ID (Microsoft Office 365 OmniAuth)

Step-by-step walkthrough for wiring Zammad's built-in Microsoft OmniAuth strategy to the Eviny Entra tenant where Plug users live. Summary lives in `CLAUDE.md` §8; this file is the long form with operational details and lessons from the DA-93 go-live.

## Strategy name

Zammad's OmniAuth strategy is `microsoft_office365` — **no `_v2` suffix**. Earlier drafts of CLAUDE.md and this file used `microsoft_office365_v2` (taken from outdated docs); that's wrong. The callback path is:

```
/auth/microsoft_office365/callback
```

The Zammad admin-UI label is just **Microsoft** (not "Microsoft (Office 365)"); in Norwegian Zammad it shows as "Autentisering via Microsoft".

## Tenant

Plug users (`@plugport.no`) are native accounts in the **Eviny AS** Entra tenant — they are not B2B guests from a separate Plug tenant. App Registration therefore goes in the Eviny tenant:

- Tenant ID: `12f1bdca-9eec-45f6-a63e-2061b957e8ee`
- Domain: `eviny.no`

Sign in to `az` as a Plug user (e.g. `Eyvind.Bohne-Kjersem@plugport.no`); `az account show` confirms the tenant.

## 1. Create the App Registration

Either via the Entra portal or via `az`. The CLI is much faster:

```bash
az ad app create \
  --display-name "Plug Zammad" \
  --sign-in-audience "AzureADMyOrg" \
  --web-redirect-uris "https://operations.plugport.no/auth/microsoft_office365/callback"
```

Capture the returned `appId` (client ID) and `id` (object ID). Tenant ID is the one above.

Then create a service principal so the app is usable as an OAuth client:

```bash
az ad sp create --id <appId>
```

Reference values for the existing prod registration:

| Field | Value |
|---|---|
| Display name | `Plug Zammad` |
| App (client) ID | `6a0ccd3c-7548-4339-ba04-4c8a11ddd7c2` |
| Object ID | `35b92f70-fbde-4369-924e-6f9adb90f28d` |
| Tenant ID | `12f1bdca-9eec-45f6-a63e-2061b957e8ee` |
| Redirect URI (Web) | `https://operations.plugport.no/auth/microsoft_office365/callback` |

## 2. Grant API permissions

Microsoft Graph **delegated** permissions:

| Permission | Graph permission ID | Purpose |
|---|---|---|
| `openid` | `37f7f235-527c-4136-accd-4a02d197296e` | OIDC sign-in |
| `profile` | `14dad69e-099b-42c9-810b-d002981feec1` | Name claim |
| `email` | `64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0` | Email claim — Zammad uses this as the user identifier |
| `User.Read` | `e1fe6dd8-ba31-4d61-89e7-88639da4683d` | Read signed-in user's basic profile |

```bash
APP_ID=<appId>
GRAPH=00000003-0000-0000-c000-000000000000
for PERM in 37f7f235-527c-4136-accd-4a02d197296e \
            14dad69e-099b-42c9-810b-d002981feec1 \
            64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0 \
            e1fe6dd8-ba31-4d61-89e7-88639da4683d; do
  az ad app permission add --id "$APP_ID" --api "$GRAPH" --api-permissions "$PERM=Scope"
done
```

Then **admin consent**:

```bash
az ad app permission admin-consent --id "$APP_ID"
```

⚠️ Admin consent requires `Application Administrator`, `Cloud Application Administrator`, or `Global Administrator` role in the Eviny tenant. Plug users typically don't have any of these — you'll get `Authorization_RequestDenied`. In that case either:

- Ask Eviny IT to run the command for you (samleboks), or
- Test sign-in first: if the tenant allows user-level consent for openid/profile/email/User.Read, the user gets a consent prompt on first sign-in and admin consent is not needed. Most Plug-relevant tenants do allow this — try before escalating.

## 3. Create and store the client secret

```bash
az ad app credential reset \
  --id "$APP_ID" \
  --display-name "zammad-omniauth-$(date +%Y-%m)" \
  --years 2 \
  --append
```

`--append` keeps any existing secrets in place so rotation doesn't break in-flight auth.

Store the returned `password` in Key Vault via the ARM control plane (the vault has `public_network_access_enabled = false`, so data-plane `az keyvault secret set` from a laptop fails unless you punch a firewall hole first):

```bash
SUB=7ffb20c8-2855-49e4-99f0-23ea9bcb706e
BODY=$(mktemp); chmod 600 "$BODY"
printf '{"properties":{"value":"%s","contentType":"text/plain","attributes":{"enabled":true}}}' "<paste-secret>" > "$BODY"
az rest --method put \
  --uri "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-prd-zammad/providers/Microsoft.KeyVault/vaults/kv-prd-zammad-ne/secrets/entra-zammad-client-secret?api-version=2023-07-01" \
  --body "@$BODY"
rm -f "$BODY"
```

Open a Linear issue in the `Zammad` project with due-date two weeks before expiry to remind us to rotate.

## 4. Configure Zammad

Sign in to Zammad as an existing admin. Navigate via admin search ("microsoft" or "office365") or directly to **Settings → Security → Third-party Applications → Microsoft**:

| Field | Value |
|---|---|
| Toggle at top | On |
| **App ID** | client ID from step 1 |
| **App Secret** | the secret value (retrieve via `az keyvault secret show --vault-name kv-prd-zammad-ne --name entra-zammad-client-secret --query value -o tsv` — requires Key Vault Secrets User role on the vault) |
| **App Tenant ID** | `12f1bdca-9eec-45f6-a63e-2061b957e8ee` |

Save.

**Important: also enable auto-link.** Setting name `auth_third_party_auto_link_at_inital_login` (note the upstream typo "inital"). Without this, the first SSO sign-in tries to *create* a new user with the Entra email, fails with 422 "Email address X is already used for another user" because the local admin you created earlier already owns that email, and the Microsoft identity never gets linked.

UI: same Settings → Security area, toggle "Automatic account link on initial sign-in". Or via Rails console:

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad --container web
# inside:
cd /opt/zammad
bundle exec rails r "Setting.set('auth_third_party_auto_link_at_inital_login', true)"
```

## 5. Test sign-in

1. Sign out as local admin.
2. Click "Sign in via Microsoft" on the login screen.
3. If admin consent is in place: straight to Zammad, signed in as the linked user.
4. If admin consent is missing but user consent is allowed: consent screen → click through → signed in.
5. If both missing: `AADSTS65001` — go back to step 2 and arrange admin consent.

Check Container App logs in a second terminal for OmniAuth stack traces:

```bash
az containerapp logs show -n ca-prd-zammad-web -g rg-prd-zammad --follow
```

## 6. Break-glass admin (required before disabling local login)

Before turning off local password login, ensure a break-glass local-password admin exists and credentials are stored somewhere reachable when SSO is broken (Entra outage, expired secret, network split). Don't use your own SSO-linked account — pick a dedicated `breakglass@plugport.no` (or similar) account.

1. Create the user via Zammad admin UI with a strong password, Admin + Agent roles.
2. Store the password in 1Password under the shared "Plug Zammad" vault.
3. Document the username + 1Password item link in `docs/features/post-install.md`.

## 7. Disable local password login

Once SSO works end-to-end **and** the break-glass admin is verified:

**Settings → Security → Base → "Third-party login only"** → on.

After this, the only way back in for non-SSO users is the break-glass account.

## 8. Operational notes

- **Secret rotation**: when the client secret nears expiry, mint a new one in Entra (`az ad app credential reset ... --append`), store in KV under `entra-zammad-client-secret`, then paste the new value into the Zammad admin UI. Zammad does not auto-refresh — the old value lives in Postgres until manually replaced.
- **Re-binding tenants**: if the Entra tenant changes (acquisition, restructure), the App Registration must be re-created and the redirect URI re-verified. Treat this as a separate Linear issue.
- **Sign-in failures**: check Container App logs (above) and Entra sign-in logs (Entra portal → Monitoring → Sign-in logs → filter by `Plug Zammad` application).
- **HTTPS requirement**: Entra rejects the OAuth callback unless `redirect_uri` is `https://`. This depends on Zammad generating https URLs, which depends on `X-Forwarded-Proto: https` reaching Rails — fixed in DA-119 (`NGINX_SERVER_SCHEME=https` on the nginx sidecar + `127.0.0.1` in `RAILS_TRUSTED_PROXIES`). If you ever see `http://` in the redirect URL of an OAuth error, that fix has regressed.
