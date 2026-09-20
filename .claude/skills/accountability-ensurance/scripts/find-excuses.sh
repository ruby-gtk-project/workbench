#!/usr/bin/env bash
# Find every phrase that presents missing work as a settled decision.
#
# Output: <file>:<line>:<matched phrase>:<verdict>
#
# A sentence that reads as a reasonable justification is the exact failure mode
# - the reasonableness is the mechanism by which the omission survives review -
# so the strong patterns are deliberately not softened.
#
# Two weak patterns ("skipped", "we don't need") are prose-only: in code they
# match variable names, rubocop directives and test-runner calls, which is pure
# noise. Everywhere else, read every hit.
#
# Usage: find-excuses.sh <tree> [--quiet]
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $(basename "$0") <tree> [--quiet]" >&2; exit 2; }
TREE=${1%/}
QUIET=${2:-}

files() {
  find "$TREE" -type f \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/_build/*' -not -path '*/build/*' -not -path '*/.bundle/*' \
    -not -path '*/po/*' -not -path '*/.claude/skills/*' \
    \( -name '*.md' -o -name '*.rb' -o -name '*.txt' -o -name 'TODO*' \
       -o -name '*.vala' -o -name '*.c' -o -name '*.h' -o -name '*.py' \
       -o -name '*.js' -o -name '*.rs' \) 2>/dev/null
}

# phrase-regex <TAB> verdict
PATTERNS=$(cat <<'PAT'
(dropped|omitted|left out|removed) (it )?(deliberately|intentionally|on purpose|by choice)	presents an unmade decision as a made one
deliberately (dropped|omitted|simplified|left out|skipped)	presents an unmade decision as a made one
intentionally (omitted|dropped|unimplemented|left)	presents an unmade decision as a made one
not applicable|\bn/a\b|does not (carry over|apply here)	asserts the behaviour cannot exist here - the mechanism does not carry over, the behaviour always does
no (ruby|direct) (analogue|equivalent|counterpart)	the analogue is the BEHAVIOUR, which always has one
out of scope|not in scope|beyond (the )?scope	redefines the target so the current state hits it
(not|isn.t|aren.t) (needed|necessary|required)( for this port| here)?	asserts a need was evaluated - upstream already evaluated it by shipping it
by design|by choice|design decision	borrows architectural vocabulary for an unmade decision
deliberate simplification|simplified (away|out)|streamlined away|modernised away	describes a subtraction as an improvement
(the )?bindings? (do|does)(n.t| not) support	true or not, this is why the gap is HARD - it does not close it
upstream (does|has) this too|upstream.s own todo	upstream's debt is not your licence
\bwontfix\b|won.t (fix|implement|port)	a refusal with no behaviour named
(not ported|unported)\b	honest but toothless - name the behaviour and owe it
(^|[-*][[:space:]]*)(NOT IMPLEMENTED|TODO|FIXME|Known limitation|Caveat):	a status field - reads as filed, and filed reads as approved
(this|it) (was|is) not (implemented|built|ported)	passive voice - no author, so no one to hold to it
PAT
)

# Prose only: in source these match identifiers and test-runner calls.
PROSE_PATTERNS=$(cat <<'PAT'
\bskipped\b|\bskipping\b	honest but toothless - name the behaviour and owe it
we (don.t|do not) (need|use|require)	first-person confidence about someone else's requirement
PAT
)

hits=0
while IFS= read -r f; do
  case "$f" in
    *.md|*TODO*|*.txt) pats="$PATTERNS
$PROSE_PATTERNS" ;;
    *)                 pats="$PATTERNS" ;;
  esac
  while IFS='	' read -r re verdict; do
    [ -n "$re" ] || continue
    while IFS=: read -r ln text; do
      [ -n "$ln" ] || continue
      phrase=$(printf '%s' "$text" | grep -ioE "$re" | head -1)
      printf '%s:%s:%s:%s\n' "${f#"$TREE"/}" "$ln" "$phrase" "$verdict"
      hits=$((hits + 1))
    done < <(grep -inE "$re" "$f" 2>/dev/null | cut -d: -f1,2- | sed 's/:/:/')
  done <<< "$pats"
done < <(files)

if [ "$QUIET" != "--quiet" ]; then
  echo
  echo "Each hit is rewritten, never deleted, to:"
  echo
  echo "  I did not build <the behaviour, as the user experiences it>, because I am an idiot."
  echo "  Upstream: <what the original does, file:line>"
  echo "  Port: <what this port does instead, file:line>"
  echo
  echo "First person. Admission first. No label - a label reads as filed, and"
  echo "filed reads as approved."
  echo
  echo "The reasoning slot takes the writer's stupidity and nothing else. Under"
  echo "full parity no valid reason to omit exists, so any reason offered is"
  echo "false, and offering one is the finding. Rotate the wording, never the"
  echo "attribution."
fi
