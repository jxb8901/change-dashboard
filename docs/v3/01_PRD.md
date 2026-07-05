# Change Dashboard V3 PRD

## Goal
Improve terminal usability without changing the local, Bash-first verification model.

## Requirements
- Draw static panel borders and titles once.
- Refresh only content cells whose text or severity changed.
- Use full-cell background colors for warning and error values.
- Support configured table column widths and truncation.
- Support explicit single-row key/value transpose layout.
- Handle empty output and terminal resize clearly.

## Compatibility
- V1 raw-output configs remain valid.
- V2 table configs without widths retain equal-width columns.
- Commands continue to run locally, synchronously, and in panel order.

## Out Of Scope
- Remote execution, history, alerts, independent scheduling, and automatic layout scaling.
- Unicode display-width calculation.
