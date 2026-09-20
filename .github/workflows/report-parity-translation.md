---
description: |
  Runs the translation-parity census on this repository: compares the upstream
  message catalogue against the port's msgid by msgid, and opens a pull
  request writing .reports/TRANSLATION_PARITY.md and
  .reports/translation-parity.yaml. Triggered by hand.

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
  - name: Census the message catalogues
    env:
      GH_TOKEN: ${{ github.token }}
      UPSTREAM_BRANCH: ${{ inputs.upstream_branch }}
    run: |
      set -euo pipefail
      OUT=/tmp/gh-aw/agent/translation-parity
      mkdir -p "$OUT"

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

      # The skill's scripts: catalogue each tree, then compare. The generated
      # YAML is facts a machine recomputes; the markdown is the judgement.
      # The port side is the workspace itself.
      ruby ".claude/skills/translation-parity/scripts/catalogue.rb" \
        /tmp/gh-aw/agent/trees/upstream --role upstream > "$OUT/upstream-catalogue.yaml"
      ruby ".claude/skills/translation-parity/scripts/catalogue.rb" \
        "$GITHUB_WORKSPACE" --role port > "$OUT/port-catalogue.yaml"
      ruby ".claude/skills/translation-parity/scripts/catalogue.rb" --compare \
        "$OUT/upstream-catalogue.yaml" "$OUT/port-catalogue.yaml" \
        > "$OUT/translation-parity.yaml"

      grep -c '' "$OUT/upstream-catalogue.yaml" "$OUT/port-catalogue.yaml"
      cat "$OUT/context.env"

post-steps:
  - name: Commit the report
    env:
      GITHUB_TOKEN: ${{ secrets.GH_AW_PROJECT_GITHUB_TOKEN }}
      GH_TOKEN: ${{ secrets.GH_AW_PROJECT_GITHUB_TOKEN }}
    run: |
      set -euo pipefail
      ok=1
      for f in .reports/TRANSLATION_PARITY.md .reports/translation-parity.yaml; do
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
      git commit -m "reports: translation parity $(date -u +%F)"
      url="https://x-access-token:${GITHUB_TOKEN}@github.com/${{ github.repository }}.git"
      git pull --rebase --autostash "$url" ruby
      git push "$url" HEAD:ruby

---

# Translation parity report

**Read `.claude/skills/translation-parity/SKILL.md` first.** It defines what
translation parity means, the two files this run commits, and why a retyped
label silently discards 78 translations. This run is that skill, applied to
this repository by machine.

A census has already run. `/tmp/gh-aw/agent/translation-parity/` holds:

- `context.env` — `repo`, `upstream_branch`, `upstream_sha`, `port_sha`,
  `date`.
- `upstream-catalogue.yaml` / `port-catalogue.yaml` — the generated catalogue
  document for each tree, sorted by (msgctxt, msgid).
- `translation-parity.yaml` — the generated comparison: counts, states, kinds,
  uses and sites, per the skill's schema.

The original's tree is at `/tmp/gh-aw/agent/trees/upstream`; the port's tree
is the workspace.

## The job

The YAML is the facts; your job is the judgement it cannot hold. Write
`.reports/TRANSLATION_PARITY.md` in the workspace — the campaign keeps
generated parity documents in `.reports/`, so where the skill says the branch
root, the path here is `.reports/`. Create the directory first. Use exactly
the shape the skill gives: the tables render `translation-parity.yaml` (never
maintain them by hand, never disagree with it), and you add the grouping by
upstream source file and one sentence per gap saying what it waits on.

Then copy the generated comparison into the workspace unchanged:

```sh
mkdir -p .reports
cp /tmp/gh-aw/agent/translation-parity/translation-parity.yaml .reports/translation-parity.yaml
```

Both files are committed together. Regenerating the YAML must never destroy
anything, so any prose you want to keep lives only in the markdown.

The commit is automatic — the run fails if either file is missing when you
finish, so write both before you finish. Nothing else may change.

## Rules

- Never edit anything but those two files, both under `.reports/`.
- If the port has no application code, stop and say so — there is nothing to
  census, and the run should end without the documents.
- If the numbers say the port ships a different key set, the report says so.
  "English-only for now" is a gap count, not a state — write it down.
