#!/usr/bin/env bash

ORG_NAME=$1
REPO_NAME=$2

repo="$ORG_NAME/$REPO_NAME"
url="repos/$repo/actions/runs"

total_deleted=0

delete_id() {
  local id=$1
  local result=""

  if gh api -X DELETE "$url/$id" --silent; then
    result="✅: Deleted '$id'"
    total_deleted=$((total_deleted + 1))
  else
    result="❌: Failed '$id'"
    echo "An error occurred while deleting ID '$id'. Press Enter to exit."
    echo "Total IDs deleted: $total_deleted"
    read -n 1 -s -r -p ""
    exit 1
  fi

  printf "%s\n" "$result"
}

while true; do
  total_ids=$(gh api "$url" | jq '.workflow_runs | length')

  if [[ $total_ids -eq 0 ]]; then
    echo "No more IDs to delete. Press Enter to exit."
    echo "Total IDs deleted: $total_deleted"
    read -n 1 -s -r -p ""
    break
  fi

  gh api "$url" |
    jq '.workflow_runs[].id' |
    while read -r id; do
      id="${id//$'\r'/}"
      delete_id "$id"
    done

  sleep 10
done
