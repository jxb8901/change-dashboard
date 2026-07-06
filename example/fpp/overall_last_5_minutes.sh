#!/usr/bin/env bash
set -u

random_between() {
  local minimum="$1" maximum="$2"
  printf '%s' "$((minimum + RANDOM % (maximum - minimum + 1)))"
}

for app in 03 04 05 06 09 10 21 22 23 24; do
  printf '%s %s %s %s %s %s\n' \
    "$app" \
    "$(random_between 0 5)" \
    "$(random_between 0 5)" \
    "$(random_between 0 5)" \
    "$(random_between 900 1500)" \
    "$(random_between 5 50)"
done
