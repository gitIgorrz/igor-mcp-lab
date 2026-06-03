# MCP Server Deployment Rules

## Testing Requirements

- After EVERY code change, run `npm test` (or your equivalent) before proceeding
- Never mark a step complete unless tests pass — fix failures first
- Validate connectivity to Azure/GitHub at each integration point
- Run `terraform validate && terraform plan` before any apply

## Deployment Checkpoints

After each phase below, STOP and confirm success before continuing:

1. Auth/OIDC token exchange verified
2. Terraform plan output reviewed and approved
3. Resource group exists and tags are correct
4. MCP server process starts without errors
5. Tool registration confirmed (list tools endpoint responds)

## Manual Action Gates

- Prompt me for approval before any `terraform apply`
- Prompt me before any `az role assignment create`
- Never proceed past a failed checkpoint without explicit instruction

## When Compacting

Always preserve: modified files list, last test command run, current checkpoint status
