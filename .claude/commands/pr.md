---
description: Open a pull request for the current branch using .github/PULL_REQUEST_TEMPLATE.md
argument-hint: "[optional extra context for the PR description]"
---

Open a pull request for the current branch, filling in `.github/PULL_REQUEST_TEMPLATE.md` based on what actually changed.

Extra context from the user (may be empty): $ARGUMENTS

## Step 1 — Survey the branch

Run these in parallel:

- `git status` (no `-uall`)
- `git rev-parse --abbrev-ref HEAD` to confirm the current branch
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}` to see if it tracks a remote (may fail — that's fine, means the branch isn't pushed yet)
- `git log main..HEAD --oneline` for the commit list
- `git diff main...HEAD --stat` for a file-level summary
- `git diff main...HEAD` for the full diff
- Read `.github/PULL_REQUEST_TEMPLATE.md`

If the current branch is `main`, stop and tell the user — no PR to open.

## Step 2 — Bump the version

Frameflow is a Swift Package Manager project. The version is tracked in the `VERSION` file at the repo root, which `scripts/build-app.sh` reads when packaging the `.app` bundle:

- Line 1 — `MARKETING_VERSION`, semver `MAJOR.MINOR.PATCH` (e.g. `1.0.1`).
- Line 2 — `CURRENT_PROJECT_VERSION`, monotonic build number.

Read the current values (`cat VERSION`), then decide the bump from the diff:

- **Patch** (default): bug fixes, refactors, internal-only work, tests, docs, build/tooling tweaks, dependency bumps without behavior change.
- **Minor**: a new user-visible feature, a new screen/module, a new theme, a new timeline/composer capability, or any meaningful capability addition.
- **Major**: a breaking change, removal of a major feature, fundamental UX overhaul, or anything the user should explicitly opt into. **Always pause and confirm with the user before bumping major.** Show your reasoning and the proposed new version.

Always increment the build number on line 2 by 1, regardless of which semver part bumps.

Write the new two-line file with the `Write` tool. Then also update the dev fallback in `Sources/Frameflow/App/ContentView.swift` — find `appVersionString` and update the literal string after `return ` to match the new marketing version (this fallback is what `swift run` uses when there's no Info.plist).

Commit just the `VERSION` file and the `ContentView.swift` fallback update with a message like:

```
Bump version to <new version> (build <new build>)
```

Do not bundle other unrelated changes into this commit.

## Step 3 — Keep the README current

Read `README.md` and compare it against what the branch changed. Update the README whenever the branch alters anything that the README documents, for example:

- User-visible features, themes, or modes listed in the Features section.
- Setup, environment variables, or required tooling.
- Scripts under `scripts/` or the build/install commands they wrap.
- Project layout (new top-level files, renamed modules, removed components).

If nothing the README covers actually changed, leave it alone — do not churn the file just to touch it. If you do edit it, commit only the README change with a message like `Update README for <short summary>` so the PR diff stays clean. If you decide no update is needed, briefly note that reasoning to the user in Step 5.

## Step 4 — Draft the PR

Read every commit in the range, not just the latest. Synthesize a PR body that follows the template *exactly* (section order, headings, checkboxes), filling in real content drawn from the diff and commit history:

- **Title**: short (under 70 chars), imperative mood, no trailing period. Don't restate the branch name.
- **Summary**: 1–3 bullets covering what changed and why. Lead with the user-visible change when there is one.
- **Type of Change**: tick the boxes that apply based on the diff (e.g. SwiftUI view files changed → UI/UX update, new `*.swift` file with a new feature → New feature, etc.). Leave others unchecked.
- **Related Issues**: leave the placeholders unless the user's `$ARGUMENTS` mention an issue number.
- **User Impact**: what someone using the app will notice. If purely internal, say so.
- **Implementation Notes**: call out non-obvious decisions you can see from the diff (new abstractions, AppKit interop, theme token additions, etc.). Skip if the change is trivial.
- **Screenshots or Recordings**: leave the table empty but keep the header — the user will paste in screenshots themselves.
- **Test Plan**: tick `Built successfully with swift build` only if you can confirm a successful build occurred on this branch (e.g., from session context). Otherwise leave unchecked. Tick others only when you have direct evidence. Fill in the Commands run code block with any `swift build` / `scripts/build-app.sh` / test commands that were actually run; otherwise leave it empty.
- **Risk and Rollback**: short, specific. "Rollback: revert commit `<sha>`" is fine.
- **Release Notes**: one user-facing line, or `None` for internal-only changes.
- **Reviewer Checklist**: leave all unchecked — the reviewer ticks these.

If `$ARGUMENTS` is non-empty, weave that context into the Summary / Implementation Notes / Risk sections where it fits.

## Step 5 — Confirm before pushing

Show the user the drafted title and body, a one-line reminder of the version bump applied in Step 2, and a one-line note on the README (either the change made in Step 3 or that no update was needed). Ask if they want to proceed. Do NOT push or create the PR until they confirm.

## Step 6 — Push and create

After confirmation, run in parallel where possible:

- If the branch has no upstream (step 1 showed no `@{u}`), `git push -u origin HEAD`. Otherwise `git push` (the version-bump commit from step 2, plus any README commit from step 3, makes this branch ahead of remote).
- `gh pr create --title "<title>" --body "$(cat <<'EOF'\n<body>\nEOF\n)"` — pass the body via heredoc so markdown formatting is preserved.

Do not append a "Generated with Claude Code" footer — the project template doesn't include one.

Return the PR URL printed by `gh pr create` so the user can open it.

## Guardrails

- Never force-push.
- Never push to `main` directly.
- If `gh` is missing or unauthenticated, stop and tell the user to run `gh auth login` themselves (suggest `! gh auth login` so it runs in their session).
- If there are uncommitted changes, ask the user whether to include them in a new commit before opening the PR, or proceed without them.
