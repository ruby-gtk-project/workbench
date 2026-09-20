#!/usr/bin/env bash
# Census the test cases in a source tree, one row per test.
#
# Output: <file>\t<identifier>\t<line>
#
# Counts test *cases*, not test files or assertions, because a case is what an
# upstream author decided was one thing worth pinning. Matching is by the
# registration syntax of each framework a GNOME app might use, so it is a lead
# and not a verdict: read the files.
#
# Usage: test-census.sh <tree> [more-trees...]
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <tree>..." >&2; exit 2; }

# A test file is one whose path says so, OR one that registers tests inside a
# source directory - Rust puts `#[cfg(test)] mod tests` in src/*.rs, and a Vala
# app may register cases outside test/. Selecting on path alone loses those and
# also picks up innocents like `latest.rs`.
#
# Test *harness* files are excluded: a driver or helper holds usage examples in
# its comments, which would otherwise be censused as cases.
testfiles() {
  find "$1" -type f \
    -not -path '*/.git/*' -not -path '*/_build/*' -not -path '*/build/*' \
    -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    -not -path '*/.claude/skills/*' -not -path '*/target/debug/*' \
    \( -name '*.vala' -o -name '*.c' -o -name '*.py' -o -name '*.js' \
       -o -name '*.ts' -o -name '*.rs' -o -name '*.rb' -o -name '*.cpp' \) 2>/dev/null \
  | while IFS= read -r f; do
      base=${f##*/}
      case "$base" in
        # An explicit test suffix always wins over the harness blocklist -
        # `helpers.test.js` is a test file, `helpers.js` is a harness.
        *.test.*|*_test.*|*-test.*|test_*|test-*|*.spec.*|*_spec.*) ;;
        *driver*|*helper*|*support*|*fixture*|*conftest*) continue ;;
      esac
      case "$f" in
        */test/*|*/tests/*|*/spec/*|*/specs/*|*/Tests/*|*/testing/*) printf '%s\n' "$f"; continue ;;
        */test_*|*/*_test.*|*/*_tests.*|*/*-test.*|*/test-*|*/*_spec.*|*/spec_*) printf '%s\n' "$f"; continue ;;
      esac
      # Content fallback for tests living beside the code they cover.
      grep -qE '#\[([A-Za-z0-9_]+::)*(test|test_case)\]|#\[cfg\(test\)\]|(g_)?[Tt]est(\.|_)add_func|^[[:space:]]*(import|from) +(unittest|pytest)' \
        "$f" 2>/dev/null && printf '%s\n' "$f"
    done
}

# emit <display-path> <read-path> <grep-ere> <sed-to-identifier>
emit() {
  grep -nEo "$3" "$2" 2>/dev/null | while IFS=: read -r line match; do
    id=$(printf '%s' "$match" | sed -E "$4")
    [ -n "$id" ] && printf '%s\t%s\t%s\n' "$1" "$id" "$line"
  done
}

for tree in "$@"; do
  TREE=${tree%/}
  testfiles "$TREE" | while IFS= read -r f; do
    rel=${f#"$TREE"/}
    case "$f" in
      # GLib test framework: Test.add_func ("/suite/case", ...) / g_test_add_func
      *.vala|*.c|*.cpp)
        # g_test_add_func / g_test_add / g_test_add_data_func, AND any
        # project-local wrapper around them - kgx registers 20 of its cases
        # through `fixtured_test ("/kgx/settings/...", ...)`. A GLib test path
        # always begins with '/', which makes the wrapper form matchable
        # without knowing its name.
        emit "$rel" "$f" '[A-Za-z_][A-Za-z_0-9]* *\( *"/[^"]+"' 's/^[^"]*"//; s/"$//' ;;

      # unittest methods and pytest functions. Comment lines are blanked first
      # (line numbering preserved) so a usage example in a docstring-adjacent
      # comment is not censused as a case.
      *.py)
        tmp=$(mktemp); sed 's/^[[:space:]]*#.*//' "$f" > "$tmp"
        emit "$rel" "$tmp" '^[[:space:]]*(async +)?def +test[A-Za-z0-9_]*' 's/.*def +//'
        rm -f "$tmp" ;;

      # Jasmine/Mocha it(...) - GJS apps and any JS/TS port
      *.js|*.ts)
        emit "$rel" "$f" "\\b(it|test)\\( *['\"][^'\"]+['\"]" "s/.*['\"]([^'\"]+)['\"].*/\\1/" ;;

      # Rust: the attribute is the registration, the following fn name is the
      # identifier. Stateful rather than a fixed context window, so that
      # `#[test] fn x()` on one line, any number of intervening attributes
      # (#[ignore], #[should_panic], #[cfg(..)]), and flavoured attributes
      # (#[tokio::test], #[gtk::test]) all work - and so that a nested fn
      # inside a test body is not counted as a second test.
      *.rs)
        awk '{
          if ($0 ~ /^[[:space:]]*#\[([A-Za-z0-9_]+::)*(test|test_case)\]/) t = 1
          if (t && match($0, /fn[[:space:]]+[A-Za-z0-9_]+/)) {
            id = substr($0, RSTART, RLENGTH); sub(/fn[[:space:]]+/, "", id)
            print FILENAME "\t" id "\t" NR
            t = 0
          }
        }' "$f" | sed "s|^$TREE/||" ;;

      # Ruby: minitest def test_*, spec-style it "...", and the house style
      # used across this fleet's ports - a named check(...) block, or
      # d.check(...) under the ruby-gtk-testing driver. A `check` is the named
      # assertion unit, which is what a GLib Test.add_func case is too; a
      # driver `step` names the case in some ports, so both are collected -
      # the skill says how to pick which one is this suite's unit.
      *.rb)
        tmp=$(mktemp); sed 's/^[[:space:]]*#.*//' "$f" > "$tmp"
        emit "$rel" "$tmp" '^[[:space:]]*def +test_[A-Za-z0-9_?!]*' 's/.*def +//'
        emit "$rel" "$tmp" "^[[:space:]]*it +['\"][^'\"]+['\"]" "s/.*['\"]([^'\"]+)['\"].*/\\1/"
        # check(...) / step(...), including the very common form that breaks
        # the name onto the next line. Tracked like the C and Rust scanners.
        awk -v F="$rel" '
          BEGIN { Q = sprintf("%c", 39) }
          {
            if (!open && match($0, /(^|[^A-Za-z_.])(d\.)?(check|step)[[:space:]]*\(/)) {
              open = 1; rest = substr($0, RSTART + RLENGTH)
            } else if (open) rest = $0
            if (open) {
              if (match(rest, "[\"" Q "][^\"" Q "]+[\"" Q "]")) {
                print F "\t" substr(rest, RSTART + 1, RLENGTH - 2) "\t" NR
                open = 0
              } else if (rest ~ /\)/) open = 0
            }
          }' "$tmp"
        rm -f "$tmp" ;;
    esac
  done
done | sort -u
:
