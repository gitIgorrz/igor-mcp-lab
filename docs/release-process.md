# Release Process

This document covers how to cut a release, what tagging does, and how to
roll back if something goes wrong.

---

## Table of contents

1. [What is a release?](#what-is-a-release)
2. [Versioning scheme](#versioning-scheme)
3. [Before you release](#before-you-release)
4. [Creating a release (automated)](#creating-a-release-automated)
5. [What the release workflow does](#what-the-release-workflow-does)
6. [Rolling back](#rolling-back)
7. [Hotfix releases](#hotfix-releases)

---

## What is a release?

In this project, a **release** is three things bundled together:

1. **A git tag** — a named, immutable pointer to a specific commit.
   Once pushed, a tag cannot be moved without deleting and recreating it.

2. **A GitHub Release** — a GitHub UI object attached to the tag, containing
   release notes and links to the source code at that point in time.

3. **A point of known good state** — a commit that has passed all CI checks,
   been deployed, and is considered stable enough to reference by version.

Tags live in the git history forever, independent of branches. You can always
check out the exact code at any tagged version:

```bash
git checkout v0.1.0    # see the codebase as it was at v0.1.0
git checkout main      # return to the latest code
```

---

## Versioning scheme

This project uses [Semantic Versioning](https://semver.org/) — `vMAJOR.MINOR.PATCH`:

| Version part | Increment when… | Example |
|---|---|---|
| `PATCH` (Z) | Bug fixes, docs, workflow tweaks — nothing the user notices | `v0.1.0` → `v0.1.1` |
| `MINOR` (Y) | New tools, non-breaking infrastructure changes | `v0.1.0` → `v0.2.0` |
| `MAJOR` (X) | Breaking changes to the MCP interface or deployment model | `v0.x.y` → `v1.0.0` |

While `MAJOR` is `0` (e.g. `v0.x.y`), the API is considered unstable —
breaking changes may happen on `MINOR` bumps.

---

## Before you release

1. **Ensure all intended PRs are merged to `main`**
2. **Update `CHANGELOG.md`** — move entries from `[Unreleased]` to a new
   `[X.Y.Z] — YYYY-MM-DD` section
3. **Commit and push the changelog update** via a PR:
   ```
   docs: update CHANGELOG for vX.Y.Z
   ```
4. Merge that PR — `main` is now release-ready

---

## Creating a release (automated)

You do not need to run any `git tag` commands locally. Use the release workflow:

1. Go to **GitHub → Actions → Release** (left sidebar under Workflows)
2. Click **Run workflow** (top right)
3. Fill in the form:
   - **Version**: `v0.1.0` *(must match the format `vX.Y.Z`)*
   - **Pre-release**: check this for release candidates or unstable builds
4. Click **Run workflow**

The workflow validates the version, creates an annotated tag on the current
HEAD of `main`, and publishes a GitHub Release with the notes from
`CHANGELOG.md`.

The release appears at `https://github.com/<owner>/<repo>/releases`.

---

## What the release workflow does

```
workflow_dispatch (you enter vX.Y.Z)
        │
        ▼
1. Validate version format (must be vX.Y.Z)
2. Confirm tag does not already exist
3. git tag -a vX.Y.Z -m "Release vX.Y.Z"
4. git push origin vX.Y.Z
5. gh release create vX.Y.Z --notes-file CHANGELOG.md
        │
        ▼
GitHub Release published — visible on the Releases page
Tag permanently in git history — anyone can checkout or diff against it
```

---

## Rolling back

"Rolling back" means different things depending on what broke.

### Rolling back a code deployment (ACI)

The previous Docker image is still in ACR, tagged with its git SHA. To
redeploy the previous version:

**Option A — Revert the commit (recommended)**

```bash
# Find the commit to revert
git log --oneline -10

# Create a revert commit (safe — preserves history)
git revert <bad-commit-sha>

# Push via a PR
git push origin fix/revert-bad-change
gh pr create --title "fix: revert <bad-change>" --body "Reverts <sha>"
```

Merging the PR triggers `deploy.yml`, which rebuilds and pushes the reverted
image, restarts ACI, and runs smoke tests — the same pipeline as any other
change.

**Option B — Roll forward with a fix**

Usually faster than reverting. If you know what broke, fix it directly and
merge via a PR. This is preferred over reverting for small fixes.

**Option C — Redeploy a specific previous image (emergency)**

If you need to restore a known-good image without a code change (e.g. while
debugging), update the `image_tag` in the HCP TF workspace Terraform variable
to the git SHA of the last known good commit, then trigger a new HCP TF plan
and apply:

```
HCP TF workspace → Variables → image_tag → change to <last-good-sha>
HCP TF workspace → New run → Plan and Apply
```

ACI will restart with the old image. Remember to revert this variable change
after the incident.

### Rolling back an infrastructure change

If a Terraform apply introduced a bad infrastructure change:

**Option A — Revert the Terraform code (recommended)**

Same as code rollback — revert the commit that changed `infra/`, merge via PR,
the HCP TF VCS trigger runs the plan automatically.

**Option B — Manually trigger a destroy and redeploy**

For catastrophic failures where the infrastructure is in an inconsistent state:

```
1. HCP TF → Settings → Destruction and Deletion → Queue destroy plan
2. Confirm the destroy
3. Follow the "Redeploying from scratch" steps in README.md
```

### What NOT to do when rolling back

| Don't do this | Why |
|---|---|
| `git push --force` to main | Rewrites history, breaks everyone's local copy, bypasses branch protection |
| Delete and recreate a tag | Confuses anyone who has already pulled the tag |
| Delete Azure resources manually via Portal or CLI | Creates drift in Terraform state — next `terraform plan` will fail |
| Edit a released CHANGELOG entry | Use a new entry instead; keep the history accurate |

### Rolling back to a tagged version

If you want to inspect or test an older release:

```bash
# View the code at a specific tag (read-only)
git checkout v0.1.0

# Return to main
git checkout main
```

To **re-deploy** a tagged version, create a branch from it and open a PR:

```bash
git checkout -b hotfix/redeploy-v0.1.0 v0.1.0
# Make any necessary changes
git push origin hotfix/redeploy-v0.1.0
gh pr create --title "fix: redeploy v0.1.0"
```

---

## Hotfix releases

A hotfix is an urgent patch that skips the normal branch-from-main flow.
You branch from the release tag itself:

```bash
# Branch from the tagged release, not main
git checkout -b hotfix/v0.1.1 v0.1.0

# Make the fix, commit, push
git commit -m "fix: critical bug description"
git push origin hotfix/v0.1.1

# Open a PR targeting main
gh pr create --title "fix: critical bug description" --base main
```

After merging, update `CHANGELOG.md` with the `[0.1.1]` entry, merge that,
then use the **Release** workflow to tag `v0.1.1`.
