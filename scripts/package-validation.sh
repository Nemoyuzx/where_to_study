#!/usr/bin/env bash

path_contains_fixed_text() {
  local needle="$1"
  local search_path="$2"

  LC_ALL=C command grep -a -F -R -- "$needle" "$search_path" >/dev/null
}

stream_contains_fixed_text() {
  local needle="$1"

  LC_ALL=C command grep -a -F -- "$needle" >/dev/null
}
