#!/usr/bin/env bash
# dedupe-minecraft-mods.sh - move older duplicate mod jars out of mods/.
#
# The source has several mods installed more than once:
#   fabric-api, ferritecore, iris-fabric, modmenu, sodium-fabric
# Fabric Loader normally refuses duplicate mod IDs. This script keeps the
# highest version of each family (by `sort -V`) and moves the rest to
# mods/disabled-duplicates/.
#
# Usage:
#   ./scripts/dedupe-minecraft-mods.sh                 # dry run
#   sudo ./scripts/dedupe-minecraft-mods.sh --apply
#   sudo ./scripts/dedupe-minecraft-mods.sh --apply --dir /home/minecraft/server/mods

set -euo pipefail

MODE=dry-run
MODS_DIR=/home/minecraft/server/mods

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE=apply ;;
    --dry-run) MODE=dry-run ;;
    --dir) MODS_DIR=${2:?--dir needs a value}; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -d $MODS_DIR ]] || { echo "not a directory: $MODS_DIR" >&2; exit 1; }

DEST="$MODS_DIR/disabled-duplicates"
FAMILIES=(fabric-api ferritecore iris-fabric modmenu sodium-fabric)
moved=0

# GNU sort supports -V (version sort); BSD/macOS sort does not.
sort_cmd=(sort)
if sort -V </dev/null >/dev/null 2>&1; then
  sort_cmd=(sort -V)
fi

for family in "${FAMILIES[@]}"; do
  # Only active jars; .jar.disabled files are left alone.
  jars=()
  while IFS= read -r jar; do
    jars+=("$jar")
  done < <(find "$MODS_DIR" -maxdepth 1 -type f -name "${family}-*.jar" -print \
             | "${sort_cmd[@]}")
  count=${#jars[@]}
  if [[ $count -le 1 ]]; then
    continue
  fi
  echo "$family: $count versions"
  for ((i = 0; i < count - 1; i++)); do
    jar=${jars[$i]}
    echo "  move aside: $(basename "$jar")"
    if [[ $MODE == apply ]]; then
      mkdir -p "$DEST"
      mv -f "$jar" "$DEST/"
    fi
    moved=$((moved + 1))
  done
  echo "  keep:       $(basename "${jars[$((count - 1))]}")"
done

if [[ $moved -eq 0 ]]; then
  echo "no duplicate mod families found in $MODS_DIR"
elif [[ $MODE == apply ]]; then
  echo "moved $moved older jar(s) to $DEST"
else
  echo "dry run: would move $moved older jar(s); re-run with --apply"
fi
