# Verification — 2026-10-26

This is a record of tested behavior, not a guarantee that every possible bug has been eliminated.

## Core

62 Swift tests pass. Coverage includes integer-cent calculations, backup validation and round trips, restore conflicts, duplicate detection, independent period budgets, period start days and short months, date boundaries, New York midnight and daylight saving transitions, timezone differences, unknown screenshot dates, Chinese bank-message extraction, merchant aliases, and French manual decimal input.

## Interface checks

The following focused simulator checks passed after correcting stale automation selectors and startup/scroll timing:

- Chinese → English → French → Chinese switching, French entry form, and retained language after restarting.
- Editable period start day, retained selection, and an unset budget in the next period.
- New purchase, restart persistence, voiding, and displaying the voided entry after restarting.
- Budget editing, saving, and reloading the saved amount.
- Ring, bar and daily trend views, including retained chart choice after restarting.
- Shared period selection between pages and return from background.
- On-device Vision recognition of synthetic Chinese and English receipts.

The device build also succeeded. Interface tests use fictional data in a dedicated simulator. No personal ledger files, signing identities or device identifiers are included here.

## Remaining scope limits

OCR can misread an unfamiliar layout. An image containing only relative labels such as “today” or “yesterday” cannot establish an absolute transaction date without confirmation. A translated interface is not general-purpose document translation, and French bank-statement OCR has not been broadly validated. USD purchase refunds are entered against the original purchase and reduce that purchase period’s net spending. Income, exchange-rate conversion and automatic refund matching remain outside this version. See the README for installation and backup limitations.

## Refunds and preserved period history

Core tests cover partial and full refunds, cumulative caps, invalid dates, atomic rejection, refund correction, backup round trips and schema version guards. Scheduled start-day changes preserve the current and historical periods; a transition period bridges the new schedule. All combinations of days 1, 22, 28, 29, 30 and 31 were checked across a year boundary and leap February, with each day assigned exactly once.

Focused UI regression checks passed for scheduled cycle changes (current period unchanged after save and restart), partial refund persistence and refund correction, and the modal budget editor (cancel leaving, dirty dismissal protection, draft recovery after restart, save before switching periods, and reloaded budget values). Simulator data is fictional. Device signing and installation were verified separately; personal data is not included in this repository.

## Whole-app audit follow-up

The audit reproduced and fixed the following regressions:

- An inaccessible ledger or a non-directory parent path could be mistaken for a new empty ledger. Only a genuinely missing file now starts a new ledger. Locked-file loading is retried after protected data becomes available or the app returns to the foreground.
- Incoming payments, repayments and simple refund receipts could enter the purchase flow. These are blocked, with a link in the wording to recording refunds against the original purchase.
- A transaction with its own date did not terminate an older statement date heading. Subsequent undated transactions now require confirmation instead of inheriting that stale heading.
- Merging a malformed current ledger could trap when constructing a dictionary with duplicate record IDs. The current ledger is validated before merging.
- Date validation repeatedly allocated formatters. Calendar-only validation now uses Gregorian arithmetic, with leap-year and supported-range cycle-boundary coverage.

Additional hardening bounds decoded OCR images to 4096 pixels on the longest side before Vision, moves receipt parsing off the main actor, protects presented editing sheets when inactive, clears obsolete budget drafts after a successful restore, and removes an animation isolation warning without changing the animation timing.

All six new core regression cases pass alongside the existing suite (62 core tests). Across the full run and targeted reruns, all 17 runnable interface cases passed. Two photo-picker fixtures were explicitly skipped because they require a separately seeded image library; they were not counted as passing. Initial failures exposed two startup-timing assumptions in automation and a real budget-save hit-target issue with the keyboard visible. The selectors now wait for the ready overview, and budget saving lives in the fixed top bar, clears keyboard focus, and was verified by saving and reopening the value. Unsaved-budget guard and draft recovery were rerun after that layout change.

The final signed build was installed and launched on the connected iPhone. A fresh device ledger snapshot before and after the update compared equal in its entirety, including records and settings. These private snapshots remain outside the repository.
