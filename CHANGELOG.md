# Changelog

All notable changes are documented here.  
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · Versioning: [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

---

## [0.1.0] — 2026-06-04

Initial working deployment of the MCP server lab.

### Added

**MCP Server**
- Node.js / TypeScript MCP server with three tools: `echo`, `add`, `server-info`
- Streamable HTTP transport (`POST /mcp`, `GET /health`) on port 3000
- Multi-stage Dockerfile: builder stage compiles TypeScript; runtime stage is lean, non-root, production-only
- Unit tests using Node.js built-in test runner and MCP `InMemoryTransport` (no HTTP required)

**Azure Infrastructure (Terraform)**
- Resource Group, Azure Container Registry (ACR), Azure Container Instance (ACI)
- User-Assigned Managed Identity with AcrPull role (constrained ABAC condition: can only delegate AcrPull, not any other role)
- Constrained User Access Administrator role assignment (write and delete limited to AcrPull role definition only)
- Liveness and readiness HTTP probes on `/health`
- Default region: `uksouth` (London) — configurable via `location` Terraform variable

**CI/CD Pipelines**
- `pr-checks.yml`: build, lint, test on every PR; HCP Terraform speculative plan as a GitHub status check
- `deploy.yml`: test → `check-infra` pre-flight → Docker build + push to ACR → ACI restart → health poll → smoke tests
- `release.yml`: `workflow_dispatch`-triggered workflow that validates version format, creates annotated git tag, and publishes a GitHub Release from `CHANGELOG.md`
- Pipeline skips Docker push and ACI restart gracefully when infrastructure is not deployed (e.g. after `terraform destroy`)
- ACI FQDN read dynamically from Azure at runtime — health check URL is correct regardless of region

**HCP Terraform**
- Remote execution mode with client secret auth (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, etc. as workspace env vars)
- VCS-driven: HCP TF watches the GitHub repo; plan on PR, apply on merge to main with manual approval in HCP TF UI
- State stored in HCP TF workspace (`gitIgorrz / igor-lab / igor-mcp-lab`)

**Security**
- GitHub Actions → Azure: OIDC federated credentials (no client secret in GitHub Actions)
- HCP Terraform → Azure: service principal client secret (stored encrypted in HCP TF workspace only)
- Azure App Registration with federated credentials for GitHub Actions (main branch push and PRs)
- Federated credentials also registered for HCP TF plan and apply phases (for potential future DPC migration)

**GitHub Repository**
- Branch protection on `main`: required PR review, `Build & Test` and HCP TF speculative plan as required status checks, conversation resolution required
- Conventional commit PR template (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`)
- `.gitattributes` for consistent LF line endings across platforms

**Documentation**
- `README.md`: architecture diagram, "Make it your own" setup guide, manual setup steps, automation opportunities, DPC history, branching strategy, Git workflow examples
- `docs/getting-started.md`: full from-scratch setup (accounts, tools, Git config, GPG commit signing, Git Credential Manager, VS Code extensions, branching strategy, first push)
- `docs/debugging.md`: Git commands reference, JSON-file technique for PowerShell `az` calls, Azure CLI commands, GitHub CLI run inspection, HCP TF log interpretation, container probe diagnosis, common errors and fixes
- `docs/release-process.md`: release workflow, versioning scheme, rollback strategies, hotfix process
- `CHANGELOG.md`: this file

### Fixed
- `az container restart` false-negative exit code (`|| true` appended — CLI incorrectly treats HTTP 200 OK as an error)
- `use_oidc = true` removed from azurerm provider when using client secret auth (conflicting auth signals)
- Speculative plan failures caused by HCP TF Dynamic Provider Credentials (DPC) not injecting `ARM_CLIENT_ID` into remote execution environment — switched to explicit workspace env vars with client secret

### Known limitations
- HCP TF Dynamic Provider Credentials (OIDC, no client secret) for remote execution could not be made to work for this workspace despite following all documented approaches. The workspace uses a client secret as a workaround. See `README.md → Automation opportunities` for full details and how to file a support ticket if you want to retry DPC.
