---
description: |
  Runs the test-parity census on this repository: counts every upstream test,
  maps each to a named Ruby test, and commits
  .reports/TEST_PARITY.md to the ruby branch. Triggered by hand.

on:
  workflow_dispatch:
    inputs:
      upstream_branch:
        description: "Branch holding the original app (blank = the fork parent's default branch)"
        required: false
        type: string

engine: copilot
model: gpt-5

timeout-minutes: 30

permissions: read-all

network:
  allowed: [defaults, github]

tools:
  edit:
  bash: ["*"]
  github:
    toolsets: [repos]

steps:
  - name: Census the test suites
    env:
      GH_TOKEN: ${{ github.token }}
      UPSTREAM_BRANCH: ${{ inputs.upstream_branch }}
    run: |
      set -euo pipefail
      OUT=/tmp/gh-aw/agent/test-parity
      mkdir -p "$OUT"

      # The workspace is the port (ruby branch); the original is a branch of
      # the same repo, fetched alongside.
      cd "$GITHUB_WORKSPACE"

      if [ -z "$UPSTREAM_BRANCH" ]; then
        UPSTREAM_BRANCH=$(gh api "repos/${{ github.repository }}" --jq '.parent.default_branch // empty')
      fi
      if [ -z "$UPSTREAM_BRANCH" ]; then
        echo "Could not determine the upstream branch — pass it explicitly." >&2
        exit 1
      fi

      git fetch --quiet --depth 1 origin "$UPSTREAM_BRANCH:refs/remotes/origin/$UPSTREAM_BRANCH"
      git worktree add --quiet --detach /tmp/gh-aw/agent/trees/upstream "origin/$UPSTREAM_BRANCH"

      {
        echo "repo=${{ github.repository }}"
        echo "upstream_branch=$UPSTREAM_BRANCH"
        echo "upstream_sha=$(git rev-parse --short "origin/$UPSTREAM_BRANCH")"
        echo "port_sha=$(git rev-parse --short HEAD)"
        echo "date=$(date -u +%Y-%m-%d)"
      } > "$OUT/context.env"

      # The skill's census script: one row per test case, per side. The port
      # side is the workspace itself.
      bash ".claude/skills/test-parity/scripts/test-census.sh" \
        /tmp/gh-aw/agent/trees/upstream > "$OUT/upstream-tests.tsv"
      bash ".claude/skills/test-parity/scripts/test-census.sh" \
        "$GITHUB_WORKSPACE" > "$OUT/port-tests.tsv"

      wc -l "$OUT/upstream-tests.tsv" "$OUT/port-tests.tsv"
      cat "$OUT/context.env"

post-steps:
  - name: Commit the report
    env:
      GITHUB_TOKEN: ${{ secrets.GH_AW_PROJECT_GITHUB_TOKEN }}
      GH_TOKEN: ${{ secrets.GH_AW_PROJECT_GITHUB_TOKEN }}
    run: |
      set -euo pipefail
      ok=1
      for f in .reports/TEST_PARITY.md; do
        if [ ! -s "$f" ]; then
          echo "::error::agent did not write $f"
          ok=0
        fi
      done
      [ "$ok" = 1 ] || exit 1
      git config user.name  "github-actions[bot]"
      git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
      git add .reports
      if git diff --cached --quiet; then
        echo "the documents are unchanged — nothing to commit"
        exit 0
      fi
      git commit -m "reports: test parity $(date -u +%F)"
      url="https://x-access-token:${GITHUB_TOKEN}@github.com/${{ github.repository }}.git"
      git pull --rebase --autostash "$url" ruby
      git push "$url" HEAD:ruby

---

# Test parity report

**Read `.claude/skills/test-parity/SKILL.md` first.** It defines what test
parity means, the document you are writing, and the two states every test
lives in. This run is that skill, applied to this repository by machine.

A census has already run. `/tmp/gh-aw/agent/test-parity/` holds:

- `context.env` — `repo`, `upstream_branch`, `upstream_sha`, `port_sha`,
  `date`.
- `upstream-tests.tsv` — every test case in the original, one row per case:
  file, identifier, line.
- `port-tests.tsv` — the same for this workspace (the `ruby` branch).

The original's tree is at `/tmp/gh-aw/agent/trees/upstream`; the port's tree
is the workspace. Read them — the census tells you what exists, not what it
tests.

## The job

Map the census. For **every** row in `upstream-tests.tsv`, find the port test
that pins the same behaviour and name it, or mark it a `gap` with the
behaviour still owed, phrased as something the app does for a person. The
skill is absolute about this: there is no third state, no `n/a`, no "does not
carry over". If a test looks harness-only or duplicated, open both files and
look — the census is a lead, not a verdict.

The port's rows are under the same discipline: a port test no upstream test
names is noted as such (it is not a problem, but it is recorded).

## Write the document

Write `.reports/TEST_PARITY.md` in the workspace — the campaign keeps
generated parity documents in `.reports/`, so where the skill says the branch
root, the path here is `.reports/`. Create the directory first. Use exactly
the shape the skill gives: the header table (upstream and port branch@sha from
`context.env`, the counts, the test command) and one section per suite with
the mapping table. Every count must be the count of rows in your mapping —
never a number you did not derive from the census files.

The commit is automatic — the run fails if the file is missing when you
finish, so write it before you finish. Nothing else may change.

## Rules

- Never edit anything but `.reports/TEST_PARITY.md`.
- If the port has no application code, stop and say so — there is nothing to
  map, and the run should end without the document.
- If upstream has no tests, the document says exactly that — zero owed, zero
  ported — and that is still a fact worth committing.
