# Terraform runbook — `evinyacp/az-0265-infra`

This repo's Terraform lives in [`evinyacp/az-0265-infra`](https://github.com/evinyacp/az-0265-infra) (Eviny ACP scaffold). The PR-time `terraform plan` and merge-time `terraform apply` workflows shipped with the scaffold are currently **broken** (see [DA-95](https://linear.app/plugport/issue/DA-95) — `startup_failure` on every run, suspected org-level Actions policy).

While DA-95 is unresolved we run Terraform **locally from the laptop**. The OIDC-wired service principal (`az-0265-sp`) is unused in this mode; we authenticate as the developer instead, who has Owner on the subscription via `az-0265-owners`.

This doc is the workflow. Discipline: every change still goes through a PR so the diff and `plan` output are reviewable; we just `apply` from the laptop after merge.

## One-time setup

```bash
# Install terraform 1.14.x (pin matches infrastructure/provider.tf)
# Recommended: tfenv or asdf so you can switch per-repo if needed
brew install tfenv
tfenv install 1.14.9
tfenv use 1.14.9

# Sign in
az login
az account set --subscription <az-0265-sub-id>

# Locate the state backend storage account
az storage account list -g DeployedByEACP-rg \
  --subscription <az-0265-sub-id> -o table
# Expect one account, name in the secrets as STORAGE_ACCOUNT_NAME on the infra repo.
```

## Per-change workflow

1. **Branch + edit** in `evinyacp/az-0265-infra`:

   ```bash
   cd ~/az-0265-infra            # or wherever you cloned it
   git checkout main && git pull
   git checkout -b eyvind/da-<n>-<slug>
   # edit files under infrastructure/
   ```

2. **Open the storage-account firewall** for your IP (the state backend has public access disabled by default; ACP's CI did this transparently):

   ```bash
   MY_IP=$(curl -s ifconfig.me)
   STATE_SA=<storage-account-name>  # from az storage account list above
   az storage account network-rule add -g DeployedByEACP-rg \
     --account-name $STATE_SA --ip-address $MY_IP \
     --subscription <az-0265-sub-id>
   sleep 30  # let the rule propagate
   ```

3. **Plan** against the canonical state:

   ```bash
   cd infrastructure
   terraform init \
     -backend-config="key=infrastructure.tfstate" \
     -backend-config="storage_account_name=$STATE_SA" \
     -backend-config="tenant_id=<plug-tenant-id>" \
     -backend-config="subscription_id=<az-0265-sub-id>"
   terraform fmt -check -recursive
   terraform validate
   terraform plan -var-file env/infrastructure.tfvars -out tfplan
   ```

4. **Open the PR** (`gh pr create`) and **paste the relevant `terraform plan` output as a comment** so the diff is reviewable in PR history. Quote-fence with ```` ```diff ```` so the additions/removals colour-code in the GitHub UI. Keep the comment ≤ 30 KB or chunk it.

5. **Merge** the PR via `gh pr merge --squash --delete-branch` after review.

6. **Apply** from the laptop, on `main`:

   ```bash
   git checkout main && git pull
   cd infrastructure
   terraform init   # in case backend config drifted
   terraform plan -var-file env/infrastructure.tfvars -out tfplan
   terraform apply tfplan
   ```

7. **Close the firewall** (always — leaving your home IP whitelisted on the state account is sloppy):

   ```bash
   az storage account network-rule remove -g DeployedByEACP-rg \
     --account-name $STATE_SA --ip-address $MY_IP \
     --subscription <az-0265-sub-id>
   ```

8. **Post the `apply` outcome** as a follow-up PR comment (or in the Linear issue). The state file holds the canonical record, but a one-line "applied 2026-XX-XX, no drift" comment makes the human trail easier to follow.

## State drift checks

Run periodically (or before any new PR):

```bash
terraform plan -var-file env/infrastructure.tfvars -detailed-exitcode
```

Exit code 0 = no changes, 2 = changes pending, 1 = error. If 2 with no PR open, someone has clicked in the portal and we need to either roll it back or import to state.

## When CI is restored (DA-95 closed)

Remove this runbook (or shrink it to the drift-check section). The scaffold workflows in `.github/workflows/` resume their normal job. Add a CLAUDE.md commit announcing the switch.
