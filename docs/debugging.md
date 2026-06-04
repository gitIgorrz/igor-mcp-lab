# Debugging Guide

A practical reference for diagnosing issues across the stack: Azure resources,
HCP Terraform, GitHub Actions, and the MCP server itself.

---

## Table of contents

1. [Git commands reference](#git-commands-reference)
2. [The JSON-file technique for complex az commands](#the-json-file-technique)
3. [Azure CLI — resource status](#azure-cli--resource-status)
4. [GitHub CLI — Actions runs and PRs](#github-cli--actions-runs-and-prs)
5. [HCP Terraform — workspace and runs](#hcp-terraform--workspace-and-runs)
6. [Container logs and health](#container-logs-and-health)
7. [Common errors and fixes](#common-errors-and-fixes)

---

## Git commands reference

A reference of the Git and GitHub CLI commands used throughout this project,
with explanations of when and why each one is needed.

### Everyday commands

```bash
# Check current branch and what has changed
git status

# See staged and unstaged diffs before committing
git diff
git diff --staged

# View recent commit history with one-line summaries
git log --oneline -10

# Update your local main to match the remote
git checkout main
git pull origin main
```

### Branching

```bash
# Create and switch to a new branch in one step
git checkout -b feat/my-new-tool

# List all local branches (* = current)
git branch

# List all branches including remote-tracking ones
git branch -a

# Delete a branch after its PR is merged
git branch -d feat/my-new-tool        # safe delete (fails if unmerged)
git push origin --delete feat/my-new-tool  # delete from GitHub too
```

### Staging and committing

```bash
# Stage specific files (preferred — avoids accidentally committing secrets)
git add src/tools/my-tool.ts
git add infra/main.tf

# Stage everything in a directory
git add src/

# Unstage a file you added by mistake
git restore --staged path/to/file.ts

# Commit with a conventional message
git commit -m "feat: add list-resource-groups tool"

# Multi-line commit message (the heredoc keeps it readable in scripts)
git commit -m "$(cat <<'EOF'
feat: add list-resource-groups tool

Lists all resource groups in the active subscription.
Useful for exploring the Azure environment from an AI assistant.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Pushing and PRs

```bash
# Push a new branch and set its upstream in one step
git push origin feat/my-new-tool

# After upstream is set, subsequent pushes are just:
git push

# Create a PR from the command line (body from a file avoids shell quoting issues)
gh pr create \
  --title "feat: add list-resource-groups tool" \
  --body-file /tmp/pr-body.md

# Create a PR with an inline body (fine for short descriptions)
gh pr create \
  --title "fix: suppress az container restart false negative" \
  --body "Appends || true to suppress HTTP 200 OK being treated as error."

# List open PRs
gh pr list --repo <owner>/<repo>

# Merge a PR (squash = one clean commit on main, admin = bypass review if needed)
gh pr merge 4 --squash --delete-branch
gh pr merge 4 --squash --delete-branch --admin   # bypass branch protection
```

### Fixing a conflicted PR

When a PR branch has many commits and main has moved on, rebase often conflicts
on every intermediate commit. The cleanest fix is a fresh branch:

```bash
# Abort a rebase that's going badly
git rebase --abort

# Reset your local main to exactly match the remote (discards local divergence)
git checkout main
git reset --hard origin/main

# Create a clean branch with only your intended change
git checkout -b fix/your-change-v2
# ... make the change ...
git commit -m "fix: ..."
git push origin fix/your-change-v2

# Close the old conflicted PR
gh pr close <old-pr-number> --comment "Superseded by #<new-pr-number>"
```

> `git reset --hard origin/main` is destructive — it discards any local commits
> on `main` that aren't on the remote. Only use it when your local `main` has
> diverged unintentionally (e.g. after a failed rebase).

### Tagging a release

```bash
# Create an annotated tag (includes a message, stored as a full Git object)
git tag -a v0.1.0 -m "Initial lab deployment — MCP server live on Azure"

# Push the tag to GitHub (tags are not pushed with a normal git push)
git push origin v0.1.0

# List all tags
git tag

# Show details of a specific tag
git show v0.1.0
```

Tags appear under **Releases** on GitHub once pushed. You can also create a
release from a tag via:

```bash
gh release create v0.1.0 \
  --title "v0.1.0 — Initial lab deployment" \
  --notes-file CHANGELOG.md
```

### Inspecting what changed

```bash
# Show files changed between two branches
git diff main...feat/my-branch --name-only

# Show full diff between current branch and main
git diff main...HEAD

# Find which commit introduced a specific line (useful for debugging regressions)
git log -S "StreamableHTTPServerTransport" --oneline

# Show what changed in a specific commit
git show <commit-hash>
```

---

## The JSON-file technique

When working in PowerShell, the `az` CLI sometimes rejects complex JSON passed
directly on the command line because PowerShell parses single quotes, braces, and
colons in ways that corrupt the JSON before `az` sees it.

**The workaround:** write the JSON to a file in `$env:TEMP`, then pass the file path
to the command. The `@` prefix tells `az` to read from a file instead of the argument.

```powershell
# 1. Write the JSON payload to a temp file
$json = @'
{
  "id": "/subscriptions/.../roleAssignments/...",
  "conditionVersion": "2.0",
  "condition": "((!(ActionMatches{...})))"
}
'@
$json | Out-File -Encoding utf8 "$env:TEMP\payload.json"

# 2. Pass the file path to the az command
az role assignment update --role-assignment "$env:TEMP\payload.json"
```

This was used in this project to update the ABAC condition on the
`User Access Administrator` role assignment (see the session history for the
exact payload). The same pattern applies to any `az` command that takes a
`--parameters` or `--body` flag.

**Why not use Bash?**  
Git Bash on Windows translates Unix-style paths (e.g. `/subscriptions/...`)
into Windows paths (`C:/Program Files/Git/subscriptions/...`) before they
reach `az`, which causes `MissingSubscription` errors. Use PowerShell or
pass paths via a file to avoid this.

---

## Azure CLI — resource status

All commands below run in PowerShell. Swap `az` for a Bash terminal if preferred.

### Verify authentication

```powershell
az account show
# Should show your subscription name, ID, and the signed-in user.
# If this fails, run: az login
```

### Resource group

```powershell
# List all resource groups in the subscription
az group list --query "[].{name:name, location:location, state:properties.provisioningState}" -o table

# Check a specific group
az group show --name rg-<project> --query "{name:name, state:properties.provisioningState}"
```

### Azure Container Registry (ACR)

```powershell
# List ACR instances in the resource group
az acr list --resource-group rg-<project> --query "[].{name:name, loginServer:loginServer}" -o table

# List repositories (images) in the ACR
az acr repository list --name <acr-name> -o table

# Show tags for a specific image
az acr repository show-tags --name <acr-name> --repository <image-name> -o table
```

### Azure Container Instance (ACI)

```powershell
# Check container group state and restart count
az container show `
  --resource-group rg-<project> `
  --name aci-<project> `
  --query "{state:instanceView.state, restartCount:containers[0].instanceView.restartCount, currentState:containers[0].instanceView.currentState.state}" `
  -o table

# Get recent events (probe failures, image pulls, kills)
az container show `
  --resource-group rg-<project> `
  --name aci-<project> `
  --query "containers[0].instanceView.events[*].{message:message, type:type, firstTimestamp:firstTimestamp}" `
  -o table
```

**What to look for in events:**
- `Pulling` / `Pulled` — image pull started and completed
- `Started` — container process started; restart count increments if this repeats
- `Liveness probe failed` — `/health` endpoint not responding; too many → container killed
- `Readiness probe failed` — container not ready to serve traffic
- `Killing` — ACI terminated the container (usually follows repeated probe failures)
- `BackOff` — ACI is waiting before retrying a crashed container

### RBAC and role assignments

```powershell
# List all role assignments for the service principal
az role assignment list `
  --assignee "<sp-object-id>" `
  --all `
  --query "[].{role:roleDefinitionName, scope:scope, condition:condition}" `
  -o table

# List federated credentials on the app registration
az ad app federated-credential list `
  --id "<app-object-id>" `
  --query "[].{name:name, issuer:issuer, subject:subject}" `
  -o table
```

### Manual health check from CLI

```powershell
# Hit the health endpoint directly (bypasses ACI probes)
curl -s http://<aci-fqdn>:3000/health

# Call the echo tool directly
curl -s -X POST http://<aci-fqdn>:3000/mcp `
  -H "Content-Type: application/json" `
  -H "Accept: application/json, text/event-stream" `
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"text":"ping"}}}'
```

---

## GitHub CLI — Actions runs and PRs

### List recent runs

```powershell
gh run list --repo <owner>/<repo> --limit 10
```

Output columns: status, name, workflow, branch, event, run ID, duration, created.

### Watch a run live

```powershell
gh run watch <run-id> --repo <owner>/<repo>
# Refreshes every 3s. Press Ctrl+C to stop watching (run continues).
```

### Get failure details

```powershell
# Show all failed step logs
gh run view <run-id> --repo <owner>/<repo> --log-failed

# Filter for specific error keywords
gh run view <run-id> --repo <owner>/<repo> --log-failed 2>&1 |
  Select-String "Error:|failed|invalid|missing" |
  Select-Object -First 20
```

### Check PR status checks

```powershell
gh pr checks <pr-number> --repo <owner>/<repo>
```

### Re-run a failed job

```powershell
gh run rerun <run-id> --repo <owner>/<repo>

# Re-run only the failed jobs (not the whole run)
gh run rerun <run-id> --repo <owner>/<repo> --failed
```

**What to look for in GitHub Actions logs:**
- `Process completed with exit code 1` — step failed; look at the lines immediately above
- `##[error]` prefixed lines — GitHub captures these as the reported error
- Docker build failures usually show the failing `RUN` command and the error output
- `ARM_*` missing errors → auth issue (see [Common errors](#common-errors-and-fixes))

---

## HCP Terraform — workspace and runs

### Finding runs

All runs for this workspace:  
`https://app.terraform.io/app/<your-org>/workspaces/<your-workspace>/runs`

Each run has:
- **Plan log** — full Terraform output including provider initialisation messages
- **Apply log** — output of the apply phase (if the run reached apply)
- **Resources** — summary of `+N to add / ~N to change / -N to destroy`

### What to look for in plan logs

| Message | Meaning |
|---------|---------|
| `configuration for Azure is invalid: missing required value(s): Azure client ID` | `ARM_CLIENT_ID` env var not set in workspace. Check workspace variables. |
| `unable to build authorizer... launching Azure CLI: exec: "az": not found` | `use_oidc = true` in provider but no OIDC token — provider fell through to CLI auth. Remove `use_oidc` if using client secret. |
| `Error: No value for required variable "tfc_workload_identity_token_azurerm"` | HCP TF not auto-populating the workload identity variable. Check `TFC_WORKLOAD_IDENTITY_AUDIENCE_AZURERM` is set as workspace env var. |
| `AuthorizationFailed: does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/delete'` | ABAC condition on User Access Administrator uses `@Request` instead of `@Resource` for delete. Run `az role assignment update` to fix. |
| `No changes. Your infrastructure matches the configuration.` | Plan succeeded, no drift — normal after a clean apply. |

### Workspace ID

Your workspace ID (format: `ws-XXXXXXXXXXXXXXXX`) is shown at the top of
**Settings → General** in the HCP TF UI. It can be used directly in API calls:

```bash
curl -s \
  -H "Authorization: Bearer $TF_API_TOKEN" \
  "https://app.terraform.io/api/v2/workspaces/<workspace-id>/runs" \
  | jq '.data[0] | {id: .id, status: .attributes.status}'
```

---

## Container logs and health

### Get live container logs

```powershell
az container logs `
  --resource-group rg-<project> `
  --name aci-<project>

# Follow logs (streams until Ctrl+C)
az container logs `
  --resource-group rg-<project> `
  --name aci-<project> `
  --follow
```

A healthy startup produces exactly one log line:

```
<your-server-name> listening on :3000
```

If you see no output or an error before that line, the container is crashing before Express starts.

### Azure Portal — Events tab

For visual event history: Azure Portal → Container instances → `aci-<project>` → **Events** tab.

Events show probe failures with timestamps and counts, which helps distinguish:
- **Transient** probe failures (3 failures then recovers) — usually a slow cold start; increase `initial_delay_seconds` in `infra/main.tf`
- **Persistent** failures (container keeps restarting) — application crash; check container logs

### Probe configuration (infra/main.tf)

```hcl
liveness_probe {
  http_get { path = "/health"; port = 3000; scheme = "http" }
  initial_delay_seconds = 15   # wait before first probe
  period_seconds        = 20   # probe interval
  failure_threshold     = 3    # kills container after 3 consecutive failures
}
readiness_probe {
  http_get { path = "/health"; port = 3000; scheme = "http" }
  initial_delay_seconds = 5
  period_seconds        = 10
}
```

If probe failures appear consistently after `az container restart`, the server may be
taking more than 15 seconds to initialise. Increase `initial_delay_seconds`.

---

## Common errors and fixes

### `az`: command gives `MissingSubscription` in Bash

**Cause:** Git Bash translates `/subscriptions/...` to a Windows path.  
**Fix:** Use PowerShell, or write the scope/path to a file and pass it with `@file.json`.

### HCP TF apply: `InaccessibleImage` 400 error on ACI creation

**Cause:** Terraform tried to create the ACI before the Docker image existed in ACR. Occurs on fresh deployments when Terraform and GitHub Actions run in parallel.

**What happens now:** `null_resource.wait_for_image` polls ACR using the Docker v2 registry API (via the ARM client credentials from workspace env vars). The ACI creation is blocked until the image appears, up to 5 minutes. If it never appears, the apply fails with a clear message.

**If it still fails after 5 minutes:** Check that the GitHub Actions `build-push` job completed successfully and the image is in ACR:
```powershell
az acr repository show-tags --name <acr-name> --repository <project> -o table
```

### `az container restart` exits with `ERROR: Operation returned an invalid status 'OK'`

**Cause:** Known Azure CLI bug — the restart API returns HTTP 200 OK, which the CLI incorrectly treats as an error. The restart actually succeeded.  
**Fix:** Append `|| true` in scripts. Confirm restart worked by polling `/health`.

### GitHub Actions: `ARM_*` variables not set / auth fails

**Cause:** The `azure/login` step didn't run, or the federated credential subject
doesn't match the workflow trigger.  
**Check:**
```powershell
# Verify federated credentials registered
az ad app federated-credential list `
  --id "<app-object-id>" `
  --query "[].{name:name,subject:subject}" -o table
```

Expected subjects:
- `repo:<owner>/<repo>:ref:refs/heads/main` — for push to main
- `repo:<owner>/<repo>:pull_request` — for PRs

### HCP TF plan: `missing required value(s): Azure client ID`

**Cause:** `ARM_CLIENT_ID` not available in HCP TF remote execution environment.  
**Check workspace variables:** ensure `ARM_CLIENT_ID`, `ARM_TENANT_ID`,
`ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_SECRET` are all set as **Environment variables**
(not Terraform variables) in the workspace.

### Merge conflict when rebasing

If a PR branch has many intermediate commits, rebase will conflict on every one of them.  
**Preferred fix:** abort the rebase, delete the branch, create a fresh branch off
`main`, and cherry-pick only the final change:

```bash
git rebase --abort
git checkout main && git pull
git checkout -b fix/your-change
# make the change
git commit && git push
```

### `terraform destroy` fails on `azurerm_role_assignment` with 403

**Cause:** The ABAC condition on User Access Administrator uses `@Request` for the
`delete` clause, but Azure evaluates delete operations against `@Resource`.  
**Fix:** Update the condition to use `@Resource` for the delete clause:

```powershell
# Write the updated assignment to a temp file, then apply
az role assignment update --role-assignment "$env:TEMP\role-assignment-update.json"
```

The JSON file must include the full assignment object with the corrected condition.
See the `@Resource` vs `@Request` explanation in the session history.

---

## Useful links

| Resource | URL |
|----------|-----|
| HCP TF workspace runs | `https://app.terraform.io/app/<your-org>/workspaces/<your-workspace>/runs` |
| GitHub Actions | `https://github.com/<owner>/<repo>/actions` |
| Azure portal — resource group | https://portal.azure.com → Resource groups → rg-<project> |
| MCP protocol spec | https://modelcontextprotocol.io/specification |
| azurerm provider docs | https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs |
