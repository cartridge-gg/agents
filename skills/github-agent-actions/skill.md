---
name: github-agent-actions
description: Create GitHub Actions workflows powered by claude-code-action. Fetches current docs to stay accurate, applies a structured checklist to avoid common pitfalls, and produces working workflows.
---

# GitHub Agent Actions Skill

Create GitHub Actions workflows that use `anthropics/claude-code-action` to automate PR reviews, issue triage, documentation updates, scheduled maintenance, and other Claude-powered tasks.

## Source of Truth

The claude-code-action repo is the authoritative source for supported inputs, events, and configuration.
When in doubt, fetch what you need before generating YAML.

- **Action inputs & structure**: `gh api repos/anthropics/claude-code-action/contents/action.yml --jq '.content' | base64 -d`
- **Supported events**: `gh api repos/anthropics/claude-code-action/contents/src/github/context.ts --jq '.content' | base64 -d`
- **Solutions & examples**: `gh api repos/anthropics/claude-code-action/contents/docs/solutions.md --jq '.content' | base64 -d`
- **Migration guide**: `gh api repos/anthropics/claude-code-action/contents/docs/migration-guide.md --jq '.content' | base64 -d`
- **GitHub Actions syntax**: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

## Process

### Phase 1: Understand the Goal

Determine what the user wants:
- **What triggers it?** PR opened, comment with @claude, schedule, manual dispatch, issue created, etc.
- **What should Claude do?** Review code, write docs, triage issues, fix code, label things, etc.
- **Does Claude need to write back?** Push commits, post comments, create issues, add labels?
- **Are fork PRs involved?** If yes, use `pull_request_target` instead of `pull_request` so the workflow has access to repo secrets.

For simple requests, proceed directly to generation.
For complex workflows, ask 1-2 clarifying questions first.

### Phase 2: Gather Current Configuration

Before generating YAML, fetch the action's `action.yml` to confirm:
1. The current version tag (use `@v1` unless the user specifies otherwise)
2. The exact input names and defaults — do not rely on memory, as inputs change between versions
3. Which inputs are deprecated (check the migration guide if unsure)

If the workflow uses an unusual trigger event, also fetch `context.ts` to confirm it's in the supported event switch statement.

### Phase 3: Pre-Flight Checklist

Verify each of these internally before writing any YAML.

#### Permissions
- Map every GitHub API operation Claude will perform to a permission scope.
- Common mappings:
  - Reading code → `contents: read`
  - Pushing commits → `contents: write`
  - Commenting on PRs → `pull-requests: write`
  - Managing issues/labels → `issues: write`
  - OIDC auth or GitHub App token exchange → `id-token: write`
- Set permissions at the **job level** for least-privilege.
- When unsure, start restrictive — a missing permission produces a clear error, an overly broad one is a silent security risk.

#### GitHub Token: Two Paths

The action needs two credentials: an **Anthropic API key** (to call Claude) and a **GitHub token** (to comment on PRs, read code, etc.).
The GitHub token has two paths — understanding which one applies is critical:

1. **Default path (OIDC + Anthropic GitHub App):** The action requests an OIDC token from GitHub, then exchanges it with Anthropic's service for a GitHub App installation token.
   This requires the repo to have **Anthropic's GitHub App installed**.
   If the App is not installed, this fails with `Invalid OIDC token`.
   This path requires `id-token: write` permission.

2. **Override path (`github_token` input):** If you pass `github_token`, the action skips OIDC entirely and uses that token directly.
   The built-in `${{ github.token }}` (aka `${{ secrets.GITHUB_TOKEN }}`) already has the permissions declared in the workflow's `permissions:` block.

**Decision rule:** If the repo has Anthropic's GitHub App installed, use the default path.
Otherwise, pass `github_token: ${{ github.token }}` to bypass OIDC:
```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    github_token: ${{ github.token }}
```

**Security tradeoff between the two paths:**
The GitHub App path adds a validation layer — Anthropic's service verifies the OIDC token and can enforce policies on which repos/workflows are allowed before issuing a scoped token.
With `github_token`, you skip that gatekeeper.

When using `github_token` with `pull_request_target` (the common fork PR pattern):
- **Safe:** The workflow file runs from the base branch, so a fork can't modify the workflow to escalate permissions. The token is scoped to only the declared permissions.
- **Risky:** If the workflow checks out the fork's code, Claude runs in that checkout. A malicious contributor could include a crafted `AGENTS.md` or `CLAUDE.md` that tries to trick Claude into misusing available tools — e.g., exfiltrating the Anthropic API key or posting spam via `gh`.

**Mitigations when using `github_token` + `pull_request_target`:**
- Restrict tools with `--allowedTools` in `claude_args` to only what the workflow needs
- Block destructive commands with `--disallowedTools` (e.g., `Bash(gh pr merge:*)`)
- Keep `--max-turns` low to limit the blast radius
- Long-term, installing Anthropic's GitHub App is the more secure option

#### Secrets & Fork PRs

- **Fork PRs cannot access repo secrets.** Workflows triggered by `pull_request` from a fork will have empty secret values — including `secrets.ANTHROPIC_API_KEY`.
  Use `pull_request_target` if you need secrets for fork PRs. This runs the workflow from the base branch with access to the base repo's secrets.
  **Security tradeoff:** The workflow has access to secrets while potentially processing untrusted code. Never checkout and execute fork code in a `pull_request_target` workflow without careful review.
