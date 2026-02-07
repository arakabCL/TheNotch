# Software Engineering Cheat Sheet (No Automated Tests)

## Purpose
Use this workflow for feature work with coding agents when you want fast iteration, clean branches, and reliable build quality without automated test execution.

## -1) Sync
- Fetch latest main branch state.
- Pull latest main branch updates.
- Update/install dependencies (language/package-manager specific).
- Create a fresh feature branch from main.

Example commands (replace as needed):
```bash
git fetch origin
git checkout main
git pull origin main
# install/update deps for your stack
git checkout -b feature/short-name
```

## 0) Validate Environment Early
- Confirm dependency install is deterministic and reproducible.
- Confirm required SDKs/toolchains are available.
- If environment is unstable or missing critical dependencies, stop and fix environment first.

## 1) Branch Discipline
- One branch per feature or fix.
- No unrelated changes in the same branch.
- No direct commits to main.
- Keep changes scoped and reversible.

## 2) Agent Constraints
- Agent must not run `git commit` or `git push` unless explicitly requested.
- Agent should use verifiable sources for APIs/libraries.
- Preferred source: official docs.
- Preferred source: source-of-truth package documentation.
- Preferred source: installed package metadata or local tooling output.

## 3) Definition of Done (DoD)
Only mark the task done when all are true:
- LINT: Linting passes with 0 errors.
- COMPILE: Type-check/compile step succeeds.
- BUILD: Project builds successfully in local environment.
- CLEANUP: Remove debug logs, temporary prints, and commented-out code.
- DOCS: Update README or local docs briefly if behavior/config changed.

## 4) Stop Criteria
- If build/compile still fails after 3 full fix-and-rebuild iterations, stop and report.
- Report item: what failed.
- Report item: what was tried.
- Report item: exact blocker.
- Report item: minimal next action needed from user.

## 5) Manual Validation Handoff
- User performs manual feature validation.
- Agent provides: what changed.
- Agent provides: how to run the updated build.
- Agent provides: what manual checks to perform.

## 6) Optional PR Handoff (When You Are Ready)
- Prepare clean diff.
- Summarize changes and risks.
- Open PR with focused scope and rollout notes.
