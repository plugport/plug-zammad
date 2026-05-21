# Zammad AI — Azure OpenAI runbook

Zammad 7's built-in AI features (ticket summary, customer mood, open questions, reply suggestions) talk to a dedicated Azure OpenAI deployment in our workload subscription. The infrastructure is provisioned by Terraform in `evinyacp/az-0265-infra/infrastructure/openai.tf` (DA-91); this doc covers what an operator does in Zammad to turn the features on.

## What's provisioned

| Resource | Where | Purpose |
|---|---|---|
| `oai-prd-zammad` | `rg-prd-zammad`, **Sweden Central** | Cognitive account, S0, public-network-disabled |
| `summary` deployment | `oai-prd-zammad` | `gpt-4.1-mini` @ 100k TPM, `DataZoneStandard` SKU |
| `reply` deployment | `oai-prd-zammad` | `gpt-4.1` @ 50k TPM, `DataZoneStandard` SKU |
| `pe-oai-prd-zammad` | `snet-data` | Private endpoint, resolves via `privatelink.openai.azure.com` |
| `kv-prd-zammad-ne/azure-openai-api-key` | KV | Cognitive account primary key |
| `kv-prd-zammad-ne/azure-openai-endpoint` | KV | `https://oai-prd-zammad.openai.azure.com/` |
| `budget-prd-zammad-openai` | Subscription budget | 500 NOK/mo, 80% actual + 100% forecast → oncall action group |

`DataZoneStandard` SKU keeps both at-rest and inference data within the EU per Microsoft Foundry deployment-types docs. Microsoft DPA covers GDPR, no separate legal step needed.

## Schema reality vs the original DA-91 sketch

The DA-91 issue draft proposed `ai_provider = 'azure_openai'` with a `models: {summarize, suggest_reply}` map. Verified against `lib/ai/provider/azure.rb` in `zammad/zammad`:

- **Provider key is `'azure'`** (mapped from `AI::Provider::Azure`), not `'azure_openai'`.
- **Config schema is single-endpoint**: `{ token, url_completions, url_embeddings, url_ocr }`. There is no `models:` map — Zammad 7.0.1 uses one chat-completions deployment for every AI feature on the instance.

Implication: the `reply` (gpt-4.1) deployment is unused by Zammad in 7.0.x — we use `summary` (gpt-4.1-mini) for all features. The `reply` deployment is kept provisioned for an eventual upstream change or per-feature override; cost is pay-per-token, so an unused deployment costs zero.

## Initial activation

Once the infra is live (verify with `az cognitiveservices account show -n oai-prd-zammad -g rg-prd-zammad` returns `provisioningState: Succeeded`), do this from the Zammad admin UI — Zammad 7 exposes the full AI Provider form so Rails console isn't needed.

### Step 1: Get the credentials

The endpoint is deterministic and not secret:

```
https://oai-prd-zammad.openai.azure.com/
```

The API key is in Key Vault as `kv-prd-zammad-ne/azure-openai-api-key`. Two ways to retrieve it:

