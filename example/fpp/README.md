# FPP LHC Prototype

This example reproduces the panel layout and sample values from
`fpp.lhc.numbers`.

## Run

Use a terminal of at least 104 columns by 27 rows:

```bash
./bin/lhc example/fpp.conf
```

## Structure

- `../fpp.conf` defines the five-panel layout, table columns, widths, and rules.
- This directory contains one executable shell per panel.
- Each shell currently prints static prototype data and can be replaced with a
  production command while keeping the same whitespace-separated output shape.

Transaction messages use underscores because LHC table cells cannot contain
whitespace. Missing rejection fields use `-` placeholders.
