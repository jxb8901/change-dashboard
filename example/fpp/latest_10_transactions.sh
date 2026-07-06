#!/usr/bin/env bash
set -u

transactions=(
  '03:15:16 03 EAI123 CT001 P S SUCC 1098 230 800 12 - -'
  '03:15:15 04 EAI124 CT001 C - RJCT 1098 230 800 12 FPP050 Failed_to_Check_Account'
  '03:15:15 09 EAI115 CT001 C - RJCT 1098 230 800 12 FPP050 Failed_to_Check_Account'
  '03:15:14 03 EAI132 ADR001 C A SUCC 8098 230 800 12 - -'
  '03:15:13 10 ICL100 Pacs002 C - SUCC 1098 230 800 12 - -'
  '03:15:12 24 ICL111 Pacs008 C - RJCT 1098 230 800 12 FPP050 Failed_to_Check_Account'
  '03:15:10 22 ICL120 Pacs003 C - SUCC 1098 530 800 12 - -'
  '03:15:01 21 EAI099 CT002 C - SUCC 5098 230 800 12 - -'
  '03:14:45 20 EAI098 CT003 C - RJCT 3098 230 800 12 FPP050 No_record_found'
)

# Fisher-Yates shuffle keeps the example portable across macOS and Linux.
for ((index = ${#transactions[@]} - 1; index > 0; index--)); do
  swap_index=$((RANDOM % (index + 1)))
  transaction="${transactions[index]}"
  transactions[index]="${transactions[swap_index]}"
  transactions[swap_index]="$transaction"
done

printf '%s\n' "${transactions[@]}"
