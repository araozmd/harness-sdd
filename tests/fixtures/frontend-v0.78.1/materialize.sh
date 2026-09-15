#!/bin/sh
# Reconstruct a frozen prior installed artifact set; never invoke an installer or Git.
set -eu
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "${1:-}" in
  all-five-off) ;;
  all-five-on|all-five-models-on|all-five-pro-on|all-five-flash-on|mixed-off|retired-only-off|gemini-only-off|antigravity-only-off) ;;
  *) echo "usage: $0 <fixture-name> <empty-target-directory>" >&2; exit 1 ;;
esac
[ "$#" -eq 2 ] || { echo "Expected fixture name and target directory" >&2; exit 1; }
target=$2
mkdir -p "$target"
[ -z "$(find "$target" -mindepth 1 -print -quit)" ] || {
  echo "Fixture target must be empty: $target" >&2; exit 1;
}
if [ "$1" = all-five-off ]; then
  cp -R "$fixture_dir/base/." "$target/"
else
  overlay=$fixture_dir/overlays/$1
  parent=$(cat "$overlay/parent.txt")
  sh "$fixture_dir/materialize.sh" "$parent" "$target"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    rm -f "$target/$path"
  done < "$overlay/remove.txt"
  [ ! -d "$overlay/files" ] || cp -R "$overlay/files/." "$target/"
fi
# Only empty fixture-owned directories remain after removal overlays.
find "$target" -depth -mindepth 1 -type d -empty -exec rmdir {} \;
