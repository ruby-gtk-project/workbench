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

safe-outputs:
  create-pull-request:
    title-prefix: "[translation-parity] "
    labels: [translation-parity]
    max: 1
    draft: false
    # The census documents and nothing else. An exclusive allowlist means a PR
    # carrying anything but them is refused rather than reviewed.
    allowed-files: [".reports/TRANSLATION_PARITY.md", ".reports/translation-parity.yaml"]
    if-no-changes: "error"
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

Both files go in the pull request. Regenerating the YAML must never destroy
anything, so any prose you want to keep lives only in the markdown.

## The pull request

Call `create_pull_request` adding exactly `.reports/TRANSLATION_PARITY.md` and
`.reports/translation-parity.yaml`, titled `Translation parity <date>`. The
body is the counts and one sentence on which languages are at risk.

## Rules

- Never edit anything but those two files, both under `.reports/`.
- If the port has no application code, stop and say so — there is nothing to
  census, and no pull request should be opened.
- If the numbers say the port ships a different key set, the report says so.
  "English-only for now" is a gap count, not a state — write it down.
