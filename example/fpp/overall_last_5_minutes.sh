#!/usr/bin/env bash
set -u

random_between() {
  local minimum="$1" maximum="$2"
  printf '%s' "$((minimum + RANDOM % (maximum - minimum + 1)))"
}

# Simulate a slower dashboard command that takes 500-1500 milliseconds.
delay_ms=$((500 + RANDOM % 3001))
printf -v delay_seconds '%d.%03d' "$((delay_ms / 1000))" "$((delay_ms % 1000))"
sleep "$delay_seconds"

for app in 03 04 05 06 09 10 21 22 23 24; do
  printf '%s %s %s %s %s %s\n' \
    "$app" \
    "$(random_between 0 5)" \
    "$(random_between 0 5)" \
    "$(random_between 0 5)" \
    "$(random_between 900 1500)" \
    "$(random_between 5 50)"
done
