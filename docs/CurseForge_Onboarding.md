# CurseForge Onboarding

## Project Setup

Use these values when creating the CurseForge project:

- **Name:** I Can't Even Right Now (With My Bags and Bank)
- **Slug:** `icant-even-right-now`
- **Category:** Bags & Inventory
- **Game:** World of Warcraft Retail
- **Project ID:** `1534906`
- **License:** All Rights Reserved on CurseForge; source code MIT and addon artwork/Finalomega brand assets all rights reserved in-repo
- **Source:** `https://github.com/majormer/ICantEvenRightNow`
- **Issues:** `https://github.com/majormer/ICantEvenRightNow/issues`

The CurseForge project ID is set in `ICantEvenRightNow.toc`:

```toc
## X-Curse-Project-ID: 1534906
```

## GitHub Release Automation

The release workflow uses `BigWigsMods/packager@v2` and reads packaging settings from `.pkgmeta`.

Before tagging a release:

1. Create a CurseForge API token at <https://wow.curseforge.com/account/api-tokens>.
2. Add it to the GitHub repository secrets as `CF_API_KEY`.
3. Confirm `X-Curse-Project-ID` in `ICantEvenRightNow.toc` is `1534906`.
4. Make sure `CHANGELOG.md` has a dated release section for the version.
5. Tag the release with `vX.Y.Z` that matches `## Version:` in `ICantEvenRightNow.toc`.

The workflow will create the packaged addon zip and publish it through the packager. If `X-Curse-Project-ID` is blank, CurseForge upload is skipped/not possible, but GitHub packaging can still run.

## Manual First Upload Option

If CurseForge requires a manual file upload (for example, first-project review), build a local zip with:

```powershell
.\scripts\Build-Release.ps1 -Version 0.2.0
```

Upload the generated file from `build/` as a Retail release.

## Release Checklist

1. Verify the addon in-game after `./scripts/Copy-ToWoW.ps1` and `/reload`.
2. Update `CHANGELOG.md` from `[Unreleased]` to the release version and date.
3. Confirm `## Version:` in `ICantEvenRightNow.toc` matches the tag.
4. Confirm `## X-Curse-Project-ID:` is set.
5. Push a `vX.Y.Z` tag.
6. Check the GitHub Actions release run and CurseForge file status.

For the full repeatable process, see `docs/Release_Process.md`.
