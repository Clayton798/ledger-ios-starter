# Verification — 2026-10-26

This is a record of tested behavior, not a guarantee that every possible bug has been eliminated.

## Core

50 Swift tests pass. Coverage includes integer-cent calculations, backup validation and round trips, restore conflicts, duplicate detection, independent period budgets, period start days and short months, date boundaries, New York midnight and daylight saving transitions, timezone differences, unknown screenshot dates, Chinese bank-message extraction, merchant aliases, and French manual decimal input.

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

OCR can misread an unfamiliar layout. An image containing only relative labels such as “today” or “yesterday” cannot establish an absolute transaction date without confirmation. A translated interface is not general-purpose document translation, and French bank-statement OCR has not been broadly validated. Only positive USD purchases are supported; refunds, income and currency conversion remain outside this version. See the README for installation and backup limitations.
