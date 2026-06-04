# Getting Started — From Absolute Zero

This guide takes you from a bare machine to a state where you can clone this
repository, make changes, push a branch, open a pull request, and have it
deploy to Azure. Follow the steps in order.

---

## Table of contents

1. [Create accounts](#1-create-accounts)
2. [Install tools](#2-install-tools)
3. [Configure Git identity](#3-configure-git-identity)
4. [Set up GPG commit signing](#4-set-up-gpg-commit-signing)
5. [Authenticate Git and the GitHub CLI](#5-authenticate-git-and-the-github-cli)
6. [Set up VS Code](#6-set-up-vs-code)
7. [Branching strategy](#7-branching-strategy)
8. [Clone the repo and make your first push](#8-clone-the-repo-and-make-your-first-push)

---

## 1. Create accounts

You need three accounts before installing anything.

### GitHub

1. Go to [github.com](https://github.com) → **Sign up**
2. Choose a username — this becomes your GitHub identity (e.g. `gitIgorrz`)
3. Verify your email address

### HCP Terraform (HashiCorp Cloud Platform)

HCP Terraform stores your infrastructure state and runs `terraform plan`/`apply`.

1. Go to [app.terraform.io](https://app.terraform.io) → **Create account**
2. Create an **organisation** — this is the top-level namespace for your workspaces (e.g. `myorg`)
3. Inside the org, create a **project** (e.g. `my-project`) — projects group related workspaces

### Azure (for deployment)

1. Go to [portal.azure.com](https://portal.azure.com) → **Start free** (requires a Microsoft account)
2. Note your **Subscription ID** — you'll need it when setting up Terraform

---

## 2. Install tools

### Windows (using winget)

Open **PowerShell as Administrator** and run:

```powershell
# Git — version control
winget install Git.Git

# GitHub CLI — manage PRs, releases, secrets from the terminal
winget install GitHub.cli

# Node.js LTS — JavaScript runtime (for the MCP server and tests)
winget install OpenJS.NodeJS.LTS

# Terraform CLI — infrastructure as code
winget install Hashicorp.Terraform

# Azure CLI — manage Azure resources
winget install Microsoft.AzureCLI

# GnuPG — for GPG commit signing (see step 4)
winget install GnuPG.GnuPG

# VS Code — editor
winget install Microsoft.VisualStudioCode
```

Close and reopen PowerShell after installing so the new commands are on your PATH.

### macOS (using Homebrew)

```bash
# Install Homebrew first if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install git gh node terraform azure-cli gnupg
brew install --cask visual-studio-code
```

### Verify everything installed

```bash
git --version
gh --version
node --version
npm --version
terraform --version
az --version
gpg --version
code --version
```

All commands should print a version number. If one fails, re-open your terminal and try again (PATH may not have refreshed).

---

## 3. Configure Git identity

Every commit you make is stamped with your name and email. This must match your GitHub account email for commits to show as "verified" on GitHub.

```bash
git config --global user.name  "Your Name"
git config --global user.email "your-github-email@example.com"

# Set VS Code as your default editor (for commit messages, merge conflicts)
git config --global core.editor "code --wait"

# Default branch name for new repositories
git config --global init.defaultBranch main
```

Verify:

```bash
git config --global --list
```

---

## 4. Set up GPG commit signing

GPG signing adds a cryptographic signature to every commit so GitHub can display a **Verified** badge. Anyone can then confirm the commit genuinely came from you.

### Generate a key

```bash
gpg --full-generate-key
```

When prompted:
- Key type: **RSA and RSA** (default)
- Key size: **4096**
- Expiry: **0** (does not expire) — or set a date if you prefer
- Real name: your name (must match `git config user.name`)
- Email: your GitHub email (must match `git config user.email`)
- Passphrase: choose a strong passphrase and store it in a password manager

### Find your key ID

```bash
gpg --list-secret-keys --keyid-format LONG
```

Output looks like:

```
sec   rsa4096/ABCDEF1234567890 2026-01-01 [SC]
      AABBCCDD11223344AABBCCDD11223344AABBCCDD
uid   [ultimate] Your Name <your@email.com>
```

The key ID is the part after `rsa4096/` — `ABCDEF1234567890` in the example above.

### Export the public key and add it to GitHub

```bash
gpg --armor --export ABCDEF1234567890
```

Copy the entire output (including `-----BEGIN PGP PUBLIC KEY BLOCK-----` and `-----END PGP PUBLIC KEY BLOCK-----`).

GitHub → **Settings** → **SSH and GPG keys** → **New GPG key** → paste → **Add GPG key**

### Tell Git to sign all commits

```bash
git config --global user.signingkey ABCDEF1234567890
git config --global commit.gpgsign true
```

**Windows only** — tell Git which gpg binary to use:

```powershell
git config --global gpg.program "C:\Program Files (x86)\GnuPG\bin\gpg.exe"
```

### Test it

```bash
echo "test" | gpg --clearsign
```

This should prompt for your passphrase and print a signed block. If it works, your future commits will have the **Verified** badge on GitHub.

> **Tip — save your passphrase:** Use your system's keychain or a password manager. On Windows, you can use gpg-agent to cache the passphrase so you're not asked on every commit:
> ```powershell
> # In your PowerShell profile ($PROFILE) or .bashrc:
> $env:GPG_TTY = $(tty)
> ```

---

## 5. Authenticate Git and the GitHub CLI

### Git Credential Manager (GCM)

Git Credential Manager is installed automatically with **Git for Windows** and handles HTTPS authentication via a browser popup — no SSH keys or personal access tokens needed. The first time you push or pull, a browser window opens and you log in to GitHub. GCM stores the token securely in the Windows Credential Manager.

To verify GCM is set up correctly:

```powershell
git config --global credential.helper
# Should print: manager
```

If it prints something else (or nothing), configure it:

```powershell
git config --global credential.helper manager
```

### GitHub CLI

The GitHub CLI (`gh`) manages pull requests, releases, and repo secrets from the terminal. Authenticate it once:

```bash
gh auth login
```

Choose:
- **GitHub.com** (not Enterprise)
- **HTTPS**
- **Login with a web browser** — this opens github.com and asks you to paste a one-time code

Verify:

```bash
gh auth status
```

Should show your username and the scopes the token has (`repo`, `workflow`, etc.).

---

## 6. Set up VS Code

### Recommended extensions

Install these from the Extensions panel (`Ctrl+Shift+X`) or via the terminal:

```bash
code --install-extension ms-vscode.vscode-typescript-next   # TypeScript support
code --install-extension dbaeumer.vscode-eslint              # ESLint linting
code --install-extension hashicorp.terraform                 # Terraform syntax + validation
code --install-extension ms-azuretools.vscode-docker         # Dockerfile support
code --install-extension github.vscode-github-actions        # GitHub Actions workflow syntax
code --install-extension eamodio.gitlens                     # Git history, blame, PR info
code --install-extension ms-vscode.azure-account             # Azure account integration
```

### Useful VS Code settings

Open Settings (`Ctrl+,`) → click the `{}` icon (Open Settings JSON) and add:

```json
{
  "editor.formatOnSave": true,
  "git.enableCommitSigning": true,
  "git.confirmSync": false,
  "terminal.integrated.defaultProfile.windows": "PowerShell"
}
```

`git.enableCommitSigning: true` makes VS Code's built-in Git UI sign commits automatically using your GPG key.

---

## 7. Branching strategy

This project uses a **trunk-based** approach: `main` is the single long-lived branch and represents what is deployed. All changes come in through short-lived branches and pull requests.

### Branch naming

```
main  (protected — no direct pushes)
 │
 ├── feat/add-list-resources-tool     ← new features or capabilities
 ├── fix/aci-probe-timeout            ← bug fixes
 ├── chore/upgrade-node-24            ← maintenance: deps, CI config, tooling
 ├── docs/update-readme               ← documentation only, no code change
 └── refactor/extract-health-route    ← code restructure, no behaviour change
```

The branch name prefix must match the type used in the PR title (see below).

### PR title convention (Conventional Commits)

Every PR title follows the format `type: short description`:

| Type | When to use | Example |
|------|-------------|---------|
| `feat:` | New tool, endpoint, or Azure resource | `feat: add list-subscriptions tool` |
| `fix:` | Broken behaviour is corrected | `fix: suppress az container restart false negative` |
| `chore:` | Tooling, CI, dependencies — no behaviour change | `chore: upgrade azurerm provider to 4.80` |
| `docs:` | README, comments, changelog only | `docs: add getting-started guide` |
| `refactor:` | Code restructured, same behaviour | `refactor: extract health route to separate module` |

The title becomes the squash-merge commit message on `main`, so it needs to make sense on its own in `git log`.

### What happens when you merge

```
main ◄── squash merge ◄── feat/my-new-tool
  │
  ├──► GitHub Actions (deploy.yml)
  │     Test → Check infra → Docker build/push → ACI restart → Smoke tests
  │
  └──► HCP Terraform (VCS trigger)
        Plan on a remote agent → you approve in HCP TF UI → apply
```

Both pipelines run in parallel automatically. You don't need to trigger anything manually beyond approving the Terraform apply in the HCP TF UI.

### Rules enforced by branch protection

| Rule | Why |
|------|-----|
| Direct pushes to `main` blocked | All changes must be reviewed |
| 1 approving review required | A second pair of eyes before deploy |
| `Build & Test` check must pass | Code must compile and tests must pass |
| HCP TF speculative plan must pass | Infrastructure changes must be valid |
| Stale reviews dismissed | Re-approval needed after new commits |
| Conversation resolution required | All review comments must be addressed |

> **As the repo owner** you can bypass these rules using "Merge without waiting for requirements" when necessary (e.g. a hotfix). Use this sparingly.

---

## 8. Clone the repo and make your first push

### Clone

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
```

Or via the GitHub CLI:

```bash
gh repo clone <owner>/<repo>
cd <repo>
```

### Install dependencies

```bash
npm install
```

### Make a change, branch, and open a PR

The commands below apply the branching strategy from step 7.

```bash
# 1. Always start from an up-to-date main
git checkout main
git pull origin main

# 2. Create your branch
git checkout -b feat/my-first-change

# 3. Make a change (e.g. edit a tool description in src/tools/echo.ts)

# 4. Stage and commit
git add src/tools/echo.ts
git commit -m "feat: update echo tool description"
# You will be prompted for your GPG passphrase on the first commit

# 5. Push the branch
git push origin feat/my-first-change

# 6. Open a pull request
gh pr create --title "feat: update echo tool description" --body "Short description of the change."
```

The CI pipeline (`pr-checks.yml`) will run automatically. Once it passes and you've reviewed it, merge the PR and `deploy.yml` will trigger.

---

## Troubleshooting

### `gpg: signing failed: No secret key`

Your Git signing key doesn't match any key in your GPG keyring.  
Run `gpg --list-secret-keys --keyid-format LONG` and confirm the key ID matches `git config user.signingkey`.

### `error: gpg failed to sign the data`

On Windows, Git can't find the `gpg` binary.  
Run: `git config --global gpg.program "C:\Program Files (x86)\GnuPG\bin\gpg.exe"`

### `gh: Not logged in`

Run `gh auth login` and follow the prompts.

### `fatal: Authentication failed` when pushing

GCM should handle this automatically via a browser popup, but if it fails:

```powershell
# Clear any cached credentials and re-authenticate
git credential reject
# Then push again — a browser window will open to re-login
```

Alternatively, re-run `gh auth login` and choose to use HTTPS.

### `node: command not found` after installing Node.js

Close and reopen your terminal — PATH needs to refresh. If still missing, restart your computer.

