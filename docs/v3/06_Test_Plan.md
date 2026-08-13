# Test Plan

## Rendering
- Confirm the first cycle contains one clear-screen sequence.
- Confirm an unchanged second cycle emits no content-cell writes.
- Change one value or severity and confirm only that cell is redrawn.
- Shrink output and confirm removed text is cleared.
- Switch raw/table/failure modes and confirm no stale content remains.

## Tables
- Verify configured widths, padding, truncation, and numeric alignment.
- Reject invalid width count, non-positive width, and excessive total width.
- Verify omitted widths preserve V2 equal-width behavior.
- Verify single-row and multi-row transpose rendering and threshold mapping.
- Verify a field-count mismatch falls back to raw output.

## Resilience
- Verify empty successful output displays `No data`.
- Verify `NO_COLOR` emits no warning/error color sequences.
- Resize to a valid size and confirm one full redraw.
- Resize below the configured layout, confirm commands pause, then recover.
- Verify `q` and Ctrl+C restore cursor and terminal attributes.
