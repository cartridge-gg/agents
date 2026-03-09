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
- **Are fork PRs involved?** This affects event type and secret access.

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
