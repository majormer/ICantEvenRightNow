# Documentation Index

This folder contains implementation and product documentation for I Can't Even Right Now (With My Bags and Bank).

## Docs in this folder

- Technical architecture: `Technical_Architecture.md`
- User flows and use cases: `User_Flows_and_Use_Cases.md`
- UX roadmap and design recommendations: `UX_Improvement_Roadmap.md`
- 0.3.0 filter-first scope plan (historical, 17KB): `0.3.0_Filter_First_Action_Model_Plan.md`
- Release runbook: `Release_Process.md`
- CurseForge docs: `CurseForge_Description.md`, `CurseForge_Onboarding.md`

## Project root docs

- Project README: `../README.md`
- Release changelog: `../CHANGELOG.md`

## Suggested read order

1. `README.md` for user-facing overview and features.
2. `Technical_Architecture.md` for implementation details.
3. `Release_Process.md` for shipping and publishing steps.
4. `User_Flows_and_Use_Cases.md` for what users are trying to accomplish.
5. `UX_Improvement_Roadmap.md` for concrete product and UI changes.
6. `CHANGELOG.md` for version history and release notes.

## Scope

These docs reflect the current multi-module addon architecture (`Shared`, `Evaluator`, `Filter`, `Scanner`, `Transfer`, `UI`, `Core`) introduced in 0.4.0.
They are intended to support both:

- Engineering work (refactors, bug fixes, and feature additions)
- Product and UX improvements (especially high-frequency inventory workflows)

## Documentation Maintenance

Update these docs when:
- A new module is added or split (update `Technical_Architecture.md`)
- A new filter or feature is added (update `README.md`, `Technical_Architecture.md`, `User_Flows_and_Use_Cases.md`)
- UX changes are shipped (update `UX_Improvement_Roadmap.md`)
- Release process changes (update `Release_Process.md`)
- Major version ships (update `CHANGELOG.md` and review all docs for accuracy)