- **Secret scope matters.** Secrets can be set at repo, environment, or org level.
  If a secret is scoped to an environment, the job must declare `environment: <name>` or the secret will be empty with no error.
- **Never interpolate secrets in `run:` blocks.** Use `env:` to pass them:
  ```yaml
  # WRONG — secret can leak in logs or process table
  - run: curl -H "Authorization: Bearer ${{ secrets.TOKEN }}" ...

  # RIGHT
  - run: curl -H "Authorization: Bearer $TOKEN" ...
    env:
      TOKEN: ${{ secrets.TOKEN }}
  ```
- **Never interpolate attacker-controlled context in `run:` blocks either.**
  Properties like `github.event.pull_request.title`, `github.event.issue.body`, `github.event.comment.body`, and `github.event.head_commit.message` can contain shell metacharacters that enable arbitrary command injection.
  Use `env:` — the same pattern as secrets:
  ```yaml
  # WRONG — attacker can inject shell commands via PR title
  - run: echo "${{ github.event.pull_request.title }}"

  # RIGHT
  - run: echo "$TITLE"
    env:
      TITLE: ${{ github.event.pull_request.title }}
  ```

#### Prompt Context
- In automation mode (when `prompt` is set), Claude does NOT automatically receive PR/issue context.
  You MUST include relevant context variables in the prompt:
  ```
  REPO: ${{ github.repository }}
  PR NUMBER: ${{ github.event.pull_request.number }}
  ```
- The PR branch is already checked out — state this in the prompt so Claude knows.

#### Tool Access
- Restrict tools to what the workflow actually needs using `--allowedTools` in `claude_args`.
- Broad tool access is a security risk, especially for workflows triggered by external contributors.

### Phase 4: Generate the Workflow

Generate a complete `.github/workflows/<name>.yml` file following this structure:

```yaml
name: <Descriptive Workflow Name>

on:
  <trigger>:
    types: [<activity_types>]

jobs:
  <job-id>:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    permissions:
      <scope>: <read|write>
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 1

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ github.token }}  # omit if Anthropic's GitHub App is installed
          prompt: |
            REPO: ${{ github.repository }}
            <additional context>

            <instructions>
          claude_args: |
            <flags>
```

Key structural rules:
- Always set `timeout-minutes` at the job level
- Use `fetch-depth: 1` unless full history is needed
- For PR workflows that push commits, checkout the head ref: `ref: ${{ github.event.pull_request.head.ref }}`
- For `pull_request_target`, the checkout gets the base branch by default — explicitly checkout the PR head if you need the fork's code (with caution about untrusted code)
- **Treat `workflow_run` artifacts as untrusted.** When splitting into an unprivileged `pull_request` workflow and a privileged `workflow_run` workflow, a malicious PR can poison artifacts uploaded during the first stage.
  In the privileged `workflow_run` job: validate artifact contents, unzip to `/tmp` (not the workspace), and never execute artifact contents as code.

### Phase 5: Review

After generating, review against these principles:

1. **Every action input used must exist in the current `action.yml`.** If you didn't fetch it, fetch it now and verify.
2. **Every GitHub API call Claude will make must have a corresponding permission.**
3. **Branch names must be unique** — use `${{ github.run_id }}` or timestamps, never date-only formats.
4. **Git push must specify remote explicitly** — `git push origin HEAD`, never bare `git push`.
5. **Secrets must not appear in shell expressions** — pass them via `env:` blocks.
6. **The workflow must be valid YAML** — watch for unescaped special characters in prompts.

## Debugging Workflow Failures

When a workflow fails, diagnose systematically:

1. **Read the error message literally.** "Resource not accessible by integration" means a missing permission. "Unsupported event type" means the trigger isn't handled. Do not guess — match the error to the cause.
2. **Check permissions first.** Most failures are permission issues.
3. **Check the action version and inputs.** Fetch the `action.yml` for the version in use and confirm every input name is valid.
4. **Inspect the event payload.** Add a debug step: `run: echo '${{ toJson(github.event) }}'` to see what context is actually available.
5. **One fix at a time.** Change one thing, push, observe. Do not stack multiple speculative fixes.
6. **Fetch docs when stuck.** If you cannot diagnose from the error alone, fetch the relevant source file from the claude-code-action repo rather than guessing.

### Common Failure Patterns

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Resource not accessible by integration` | Missing permission scope | Add the required permission at job level |
| `403` on `git push` | Missing `contents: write` | Add `contents: write` to job permissions |
| Secret value is empty (no error) | Fork PR, wrong scope, or typo in secret name | Check: is this a fork PR? Is the secret scoped to an environment the job doesn't declare? Does the name match exactly? |
| `Invalid OIDC token` | Anthropic's GitHub App is not installed on the repo | Pass `github_token: ${{ github.token }}` to bypass OIDC exchange |
| `Error: OIDC token request failed` | Missing `id-token: write` permission | Add `id-token: write` to job permissions (only needed if using default OIDC path) |
| `Unsupported event type` | Trigger not handled by claude-code-action | Fetch `context.ts` to confirm supported events |
| Claude posts no comment / takes no action | Missing context in `prompt` | In automation mode, Claude doesn't receive PR/issue context automatically — add `${{ github.event.pull_request.number }}` etc. to the prompt |