- **From Key Vault** (requires `Key Vault Secrets User` role on the vault — Plug users typically don't have it by default; ask Eviny IT or use the worker-container path below):

  ```bash
  az keyvault secret show --vault-name kv-prd-zammad-ne \
    --name azure-openai-api-key --query value -o tsv
  ```

- **From the worker container** (the worker's MI has Secrets User; the key is mounted as an env var):

  ```bash
  az containerapp exec -n ca-prd-zammad-worker -g rg-prd-zammad --container worker
  # inside the pod:
  echo "Endpoint: $AZURE_OPENAI_ENDPOINT"
  echo "API key:  $AZURE_OPENAI_API_KEY"
  ```

### Step 2: Configure the AI Provider in admin UI

In Zammad admin, search for "AI" or navigate to **Settings → AI → AI Provider**. The Provider dropdown has multiple Azure options — pick **"Azure AI (legacy deployment-based endpoints)"**. The "legacy" label refers to the named-deployment URL pattern (`openai/deployments/<name>/chat/completions?api-version=...`) — which is exactly what our `openai.tf` provisions. It is stable and not being sunset; the non-legacy "Foundry endpoints" option is for a different routing model we don't use.

Fill in:

| Field | Value |
|---|---|
| Provider | `Azure AI (legacy deployment-based endpoints)` |
| Token | API key from step 1 |
| URL Completions | `https://oai-prd-zammad.openai.azure.com/openai/deployments/summary/chat/completions?api-version=2024-08-01-preview` |
| URL Embeddings | (leave blank — no embeddings deployment) |
| URL OCR | (leave blank — no vision deployment) |

Save. If config is valid, Zammad shows a "verified" status; if not, copy the error and check the worker logs.

### Step 3: Enable per-feature assistance

Same admin area (or sub-page **AI → AI Assistance**):

- **Ticket Summary** → On
- **Writing Assistant** → On

### Step 4: Smoke-test

Open any ticket — the summary panel should render within a couple of seconds. The Writing Assistant menu (the small ✨ button on reply forms) should offer "Improve writing", "Simplify", "Translate", etc.

If something fails, the worker container is where AI jobs run:

```bash
az containerapp logs show -n ca-prd-zammad-worker -g rg-prd-zammad --follow
```

`AI::Provider::Azure` is the log facility for auth/endpoint errors.

### Alternative: Rails console activation

Same effect as the UI, useful for scripted re-config or when admin UI isn't reachable:

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad --container web
# inside the pod:
cd /opt/zammad
bundle exec rails r "
  Setting.set('ai_provider', 'azure')
  Setting.set('ai_provider_config', {
    'token' => 'PASTE_KEY_HERE',
    'url_completions' => 'https://oai-prd-zammad.openai.azure.com/openai/deployments/summary/chat/completions?api-version=2024-08-01-preview'
  })
  Setting.set('ai_assistance_ticket_summary', true)
  Setting.set('ai_assistance_text_tools', true)
"
```

Note: `az containerapp exec --command "..."` returns `ClusterExecFailure code 500` for `rails r` — use the interactive shell path (no `--command` flag), then run `bundle exec rails r "..."` at the in-pod prompt. Also, `rails` is not on `PATH` — go through `/opt/zammad` and `bundle exec`.

## Permissions matrix

Default Zammad permissions are reasonable; tighten only if a specific group needs AI off.

| Role | AI access |
|---|---|
| Admin (1–2 people) | Full `admin.ai.*` — switch provider, model, see cost, kill-switch globally |
| Agent (default) | Enabled: ticket summary, reply suggest, mood/intent. Open from start. |
| Customer | No AI permissions |
| Sensitive group | If/when needed, create a Zammad group `Sensitive` and gate AI summary via group ACL |

Disable globally if needed (Rails console):

```ruby
Setting.set('ai_provider', false)
Permission.where("name LIKE 'admin.ai%'").update!(active: false)  # also hide settings from UI
```

## Operations

### Rotate the API key

```bash
# Cognitive Services has two keys for zero-downtime rotation.
NEW_KEY=$(az cognitiveservices account keys regenerate \
  -n oai-prd-zammad -g rg-prd-zammad --key-name Key2 --query key2 -o tsv)

# Update KV. The next worker-app revision picks it up via secret ref;
# Setting.set value in the DB still has the old key in the URL — re-run
# the activation step #2 above with the new key.
az keyvault secret set --vault-name kv-prd-zammad-ne \
  --name azure-openai-api-key --value "$NEW_KEY"

# Then regenerate Key1 once everything is on Key2 (and swap names back if you prefer Key1 as primary).
```

### Re-tune capacity

After one month of telemetry, look at the Azure OpenAI metrics blade — token rate, throttles, latency. Bump `capacity` on the deployment in `openai.tf` if throttling, or down if oversized.

### Budget breach

Alert fires at 80% actual or 100% forecast. First investigate which Zammad feature is driving tokens (worker logs), then either:
- Increase the budget intentionally (if scale is healthy)
- Disable a feature (e.g. `Setting.set('ai_assistance_text_tools', false)`)
- Move heavier work to a cheaper model

### Disable AI entirely (emergency)

```bash
az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
  --container web -- rails r "Setting.set('ai_provider', false)"
```

Effect is immediate — workers stop dispatching AI jobs. Cost goes to zero.

## Known limitations (Zammad 7.0.1)

- One provider per Zammad instance; can't use different models per feature.
- No native AAD-auth — must use API key. Watch for upstream support; switch to MI when available.
- Image-OCR support (`url_ocr`) requires a vision-capable deployment which we haven't provisioned. Add a `vision` deployment if/when that's wanted.
- Embeddings (`url_embeddings`) likewise — currently unused, no deployment.

## References

- Linear: [DA-91](https://linear.app/plugport/issue/DA-91)
- Upstream provider source: [`zammad/zammad/lib/ai/provider/azure.rb`](https://github.com/zammad/zammad/blob/develop/lib/ai/provider/azure.rb)
- MS Learn: [Foundry deployment types](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/deployment-types) (`DataZoneStandard` SKU rationale)
- Zammad docs: [Disabling the AI feature](https://docs.zammad.org/en/latest/admin/console/other-useful-commands.html) (kill-switch reference)
