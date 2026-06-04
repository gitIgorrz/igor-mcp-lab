# igor-mcp-lab

A production-grade **Model Context Protocol (MCP)** server deployed on Azure, built as a reference implementation for enterprise CI/CD patterns.

---

## What is MCP?

[Model Context Protocol](https://modelcontextprotocol.io) is an open standard that lets AI assistants (such as Claude) call external **tools** — named functions with typed inputs and outputs. An MCP server exposes those tools over a network; clients discover and invoke them using JSON-RPC 2.0.

This server exposes three tools over HTTP:

| Tool | Input | What it does |
|------|-------|-------------|
| `echo` | `{ text: string }` | Returns the input unchanged — used for smoke testing |
| `add` | `{ a: number, b: number }` | Returns the sum as a string |
| `server-info` | _(none)_ | Returns deployment metadata (version, timestamp, environment) |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        GitHub                                │
│                                                              │
│  Pull Request          Push to main                          │
│       │                      │                               │
│  ┌────▼──────────┐    ┌──────▼──────────────────────────┐  │
│  │ pr-checks.yml │    │         deploy.yml               │  │
│  │               │    │  Test → Build → Push → Restart  │  │
│  │  • Build      │    │  → Health poll → Smoke tests    │  │
│  │  • Lint       │    └──────────┬──────────────────────┘  │
│  │  • Test       │               │ GitHub OIDC              │
│  └───────────────┘               │ (no client secret)       │
│        │ VCS speculative plan    │                           │
└────────┼────────────────────────┼───────────────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌──────────────────────┐
│  HCP Terraform  │    │     Azure ACR        │
│  Remote exec    │    │  <project>:latest    │
│                 │    └──────────┬───────────┘
│  PR  → plan     │               │ image pull
│  main → apply   │               │
│  (your approval)│               │
└────────┬────────┘               │
         │ manages                │
         ▼                        ▼
┌────────────────────────────────────────────────────┐
│                    Azure                           │
│                                                    │
│  Resource Group: rg-<project> (<region>)           │
│                                                    │
│  ┌──────────────┐  AcrPull  ┌───────────────────┐ │
│  │   Managed    │──────────►│  Container        │ │
│  │   Identity   │           │  Instance (ACI)   │ │
│  └──────────────┘           │                   │ │
│                             │  MCP Server :3000  │ │
│  ┌──────────────┐           │  GET  /health      │ │
│  │     ACR      │◄──────────│  POST /mcp         │ │
│  └──────────────┘  image    └───────────────────┘ │
└────────────────────────────────────────────────────┘
```

### Key design decisions

| Decision | Rationale |
|----------|-----------|
| GitHub OIDC → Azure for Docker push | No client secret needed in GitHub Actions |
| Client secret in HCP TF workspace | Required for Terraform remote execution; stored encrypted, never in code |
| VCS-driven Terraform | HCP TF watches the repo; plan on PR, apply on merge with manual approval |
| ACI restart in GitHub Actions | Docker deployment separated from infrastructure management |
| Stateless MCP transport | One server instance per HTTP request — simple, no session management |

---

## Repository structure

```
igor-mcp-lab/
├── src/
│   ├── index.ts              # HTTP server + MCP transport setup
│   ├── tools/
│   │   ├── index.ts          # Registers all tools on the server
│   │   ├── echo.ts           # echo tool
│   │   ├── add-numbers.ts    # add tool
│   │   └── get-info.ts       # server-info tool
│   └── __tests__/
│       └── tools.test.ts     # Unit tests (InMemoryTransport, no HTTP)
├── infra/
│   ├── main.tf               # Azure resources (ACR, ACI, identity, roles)
│   ├── variables.tf          # Input variables with defaults
│   ├── outputs.tf            # Outputs (ACR name, ACI endpoints)
│   └── backend.tf            # HCP Terraform Cloud backend
├── .github/
│   ├── workflows/
│   │   ├── pr-checks.yml     # CI: build + test on every PR
│   │   └── deploy.yml        # CD: full deploy pipeline on push to main
│   ├── pull_request_template.md
│   └── actionlint.yaml       # Declares known secrets to suppress linter warnings
├── Dockerfile                # Multi-stage: builder (tsc) → runtime (node)
├── package.json
├── tsconfig.json
├── CHANGELOG.md
└── CLAUDE.md                 # Rules and checkpoints for AI-assisted work
```

> **`dist/`** — TypeScript compiles here at build time. Gitignored; never committed.  
> **`infra/.terraform/`** — Downloaded providers. Gitignored; never committed.

---

## Prerequisites

> **Starting from scratch?** See [docs/getting-started.md](./docs/getting-started.md) for a complete walkthrough: installing tools, creating accounts, configuring Git, setting up GPG commit signing, and making your first push.

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | >= 20 | Run the server and tests locally |
| npm | >= 9 | Package management |
| Terraform | >= 1.9 | Provision Azure infrastructure locally |
| Azure CLI (`az`) | any | Authenticate to Azure |
| GitHub CLI (`gh`) | any | Manage PRs and releases |
| Git Credential Manager | bundled with Git for Windows | HTTPS authentication to GitHub (no SSH keys needed) |

---

## Local development

```bash
# 1. Install dependencies
npm install

# 2. Build TypeScript
npm run build

# 3. Run tests
npm run test:built

# 4. Start the server with live reload
npm run dev
```

The server starts on `http://localhost:3000`.

**Call a tool locally:**

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hello"}}}'
```

**List available tools:**

```bash
curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

---

## Deployment

### Make it your own

If you are forking or adapting this project, change these three files before deploying:

**1. `infra/variables.tf` — project name and region**

```hcl
variable "project" {
  default = "igormcplab"   # ← change to your project name (alphanumeric, no hyphens)
}

variable "location" {
  default = "uksouth"      # ← change to your preferred Azure region
}
```

This single `project` value drives all Azure resource names: the resource group (`rg-<project>`), container registry, container instance, managed identity, and DNS label.

**2. `infra/backend.tf` — HCP Terraform workspace**

```hcl
cloud {
  organization = "gitIgorrz"     # ← your HCP TF organisation name
  workspaces {
    name = "igor-mcp-lab"        # ← your workspace name
  }
}
```

**3. `.github/workflows/deploy.yml` — workflow resource names**

```yaml
env:
  RESOURCE_GROUP: rg-igormcplab    # ← rg-<your-project>
  ACI_NAME: aci-igormcplab         # ← aci-<your-project>
  IMAGE_REPO: igormcplab           # ← <your-project>
  TF_WORKSPACE_URL: https://app.terraform.io/app/gitIgorrz/workspaces/igor-mcp-lab
  #                                               ^^^^^^^^^^               ^^^^^^^^^^^^
  #                                               your org                 your workspace
```

After these three changes, complete the one-time manual setup below to provision the Azure identity and HCP TF workspace.

---

### One-time manual setup

This section documents every manual step required to stand up the full stack from scratch.

#### 1. Azure — App Registration and Service Principal

```bash
# Create the app registration
az ad app create --display-name "<your-app-name>"
# Note the appId (client ID) and id (object ID) from the output

# Create the service principal
az ad sp create --id <appId>
# Note the id (SP object ID) from the output

# Grant Contributor on the subscription (for resource creation)
az role assignment create \
  --assignee-object-id <SP-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope /subscriptions/<subscription-id>

# Grant constrained User Access Administrator
# (allows assigning AcrPull only — the condition restricts write and delete
#  to the AcrPull role definition ID 7f951dda-...)
az role assignment create \
  --assignee-object-id <SP-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id> \
  --condition "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d}))" \
  --condition-version "2.0"
```

#### 2. Azure — Federated credentials (GitHub Actions OIDC)

GitHub Actions authenticates to Azure without a client secret by exchanging a GitHub-issued JWT for an Azure access token. The federated credentials tell Azure which GitHub subjects to trust.

```bash
# For push to main (Docker image push in deploy.yml)
az ad app federated-credential create --id <app-object-id> --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# For pull requests (if PRs need Azure access)
az ad app federated-credential create --id <app-object-id> --parameters '{
  "name": "github-actions-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

#### 3. Azure — Client secret (for HCP Terraform remote execution)

HCP Terraform remote execution cannot use GitHub Actions OIDC tokens (they are bound to the GitHub Actions runner, not the HCP TF runner). A service principal client secret is used instead.

Azure Portal → App registrations → `<your-app-name>` → **Certificates & secrets** → **New client secret** → copy the **Value** (shown once only).

> See [Automation opportunities](#automation-opportunities) for how this could be replaced with OIDC in future.

#### 4. HCP Terraform — Workspace

1. Log in to [app.terraform.io](https://app.terraform.io)
2. Create workspace: org `<your-org>` → project `<your-project>` → **New workspace** → **VCS-driven**
3. Connect to the GitHub repo; set Terraform working directory to `infra`
4. Set execution mode: **Remote**
5. Disable auto-apply (so you can review plans before they apply)
6. Add workspace variables:

| Key | Category | Value | Sensitive |
|-----|----------|-------|-----------|
| `subscription_id` | Terraform | `<azure-subscription-id>` | No |
| `location` | Terraform | `uksouth` *(or any Azure region)* | No |
| `create_aci` | Terraform | `true` | No |
| `image_tag` | Terraform | `latest` | No |
| `ARM_CLIENT_ID` | Environment | `<app-registration-client-id>` | No |
| `ARM_TENANT_ID` | Environment | `<azure-tenant-id>` | No |
| `ARM_SUBSCRIPTION_ID` | Environment | `<azure-subscription-id>` | No |
| `ARM_CLIENT_SECRET` | Environment | `<client-secret-value>` | **Yes** |

> **Choosing a region:** `location` defaults to `uksouth` (London). To use a different region, set the `location` workspace variable to any valid Azure region name (e.g. `ukwest`, `westeurope`, `eastus`). Run `az account list-locations -o table` to see all options. The ACI endpoint FQDN changes with the region — the deploy pipeline reads it dynamically from Azure so no workflow change is needed.

#### 5. GitHub — Repository secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | App Registration client ID |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `TF_API_TOKEN` | HCP Terraform user API token |

#### 6. GitHub — Branch protection

Settings → Branches → Add branch protection rule for `main`:

- Required status checks: `Build & Test` and `Terraform Cloud/<org>/<repo-id>`
- Required approving review: 1
- Dismiss stale reviews: on
- Require conversation resolution: on
- Allow force pushes: off

#### 7. GitHub — Production environment

Settings → Environments → New environment → name: `production` → Required reviewers: add yourself.

---

### Automation opportunities

Several of the manual steps above could be automated. This section documents what we explored and where the limits are.

#### HCP Terraform workspace via Terraform

The [HCP Terraform provider](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs) can create and configure workspaces as code:

```hcl
resource "tfe_workspace" "mcp_lab" {
  name         = "<your-workspace-name>"
  organization = "<your-org>"
  project_id   = data.tfe_project.your_project.id
  execution_mode       = "remote"
  auto_apply           = false
  working_directory    = "infra"
  vcs_repo {
    identifier     = "<github-owner>/<repo-name>"
    branch         = "main"
    oauth_token_id = var.github_oauth_token_id
  }
}

resource "tfe_variable" "arm_client_secret" {
  workspace_id = tfe_workspace.mcp_lab.id
  key          = "ARM_CLIENT_SECRET"
  value        = var.arm_client_secret
  category     = "env"
  sensitive    = true
}
```

This would require a separate "bootstrap" Terraform workspace (or a local run) to manage the HCP TF workspace itself.

#### Organizational Variable Sets for OIDC (DPC)

HCP Terraform supports **Dynamic Provider Credentials (DPC)** via organizational Variable Sets. When properly configured, HCP TF generates a short-lived OIDC token per run and injects `ARM_OIDC_TOKEN`, `ARM_CLIENT_ID` etc. automatically — no client secret needed.

**What was attempted in this project:**

We spent significant time attempting DPC. The documented approach requires:

1. In HCP TF org Settings → Variable Sets → create a set with Azure DPC enabled
2. Apply the variable set to the workspace
3. In the Terraform provider: `use_oidc = true` (no `client_id` or `client_secret`)
4. Azure federated credentials trusting `https://app.terraform.io` with subject:
   `organization:<org>:project:<project>:workspace:<workspace>:run_phase:plan`

**What happened:**

Despite following the documented configuration exactly, `ARM_CLIENT_ID` was never injected by HCP TF into the remote execution environment — every plan failed with "missing required value(s): Azure client ID". This persisted across multiple approaches:
- Workspace env vars with `TFC_AZURE_*` prefix
- Organisational Variable Set with native DPC UI
- Workload identity token (`tfc_workload_identity_token_azurerm`) Terraform variable
- Speculative plans and real plans

We ultimately switched to a client secret stored as a sensitive workspace variable. This is the same approach used in other workspaces on this account.

**If you want to retry DPC:** Open a support ticket with HashiCorp including your workspace ID (found at Settings → General in the workspace) and the reproducible error. The configuration appears correct per the documentation; the failure is likely a workspace-level platform issue.

---

### Deploying a change

1. Create a branch: `feat/your-change`
2. Open a PR — `pr-checks.yml` runs build + test; HCP TF shows a speculative plan
3. Approve and merge the PR
4. `deploy.yml` runs: tests → Docker build + push → ACI restart → smoke tests
5. HCP TF triggers a plan; review it in the HCP TF UI → **Confirm & Apply**

### Tearing down

**HCP TF workspace → Settings → Destruction and Deletion → Queue destroy plan**

Review the plan (all resources listed), then confirm. Never delete Azure resources manually — it creates drift in Terraform state.

### Redeploying from scratch

1. Set `create_aci = false` in HCP TF workspace Terraform variables (temporarily)
2. Push a commit to `main` — GitHub Actions pushes the Docker image; HCP TF creates the ACR
3. Set `create_aci = true`, trigger a new HCP TF run — ACI is created with the image in place

---

## Contributing

All changes go through pull requests — direct pushes to `main` are blocked.

### Branching strategy

```
main  (protected)
 │
 ├── feat/add-list-resources-tool   ← new features
 ├── fix/aci-probe-timeout          ← bug fixes
 ├── chore/upgrade-node-22          ← maintenance (deps, CI, config)
 └── docs/update-readme             ← documentation only
```

**Rules:**
- `main` is the single long-lived branch — it always represents the deployed state
- Every change comes in via a PR from a short-lived branch
- Branch names use a `type/short-description` format matching the PR title type
- Branches are deleted after merging (the GitHub UI offers this automatically)

### Commit and PR title convention

Titles follow [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | When to use |
|--------|-------------|
| `feat:` | A new tool, endpoint, or infrastructure resource |
| `fix:` | A bug fix — broken behaviour is corrected |
| `chore:` | Tooling, CI, dependencies, config — no behaviour change |
| `docs:` | README, comments, changelog only |
| `refactor:` | Code restructured without behaviour change |

Examples used in this project:
```
feat: remote exec, manual apply gate, DEPLOYED_AT, Node.js 24 actions
fix: remove use_oidc; switch to client secret auth for remote execution
fix: suppress false-negative exit code from az container restart
chore: repo cleanup, comments, docs, and CHANGELOG for v0.1
```

### Day-to-day Git workflow

```bash
# 1. Always start from an up-to-date main
git checkout main
git pull origin main

# 2. Create a branch
git checkout -b fix/your-change-description

# 3. Make changes, then commit with a conventional title
git add path/to/changed/file.ts
git commit -m "fix: short description of what was fixed and why"

# 4. Push and open a PR
git push origin fix/your-change-description
gh pr create --title "fix: short description" --body-file /tmp/pr-body.md

# 5. After the PR is approved and merged, clean up locally
git checkout main
git pull origin main
git branch -d fix/your-change-description
```

### When to bypass branch protection

The repo owner has `enforce_admins: false`, which means you can merge without
a PR review when needed (e.g. hotfixes, rebasing a broken PR). Use the
**"Merge without waiting for requirements"** button in the GitHub UI, or:

```bash
gh pr merge <number> --squash --admin --delete-branch
```

Use this sparingly — it skips the CI checks.

### Workflow diagram

```
feat/your-branch ──► PR ──► pr-checks.yml (build + test + HCP TF plan)
                               │
                               ▼ you approve and merge
main ──────────────────────────► deploy.yml (test + docker + smoke tests)
                               │
                               ▼ HCP TF VCS trigger (automatic)
                            HCP TF plan → you review → Confirm & Apply
```

---

## Debugging

See [docs/debugging.md](./docs/debugging.md) for:
- Common Azure CLI and PowerShell commands to check resource status
- GitHub CLI commands for inspecting Actions runs
- HCP Terraform run log interpretation
- Container logs and probe failure diagnosis
- Common errors with fixes (including the JSON-file technique for complex `az` commands)

---

## Versioning

[Semantic Versioning](https://semver.org/):

- **Patch** `0.x.Y` — bug fixes, docs, workflow tweaks
- **Minor** `0.X.0` — new tools, infrastructure changes, non-breaking
- **Major** `X.0.0` — breaking changes to the MCP interface or deployment model

See [CHANGELOG.md](./CHANGELOG.md) for the full history.
