#!/usr/bin/env bash

validate_release_label() {
  local release_label="$1"

  if [[ ! "$release_label" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$ ]]; then
    echo "Release label contains unsupported characters: $release_label" >&2
    return 1
  fi
}

path_contains_fixed_text() {
  local needle="$1"
  local search_path="$2"

  LC_ALL=C command grep -a -F -R -- "$needle" "$search_path" >/dev/null
}

stream_contains_fixed_text() {
  local needle="$1"

  LC_ALL=C command grep -a -F -- "$needle" >/dev/null
}
