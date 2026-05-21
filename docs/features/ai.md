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

Once the infra is live (verify with `az cognitiveservices account show -n oai-prd-zammad -g rg-prd-zammad` returns `provisioningState: Succeeded`):

1. Pull the API key and endpoint from Key Vault (`mi-prd-zammad-apps` already has Secrets User):

   ```bash
   API_KEY=$(az keyvault secret show --vault-name kv-prd-zammad-ne \
     --name azure-openai-api-key --query value -o tsv)
   ENDPOINT=$(az keyvault secret show --vault-name kv-prd-zammad-ne \
     --name azure-openai-endpoint --query value -o tsv)
   ```

2. Configure Zammad via Rails console on the web container. The OCR field can stay unset until we wire image-OCR support; embeddings likewise. The chat-completions URL must include the **deployment name** (`summary`) and an API version pinned to a recent stable value:

   ```bash
   az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
     --container web -- rails r "
       Setting.set('ai_provider', 'azure')
       Setting.set('ai_provider_config', {
         token: '$API_KEY',
         url_completions: '$ENDPOINT' + 'openai/deployments/summary/chat/completions?api-version=2024-08-01-preview'
       })
     "
   ```

3. Enable per-feature toggles. Each is a separate Setting per the seed schema (`db/seeds/settings.rb`):

   ```bash
   az containerapp exec -n ca-prd-zammad-web -g rg-prd-zammad \
     --container web -- rails r "
       Setting.set('ai_assistance_ticket_summary', true)
       Setting.set('ai_assistance_text_tools', true)
     "
   ```

4. Verify in the admin UI: **Settings → System → AI** shows the provider as `Azure` with the endpoint visible.

5. Smoke-test from the agent UI: open any ticket → the summary panel should render within a couple of seconds. If it doesn't, check `ca-prd-zammad-worker` console logs (`az containerapp logs show -n ca-prd-zammad-worker -g rg-prd-zammad --follow`) — `AI::Provider::Azure` log facility surfaces auth / endpoint errors.

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
