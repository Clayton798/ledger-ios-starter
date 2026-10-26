# Verification — 2026-10-26

This is a record of tested behavior, not a guarantee that every possible bug has been eliminated.

## Core

63 Swift tests pass. Coverage includes integer-cent calculations, backup validation and round trips, restore conflicts, duplicate detection, independent period budgets, period start days and short months, date boundaries, New York midnight and daylight saving transitions, timezone differences, unknown screenshot dates, Chinese bank-message extraction, merchant aliases, and French manual decimal input.

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

## Search usability follow-up

Added current/all-period search, matching record count and net spending, and a return-to-current-period action. Search supports multiple words, merchant names, translated categories, notes, ISO dates and original/net amounts. Voided entries may be displayed but never contribute to the result total; refunds reduce the original purchase’s amount. The scope does not modify stored dates or budgets.

63 core tests pass. Three focused interface tests passed for cross-period scope and return-to-current, the existing search/guide flow, and shared period navigation/background return. The signed build was installed and launched, and the complete before/after device ledger snapshots matched. No private snapshots are in this repository.

Design references: [Actual transaction filtering](https://actualbudget.org/docs/transactions/filters/) and [YNAB search, sorting and filtering](https://support.ynab.com/en_us/searching-transactions-a-guide-r1gxyQryj?mobile-help=true). These informed the local search workflow; no service integration was added.

## Previously skipped photo-picker tests completed

Both photo-picker end-to-end cases now passed on a fresh dedicated simulator with synthetic images. The initial image saved Example Cafe USD 12.34 and Louis Vuitton USD 55.00, both dated October 25. The overlapping image defaulted to selecting only New Grocery USD 9.25 dated October 26. Importing that same image again selected zero entries and disabled saving. Reading the simulator ledger confirmed exactly these three entries after the sequence.

The automation was corrected to wait for the ready overview, select the actual nested confirmation switch, and scroll the final save action into view. No app functionality changed during this follow-up. The previously signed latest app was reinstalled and launched at the user's request; before/after device ledger contents matched exactly. The earlier skipped-test limitation is now resolved for these two fixtures; unfamiliar real screenshots still require review.

## Budget clarity and backup reminders

The overview labels its remaining amount as budget remaining and explains that it is based on recorded net spending, not a bank balance. Refund entry displays the exact original spending period it will affect. The cycle editor shows the transition length in calendar days so a short or long period can receive its own budget. All new explanatory text has Chinese, English and French translations.

Settings records the time only after a successful export of the current ledger. Exporting an older safety copy or raw file does not advance that time. A local reminder appears when there are entries and no recorded export time, or the last export was at least seven days ago. This is not an automatic backup or a verification that a previously saved file still exists. Import wording now explains merging and conflict rejection instead of implying a complete rollback.

65 core tests pass, including seven-day reminder boundaries, future timestamps, leap February, and 9-day and 51-day transition periods. The cycle/independent-budget UI case and the overview/backup-status UI case passed. The latter was rerun successfully after the final copy and date-locale changes. The system file picker export completion was code-reviewed but not automated in this follow-up. The refund UI case initially exposed a save button that was not hittable with the keyboard visible; a fixed top action row now clears focus, and the partial-refund/save/relaunch/correction case passed after the fix.

The signed device build succeeded. After device access became available, a fresh pre-install ledger backup was saved, the build was installed and launched successfully, and the full post-install ledger compared equal to the pre-install snapshot. Private ledger snapshots are kept outside this repository.

## Everyday-use review: protect input and clarify context

Reviewed entry, refund, batch review, search, budget and persistence boundaries. The concrete gap was that transaction sheets could discard unsaved work even though budgets already had an exit decision. A shared `UnsavedChangesGuard` now prevents interactive dismissal while there is unsaved work and offers continue/discard on explicit close. Blank manual entries still close immediately. Receipt review also asks before leaving its recognized content. This protects the current editing session; it does not claim recovery after process termination.

Entry forms now preview the destination budget period next to the date. Empty search results explain the current scope and offer clearing the search or viewing all periods; the section heading also follows the scope. These changes keep the existing typography, palette and layout hierarchy. Added text is localized in Chinese, English and French.

Design reference: [Apple HIG — Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data), particularly clarity about requested data and reducing input mistakes.

65 core tests passed unchanged. Focused UI tests passed for cross-period search, unsaved manual-entry continue/discard and reopening a blank form, and partial refund persistence/correction. Further regression and device verification results follow below. No new financial schema or calculation changes were introduced.

Final focused regression passed: language switching/relaunch, manual entry/save/relaunch/void, and partial refund with cancel → continue-editing → save → relaunch → correction. The signed build was installed and launched on the connected phone; a fresh complete before/after ledger comparison matched. The batch-review exit guard shares the same component but its photo-picker path was not rerun in this follow-up. OCR accuracy on unfamiliar images and recovery of unsaved input after process termination remain explicit limitations.
