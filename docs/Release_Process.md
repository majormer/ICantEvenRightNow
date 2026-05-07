# Release Process

This runbook describes the repeatable process to publish a new addon release through GitHub Actions and the WoW packager.

## What is automated

- Workflow: `.github/workflows/release.yml`
- Trigger: push tag matching `v*` or manual `workflow_dispatch`
- Packager: `BigWigsMods/packager@v2`
- Changelog source: `.pkgmeta` -> `manual-changelog` -> `CHANGELOG.md`

## Prerequisites (one-time)

1. CurseForge project exists and `X-Curse-Project-ID` is set in `ICantEvenRightNow.toc`.
2. GitHub repository secret `CF_API_KEY` is configured.
3. Release workflow file is committed to the repository.

## Prerequisites (each release)

1. Working tree is clean enough to isolate release-intended changes.
2. `CHANGELOG.md` contains a dated section for the version (for example `## [0.3.0] - YYYY-MM-DD`).
3. `## Version:` in `ICantEvenRightNow.toc` matches the release version (for example `0.3.0`).
4. Lua syntax passes:

```powershell
luac -p Core.lua Data.lua Debug.lua
```

5. In-game smoke check completed (copy + `/reload`).

## Standard release flow

1. Commit all release changes on your working branch.
2. Open and merge PR into `main`.
3. Update local `main` from origin.
4. Create and push annotated tag `vX.Y.Z`.

Example commands:

```powershell
git checkout main
git pull --ff-only origin main
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
```

## Verification flow

1. Confirm the Release workflow started for the tag.
2. Confirm `WoW Packager` step succeeded.
3. Confirm GitHub Release exists for tag `vX.Y.Z`.
4. Confirm CurseForge file appeared for the project.

Useful commands:

```powershell
gh run list --workflow "Release" --limit 5
gh run view <run-id> --json status,conclusion,url,jobs
gh release list --limit 5
```

## Troubleshooting

### Workflow did not run

- Ensure the tag matches `v*`.
- Ensure `.github/workflows/release.yml` is present on default branch.

### Packager fails on upload

- Confirm `CF_API_KEY` exists in repo secrets.
- Confirm `X-Curse-Project-ID` is set in `ICantEvenRightNow.toc`.

### Upload succeeded but file is not visible on CurseForge

- Check the project Files tab filters (game version and release type).
- Confirm the file status in CurseForge project management, since first-project moderation or delayed indexing can hide newly uploaded files temporarily.
- Recheck after a short delay; packager success in GitHub Actions means the upload request completed successfully.

### Changelog missing in release notes

- Confirm `.pkgmeta` contains:
  - `manual-changelog.filename: CHANGELOG.md`
  - `manual-changelog.markup-type: markdown`

## Changelog policy

Follow the rules at the top of `CHANGELOG.md`:

- Only user-facing deltas from previous released version.
- Do not log mid-cycle test-only fixes as release regressions unless users previously saw them.
- Prefer Added/Changed/Improved wording for in-cycle refinement.

## Verified example: 0.2.0

- PR merged: `#1` (`dev` -> `main`)
- Tag pushed: `v0.2.0`
- Release workflow run: `25470716468` (success)
- GitHub release: `v0.2.0` (published)
