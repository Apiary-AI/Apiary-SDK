# TASK-035: CI/CD Pipeline (GitHub Actions)

**Status:** In Progress
**Branch:** `task/035-ci-cd-pipeline`
**Depends On:** 004 (Test infrastructure), 034 (E2E integration tests)

## Objective

Set up a GitHub Actions CI pipeline that runs on every push to `main` and every
pull request. The pipeline validates code quality, runs the full test suite,
verifies the frontend build, and checks SDK quality — providing fast, reliable
feedback for every change.

## Requirements

### CI Workflow (`.github/workflows/ci.yml`)

1. **PHP Lint** — Run Laravel Pint in check mode (`vendor/bin/pint --test`)
2. **PHP Tests** — Run the full PHPUnit suite (Unit + Feature) with SQLite
   in-memory, matching the existing `phpunit.xml` and `.env.testing` config
3. **Frontend Build** — Verify `npm ci && npm run build` succeeds (Vite + React)
4. **Python SDK** — Run Ruff lint/format checks and pytest for `sdk/python`

### Optimization

- Composer dependency caching (`actions/cache` keyed on `composer.lock`)
- npm dependency caching (built-in `actions/setup-node` cache)
- pip dependency caching (built-in `actions/setup-python` cache)
- Parallel jobs for independent checks
- Fail-fast disabled so all jobs complete even if one fails

### Artifacts & Visibility

- Upload Laravel log on test failure for debugging
- Clear job names for at-a-glance PR status

### Safety

- No deploy automation — CI only
- No secrets required for any job
- No force-push or destructive operations

## Non-Goals

- CD / deployment automation (future task)
- Docker image builds in CI (heavy, not needed yet)
- Code coverage reporting (can be added later)
- Browser/E2E testing in CI (requires full Docker stack)

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | New — CI pipeline definition |
| `docs/tasks/TASK-035-ci-cd-pipeline.md` | New — this task file |
| `docs/guide/ci-cd.md` | New — VitePress guide for CI/CD usage |
| `docs/index.md` | Updated — link to CI/CD guide |

## Test Plan

- [ ] Workflow YAML is valid (parseable, no syntax errors)
- [ ] All four jobs are defined and run in parallel
- [ ] PHP lint job runs Pint in test mode
- [ ] PHP test job runs full PHPUnit suite with SQLite
- [ ] Frontend build job compiles without errors
- [ ] Python SDK job runs ruff + pytest
- [ ] Caching is configured for all dependency managers
- [ ] Failure artifacts (Laravel log) are uploaded on test failure
- [ ] Workflow triggers on push to main and on PRs to main

## Acceptance Criteria

- CI workflow file committed and pushed
- All jobs pass on the PR branch
- Documentation added and linked from docs index
- PR opened and ready for review
