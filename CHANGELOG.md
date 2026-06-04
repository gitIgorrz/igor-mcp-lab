# Changelog

All notable changes are documented here.  
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) · Versioning: [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

## [0.1.0] — 2026-06-04

Initial working deployment of the MCP server lab.

### Added
- Node.js / TypeScript MCP server with three tools: `echo`, `add`, `server-info`
- Streamable HTTP transport on port 3000 (`POST /mcp`, `GET /health`)
- Multi-stage Dockerfile (builder → runtime, non-root user)
- Azure infrastructure via Terraform: Resource Group, ACR, ACI, User-Assigned Managed Identity, AcrPull role assignment
- HCP Terraform Cloud workspace (`gitIgorrz / igor-lab / igor-mcp-lab`) with remote execution and client secret auth
- VCS-driven CI/CD:
  - `pr-checks.yml` — build, lint, test on every PR; HCP TF speculative plan as status check
  - `deploy.yml` — test → Docker build & push → ACI restart → smoke tests on merge to main
- GitHub branch protection: required PR review, required status checks (`Build & Test`, HCP TF plan)
- Conventional commit PR template
- Unit tests using Node.js built-in test runner and MCP `InMemoryTransport`
- Azure OIDC federated credentials for GitHub Actions (no client secret for Docker push)
- Constrained `User Access Administrator` role for the service principal (AcrPull-only delegation)
