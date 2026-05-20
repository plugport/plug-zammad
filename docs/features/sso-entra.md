# SSO — Entra ID (Microsoft Office 365 v2)

Step-by-step walkthrough for wiring Zammad's built-in Microsoft (Office 365) v2 OmniAuth strategy to a Plug Entra ID tenant. Summary lives in `CLAUDE.md` §8; this file is the long form with operational details.

## 1. Create the Entra App Registration

In the Entra admin center (Microsoft Entra ID → App registrations → **New registration**):

| Field | Value |
|---|---|
| Name | `Plug Zammad` |
| Supported account types | Accounts in this organizational directory only |
| Redirect URI | **Web** → `https://operations.plugport.no/auth/microsoft_office365_v2/callback` |

> ⚠️ The callback path `/auth/microsoft_office365_v2/callback` is hard-coded by Zammad's OmniAuth strategy. Do not change it.

After creation, capture:

- **Application (client) ID** — public.
- **Directory (tenant) ID** — public.

## 2. Create the client secret

Certificates & secrets → New client secret → expiry **24 months**.

Store the secret value in Azure Key Vault:

```bash
az keyvault secret set \
  --vault-name kv-prd-zammad \
  --name entra-zammad-client-secret \
  --value '<paste-secret-here>'
```

Open a Linear issue in the `Zammad` project with due date two weeks before expiry to remind us to rotate.

## 3. Grant API permissions

Microsoft Graph **delegated** permissions:

| Permission | Purpose |
|---|---|
| `openid` | OIDC sign-in |
| `profile` | Name claim |
| `email` | Email claim — Zammad uses this as the user identifier |
| `User.Read` | Read signed-in user's basic profile |

Then click **Grant admin consent for Plug**.

## 4. (Optional) Add the groups claim

If you want to map AD groups → Zammad roles automatically:

1. Token configuration → **Add groups claim** → Security groups → enable for ID token and access token.
2. Decide how Zammad consumes the claim:
   - **Option A (simpler)**: leave it off in Zammad and assign roles manually in the admin UI. Fine when user count is small.
   - **Option B (automated)**: add a post-login Ruby hook at `lib/zammad/extensions/entra_group_mapping.rb` that reads `auth.extra.raw_info.groups` and updates `user.roles`. Document the mapping table (group object ID → Zammad role name) inline.

## 5. Configure Zammad

Sign in to Zammad as an admin and go to **Settings → Security → Third Party Applications → Microsoft (Office 365)**:

1. Enable the integration.
2. Paste:
   - **App ID** (from step 1)
   - **App Secret** (retrieve from Key Vault: `az keyvault secret show --vault-name kv-prd-zammad --name entra-zammad-client-secret --query value -o tsv`)
   - **Tenant ID** (from step 1)
3. Enable **Automatic account link on initial sign-in** matched on email.
4. Save.

Test by signing out and signing back in via the Microsoft button. Verify the user record is linked and that the email matches.

## 6. Disable local password login

Once SSO works end-to-end:

**Settings → Security → Base → Third-party login only**.

Document any operator break-glass user (and where its credentials are stored) in `docs/features/post-install.md`.

## 7. Operational notes

- **Rotation**: when the client secret nears expiry, mint a new one in Entra, store in Key Vault under `entra-zammad-client-secret`, then paste the new value into the Zammad admin UI. Zammad does not auto-refresh.
- **Re-binding tenants**: if the Entra tenant changes (acquisition, restructure), the App Registration must be re-created and the redirect URI re-verified. Treat this as a separate Linear issue.
- **Sign-in failures**: check Container App logs (`az containerapp logs show -n ca-prd-zammad-web -g rg-prd-zammad --follow`) and Entra sign-in logs (Monitoring → Sign-in logs).
