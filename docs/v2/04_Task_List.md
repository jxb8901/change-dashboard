# Task List

## Task 1: Update V2 Docs
- Align PRD, functional spec, architecture, task list, test plan, and changelog.
- Remove summary bar and independent refresh from V2 scope.

## Task 2: Threshold Config Validation
- Add optional table column and rule arrays.
- Validate column names, unknown rule columns, and condition syntax.
- Keep V1 configs valid without V2 arrays.

## Task 3: Condition Evaluator
- Parse operators and condition values.
- Support numeric comparisons.
- Support string `==` and `!=`.
- Return `OK`, `WARN`, or `ERROR`.

## Task 4: Table Parser
- Parse stdout into table rows when field counts match.
- Fall back to raw rendering when parsing fails.

## Task 5: Color Rendering
- Add ANSI color helpers.
- Color warning/error cells.
- Color panel border/title by worst panel status.
- Reset colors after colored text.

## Task 6: V1 Compatibility
- Confirm raw panels still render.
- Confirm `config/sample.conf` and `config/fpp.conf` still run.

## Task 7: V2 Sample Config
- Add a sample config with multi-column table data.
- Include OK, WARN, ERROR, command failure, and parse fallback examples.

## Task 8: Manual Acceptance
- Run V2 test plan.
- Confirm global refresh continues.
