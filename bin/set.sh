#!/usr/bin/env bash

function usage() {
  echo "Usage: $0 --operation fileA fileB"
  echo "Available operations: --intersection, --left-only, --right-only"
  exit 1
}

if [ "$#" -ne 3 ]; then
  usage
fi

operation="$1"
file1="$2"
file2="$3"

declare -A hashmap1
declare -A hashmap2

while read -r item; do
  hashmap1["$item"]=1
done < "$file1"

while read -r item; do
  hashmap2["$item"]=1
done < "$file2"

case "$operation" in
  --intersection)
    for item in "${!hashmap1[@]}"; do
      if [ "${hashmap2["$item"]}" == "1" ]; then
        echo "$item"
      fi
    done
    ;;
  --left-only)
    for item in "${!hashmap1[@]}"; do
      if [ -z "${hashmap2["$item"]}" ]; then
        echo "$item"
      fi
    done
    ;;
  --right-only)
    for item in "${!hashmap2[@]}"; do
      if [ -z "${hashmap1["$item"]}" ]; then
        echo "$item"
      fi
    done
    ;;
  *)
    usage
    ;;
esac