#!/usr/bin/env bash
set -euo pipefail

BASE_DIR=".agents/skills"
AGENTS_FILE="AGENTS.md"
START_MARKER="<!-- SKILLS_INDEX_START -->"
END_MARKER="<!-- SKILLS_INDEX_END -->"

if [[ ! -d "$BASE_DIR" ]]; then
  echo "Missing base directory: $BASE_DIR" >&2
  exit 1
fi

if [[ ! -f "$AGENTS_FILE" ]]; then
  echo "Missing $AGENTS_FILE at repo root." >&2
  exit 1
fi

has_start=0
has_end=0
if grep -qF "$START_MARKER" "$AGENTS_FILE"; then
  has_start=1
fi
if grep -qF "$END_MARKER" "$AGENTS_FILE"; then
  has_end=1
fi

if [[ "$has_start" -eq 0 && "$has_end" -eq 0 ]]; then
  tmp="$(mktemp)"
  {
    printf "%s\n" "$START_MARKER"
    printf "%s\n" "$END_MARKER"
    cat "$AGENTS_FILE"
  } > "$tmp"
  mv "$tmp" "$AGENTS_FILE"
elif [[ "$has_start" -eq 0 || "$has_end" -eq 0 ]]; then
  echo "Markers not found as a pair in $AGENTS_FILE." >&2
  echo "Add the following lines as a pair:" >&2
  echo "$START_MARKER" >&2
  echo "$END_MARKER" >&2
  exit 1
fi

index="$(
  find "$BASE_DIR" -type f -name 'SKILL.md' -print \
    | sort \
    | awk -v base="$BASE_DIR" -v prefix="$(basename "$BASE_DIR")" '
function join(arr, start, end,   s, i) {
  s=""
  for (i=start; i<=end; i++) {
    if (s=="") s=arr[i]; else s=s "/" arr[i]
  }
  return s
}
function add_child(parent, child_path,   key) {
  key = parent SUBSEP child_path
  if (!(key in seen)) {
    seen[key]=1
    child_count[parent]++
    children[parent, child_count[parent]] = child_path
  }
}
function build(dir,   i, childpath, childlabel, childcontent, entries, label) {
  entries=""
  for (i=1; i<=child_count[dir]; i++) {
    childpath = children[dir, i]
    childlabel = childpath
    sub(".*/", "", childlabel)
    childcontent = build(childpath)
    if (entries!="") entries = entries ","
    entries = entries childlabel ":{" childcontent "}"
  }
  if (dir in skill) {
    label = dir
    if (label=="") label = base_label
    sub(".*/", "", label)
    if (entries!="") entries = entries ","
    entries = entries label ".md"
  }
  return entries
}
BEGIN {
  base_label = prefix
  count = 0
}
{
  line = $0
  base_prefix = base "/"
  if (index(line, base_prefix) == 1) {
    line = substr(line, length(base_prefix) + 1)
  }
  sub("/SKILL.md$", "", line)
  skill[line] = 1
  count++
  if (line=="") {
    include[""] = 1
    next
  }
  n = split(line, parts, "/")
  for (i=1; i<=n; i++) {
    parent = (i==1 ? "" : join(parts, 1, i-1))
    childpath = join(parts, 1, i)
    include[parent] = 1
    include[childpath] = 1
    add_child(parent, childpath)
  }
}
END {
  if (count==0) {
    print prefix "|"
    exit
  }
  out = build("")
  print prefix "|" out
}
'
)"

index="[Agent Skills Index]|root: ./agents|IMPORTANT: Prefer retrieval-led reasoning over pre-training for any tasks covered by skills.|${index}"

tmp="$(mktemp)"
awk -v start="$START_MARKER" -v end="$END_MARKER" -v repl="$index" '
{
  if ($0==start) { print; print repl; in_block=1; next }
  if ($0==end) { in_block=0; print; next }
  if (!in_block) print
}
' "$AGENTS_FILE" > "$tmp"

mv "$tmp" "$AGENTS_FILE"
printf "Updated %s\n" "$AGENTS_FILE"
