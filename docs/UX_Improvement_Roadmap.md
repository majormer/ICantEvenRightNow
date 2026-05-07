# UX Improvement Roadmap

## 1. Context

Recent testing surfaced repeated friction around high-frequency flows, especially:

- AH pull from bank
- Recommended-only defaults obscuring actionable rows
- Filter semantics around BoE vs WuE

The addon already has strong filtering and explicit movement controls. The main UX opportunity is to make those strengths easier to access without reducing safety.

## 2. UX Goals

- Reduce setup clicks for common workflows
- Clarify the difference between recommendation and actionability
- Keep conservative safeguards while allowing intentional manual workflows
- Make filter behavior predictable and discoverable

## 3. Priority Improvements

### P0: Mode Presets for High-Frequency Work

Add command and UI presets that configure tab, mode, and filters in one action.

Suggested presets:

- AH Pull BoE:
  - Tab: Move
  - Mode: Recall from Bank
  - Type: BoE
  - Recommended only: off
  - Location: Bank
- WuE Dump:
  - Tab: Move
  - Mode: Dump to Bank
  - Type: WuE
  - Recommended only: off
  - Location: Bags
- Legacy Cleanup:
  - Tab: Move
  - Mode: Dump to Bank
  - Expansion: Not current
  - Recommended only: on

Expected benefit:

- Eliminates repetitive setup errors
- Aligns addon with real user jobs rather than raw controls

### P0: Recommendation vs Actionability Clarity

Current ambiguity:

- Users may interpret disabled rows as "cannot move" when they only mean "not recommended"

Proposed changes:

- Introduce an explicit row state field in UI text:
  - Recommended
  - Actionable (manual)
  - Blocked
- Replace generic blockers with policy class labels:
  - Rule blocked
  - Context blocked
  - Capacity blocked
  - Recommendation-only hidden

### P1: Filter Model Improvements

#### A. Split filter dimensions

Current type filter mixes item type and bind semantics.

Proposed two-dropdown model:

- Item Type: All, Profession, Consumable, Equipment, etc.
- Bind Type: All, BoE, WuE, Soulbound, Warbound

Benefits:

- Avoids overloading one filter control
- Reduces confusion when items are equipment but not BoE/WuE

#### B. Add Actionability quick filter

Add "Can Act Now" toggle to only show rows currently selectable.

Benefits:

- Removes cognitive load from disabled rows
- Speeds up batch operations

### P1: Better Empty and Disabled Explanations

Enhance list states with top reason counts, for example:

- 12 filtered by recommendation-only
- 5 blocked by current-expansion policy
- 3 blocked by no bag space

Benefits:

- Immediate diagnosis without hovering many rows

### P2: Workflow-specific Footer Actions

Contextual footer action text:

- Move tab in Recall mode + BoE filter: `Recall BoE Selected`
- Move tab in Dump mode + WuE filter: `Bank WuE Selected`

Benefits:

- Reinforces user intent and reduces misclick anxiety

## 4. Proposed Implementation Plan

## Phase 1 (Low Risk)

- Add slash presets (`/icanteven ahpull`, `/icanteven wuedump`, `/icanteven legacycleanup`)
- Improve row detail text for recommendation/actionability status
- Improve empty-state diagnostics

## Phase 2 (Medium Risk)

- Add bind-type filter dropdown
- Keep current type filter for compatibility, then migrate
- Add `Can Act Now` toggle

## Phase 3 (Optional)

- Introduce per-flow mini-wizards (single panel quick actions)
- Add persistent "last workflow" restoration

## 5. Acceptance Criteria for AH Pull UX

A successful AH pull UX should satisfy all:

1. From bank, user can run one command or click one preset.
2. List shows only auctionable BoE items by default.
3. WuE items are excluded unless explicitly requested.
4. Selected items are immediately recallable with no recommendation-policy friction.
5. Empty states explain exactly why no rows are shown.

## 6. Safety Guardrails to Preserve

Do not remove:

- Explicit user selection before action
- Rule-based hard blocks (`Protect`, `Ignore`, `Never Move`)
- Context checks (bank/vendor/combat)
- Conservative defaults for ambiguous content

The roadmap should improve speed and clarity without relaxing core safety principles.
