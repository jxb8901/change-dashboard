# Architecture

Command Executor -> Table Parser -> Threshold Evaluator -> Frame Builder -> Frame Diff -> Terminal

## Frame Builder
- Converts each visible panel content region into non-overlapping cells.
- Each cell contains row, column, width, padded text, and severity style.
- Raw lines occupy one full-width cell; table values occupy configured cells.

## Frame Diff
- Clears cells present only in the previous frame.
- Draws new cells and cells whose text or style changed.
- Replaces the cache after each render.
- A resize invalidates the cache and forces one complete redraw.

## Terminal Lifecycle
- The signal handler only records a resize request.
- The main loop validates dimensions and controls pause/recovery.
- Static chrome is rebuilt only on initial render or valid resize.

## Boundaries
- Parsing and threshold evaluation remain independent from rendering.
- Command scheduling remains global and synchronous.
- Config remains trusted Bash source input.
