#!/usr/bin/env bash
set -u

random_total() {
  # Generate a value from 8500 through 11500, within 15% of 10000.
  printf '%s' "$((8500 + RANDOM % 3001))"
}

printf '%s %s %s %s %s %s\n' \
  "$(random_total)" \
  "$(random_total)" \
  "$(random_total)" \
  "$(random_total)" \
  "$(random_total)" \
  "$(random_total)"
