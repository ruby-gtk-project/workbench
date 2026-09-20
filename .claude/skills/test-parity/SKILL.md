---
name: test-parity
description: Establish and prove test parity between a GNOME app and its Ruby GTK4 port - census the upstream suite test by test, map each one to a named Ruby test, and show the counts match exactly. Use when porting an app to Ruby GTK, when asked whether the tests are ported / how many tests are missing / "do we have test parity", when writing the port's first tests, when reviewing a port PR that adds or changes tests, or before calling any port finished. Also use when a port's suite looks healthy but was never checked against what upstream actually tested.
---

# Test parity

## What test parity means

**A port has test parity when its suite contains exactly one test for every
test in the upstream suite, and nothing is left unaccounted for in either
direction.**

Three claims, all of which must hold:

1. **The counts are equal.** Upstream has N tests; the port has N tests. Not
   "about N", not "N minus the ones that don't apply". N.
2. **The mapping is a bijection.** Every upstream test names exactly one port
   test, and every port test is named by exactly one upstream test. No upstream
   test maps to two port tests; no port test covers three upstream tests at
   once.
3. **Each pair tests the same thing.** The port's test asserts the same
   property, over the same inputs, for the same reason. A test that shares a
   name and asserts something easier is a parity failure wearing a disguise.

Parity is a property of the *census*, not of the number at the bottom of the
test runner. A suite of 34 Ruby tests that were written from scratch has no
parity with a suite of 34 Vala tests; it has a coincidence. Parity exists only
once each pair is written down.

### Why it is defined this way

The upstream suite is the only surviving record of what the original authors
found worth pinning down: the bug that came back, the edge case in the date
parser, the null dereference in #2652. A port that drops a test drops that
knowledge silently and gets a green suite for it. Counting is the cheapest
check that catches it, and the name-by-name census is what makes the count
mean something.

### Nothing authorises a skip

There are exactly two states: **`ported`** (a named port test pins the whole
property) and **`gap`** (anything else). There is no third state, and no
document, decision or rationale can create one.

In particular:

- **A note in the port's own `PORTING.md` is not authority.** It is written by the port, about the port. Citing it to excuse the port's own missing work is circular — the same hand that skipped the implementation wrote the line permitting the skip. Read `PORTING.md` to find out *where* things live; never to find out what you are allowed to leave out.
- **"C-specific plumbing" is not an exemption.** An upstream test of a closure struct or a GObject interface exists because some behaviour depended on it. Ruby does not need the struct; the user still needs the behaviour. The row becomes a gap whose Purpose states the *behaviour*, so someone can write the Ruby test that pins it.
- **A partially-ported test is a gap.** If upstream pins seven cases and the port pins one, that property does not have parity. Half a test is not half a pass.
- **There is no `n/a`, no `not applicable`, no `does not carry over`, no `skipped`.** Every one of those is a gap wearing a justification.

A test may be written differently in Ruby than in C — a different framework, a
different formulation, GC instead of an explicit refcount check. That is fine
and it is still `ported`, because a real named test pins the property. The
distinction that matters is not *how* the port tests it but *whether* it does.

Each gap carries one more thing: the **behaviour still owed**, phrased as
something the app does for a person. "A failed spawn shows the user an error"
is a behaviour. "`KgxDepot` exists" is not.

## How to establish it

### Step 1 — Census the upstream suite

Work from the upstream branch of the fork — the port's `ruby` branch and the
original share one repo. The upstream branch is the fork parent's default
branch, which is not always `main`:

```sh
REPO=$(basename -s .git "$(git remote get-url origin)")   # e.g. binary-rb, not binary
UP=$(gh api "repos/ruby-gtk-project/$REPO" --jq '.parent.default_branch')
```

`ruby` is an **orphan** branch — it shares no history with upstream, so
`git merge-base` returns nothing and there is no commit to derive. Record the
upstream sha in the ledger header the first time, and compare against that
recorded sha afterwards; otherwise every upstream commit silently moves the
target the port is being measured against.

```sh
scripts/test-census.sh <upstream-tree> > upstream-tests.tsv
```

The script finds test cases across the frameworks GNOME apps use — GLib
`Test.add_func` (Vala/C), Python `unittest` / `pytest`, GJS Jasmine `it(...)`,
Rust `#[test]` and its flavours (`#[tokio::test]`, `#[gtk::test]`) including
inline `#[cfg(test)] mod tests` in `src/`, Ruby `test_*` / `it` / the house
`check("...")`. It emits one row per test:
`file<TAB>identifier<TAB>line`.

**Decide which call is this suite's assertion unit before you trust the count.**
`check`, `step`, `assert` and `it` are conventions, not contracts. The script
collects both `check(...)` and `step(...)` from a Ruby driver, which
double-counts a suite that uses them as grouping plus assertion, and undercounts
one where `check` is only ever called from inside a helper. Open the driver and
find the call that increments the pass counter:

```sh
grep -nE 'def (check|step)|failures? *\+?=' <port>/test/*.rb
```

console-rb names all 71 of its cases on `step` and calls `check` once, from a
rescue block — censusing on `check` there gives 1. A file whose row count is far
below its visible assertion count has been matched at the wrong call site.

Two things it deliberately excludes, so that you do not have to decide:
**comment lines** (a driver's usage example is not a test case) and **harness
files** matching `*driver*`, `*helper*`, `*support*`, `*fixture*`, `*conftest*`.
If a real test lives in a file with one of those names, it is invisible —
check.

**Read the script's output as a lead, not a verdict.** Then open every test
file and write down, for each test, what it actually asserts. The identifier is
rarely enough: `/cli/task_validator/date_format_valid` does not tell you which
formats, or that the empty string is deliberately excluded. That purpose is the
thing you are porting; the name is just its handle.

**Cross-check the census against the build file's test list** — the `tests`
array in `tests/meson.build`, `[[test]]` in `Cargo.toml`, `testpaths` in
`pytest.ini`, the `test` task in a Rakefile. A declared test binary with zero
census rows means the script missed that file's registration macro, not that
the binary has no tests:

```sh
grep -oE "'[a-z0-9-]+'" up/tests/meson.build | tr -d "'" | sort -u   # declared
cut -f1 upstream-tests.tsv | sort -u                                  # censused
```

kgx registers 127 cases three different ways — `g_test_add_func`,
`g_test_add_data_func` and a fixture macro wrapping `g_test_add` whose path
argument is a *variable*. The last of those cannot be matched by any regex; the
build-file cross-check is the only thing that finds it, and those cases are
censused by hand from the file.

A test whose purpose you cannot state in a sentence has not been censused.
Do not move on.

**Tests generated in a loop** get one ledger row, not N. `(2..6).each { |n|
check("on page #{n}") }` is five assertions at runtime and one row here, and
its identifier cannot be matched back by name because it is interpolated.
Mirror the *repeater* rule from `component-identification`: one row, the
identifier written with the interpolation intact (`on page #{page_nr}`), and
the loop's range stated in the Purpose cell. Step 4's "exists by that name"
check is then read against the interpolated form.

The same rule covers every table-driven form: `@pytest.mark.parametrize`,
`unittest`'s `subTest`, a Vala loop over fixtures, a Rust `#[test_case]`. One
row, the parameter set in the Purpose cell.

**When an identifier repeats**, the name alone is not a key — two `test_one`s
in two classes in one file, or six `check('a dialog is showing')` calls in one
driver, are distinct cases. The ledger cell is then `file#identifier@line`, and
the census row's third column is part of the key. Check for these before
writing the ledger:

```sh
cut -f2 port-tests.tsv | sort | uniq -d
```

### Step 2 — Write the ledger

`TEST_PARITY.md` at the root of the port's `ruby` branch. It is the contract,
and like `PORTING.md` it is the source of truth — not a summary of one.

```markdown
# Test parity — <app>

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Upstream tests | 34 |
| Ported | 34 |
| Gaps | 0 |
| Test command | `rake test` |

## Suite: cli/argument_parser (15 tests)

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `/cli/argument_parser/add_minimal` | `add` with only `--content` fills the rest from defaults | `test/cli/test_argument_parser.rb#test_add_minimal` | ported |
| 2 | `/cli/argument_parser/unknown_option` | an unrecognised flag is an error, not a silent ignore | `test/cli/test_argument_parser.rb#test_unknown_option` | ported |
| 3 | `/cli/argument_parser/invalid_pin_value` | `--pin` rejects anything but true/false | — | **gap** |

Gaps carry a sixth column, `Behaviour still owed`, naming what a Ruby test must
pin — in terms of what the app does for a person.
```

One row per upstream test, forever. Rows are never deleted — a ported test that
gets rewritten keeps its row and changes its `Port test` cell. The state is
`ported` or `gap`. There is no third state.

### Step 3 — Port the gaps

Take gaps in ledger order. For each: read the upstream test, write the Ruby
test that asserts the same property, run it, tick the row.

Name the Ruby test after the upstream one, mechanically, so the mapping is
visible without the ledger:

| Upstream | Ruby |
|---|---|
| `/cli/argument_parser/add_minimal` | `test/cli/test_argument_parser.rb`, `test_add_minimal` |
| `/item-sorting/breaks-a-priority-tie-by-date-added` | `test/core/test_item_sorting.rb`, `test_breaks_a_priority_tie_by_date_added` |

Keep the upstream suite's file structure too. If upstream splits the CLI tests
across three files, the port splits them across three files. A single
`test/all_test.rb` holding 34 tests passes the count and loses the shape.

The port's tests are plain Ruby, run under whatever target the port declares —
`rake test`, `make test`, `meson test`. Check which exists (`ls Rakefile
Makefile meson.build`) and **name the command you ran in the ledger header**
— see the `ruby-gtk-testing` skill for the non-widget checks and the
headless driver. Nothing here asks for a new framework.

### Step 4 — Prove it

```sh
scripts/test-census.sh <port-tree> > port-tests.tsv
wc -l upstream-tests.tsv port-tests.tsv
```

Parity is proven when all four hold:

- the two counts are equal;
- every ledger row has a non-empty `Port test`;
- every test named in the ledger exists, by that name, in the port tree;
- the port's suite passes under its own test target (`rake test` / `make test`).

Report the numbers, not an adjective. "34/34, suite green" is a claim someone
can re-run. "Good test coverage" is not.

### When upstream has no tests

Common, and not a licence to skip the skill. GNOME Tour's upstream has zero.
The ledger degenerates to a header and a statement — do not build empty tables,
and do not pad the `## Extra` section into a ledger it is not:

```markdown
# Test parity — gnome-tour

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |

Upstream has no test suite (verified: the census is empty, and no `def test_*`,
`unittest`, `pytest`, `#[test]`, `#[cfg(test)]`, `Test.add_func`, `it(...)`,
no `test/` or `tests/` directory and no test target in the build files).
Parity is 0/0 and is met trivially. **The port therefore inherits no
safety net** — every check below was written for the port and pins nothing
upstream considered worth pinning.

## Extra

- `test/drive_tour.rb` — 71 checks driving the carousel, the page transitions and the skip action.
- `test/test_load.rb` — 29 checks on the page model and the resource bundle.
```

`## Extra` is a plain list, one line per file with a count and a sentence. Extra
rows need no Purpose cell and no bijection — they are outside the count by
definition. Say the "no safety net" line explicitly; it is the finding, and
leaving it implied is how a 0/0 report gets read as a pass.

## How this ledger relates to the others

A fork carries up to four documents, and they are not interchangeable:

| File | Source of truth for |
|---|---|
| `PORTING.md` | **what was ported** — the enumerated units, their state, the cursor |
| `TEST_PARITY.md` | **what was tested** — this skill's census and bijection |
| `COMPONENT_PARITY.md` | **what was built** — the four-axis component comparison |
| `FINDINGS.md` | **binding defects** — ruby-gnome bugs and workarounds found en route |

`PORTING.md` describes *where things went*, and that makes it useful for
navigation — its architecture table is the file mapping. It does **not** decide
what the port owes. Upstream decides that, by having written the test.

Cite `FINDINGS.md` from a gap row when a binding defect is *why* that gap is
hard to close — never copy its content into this ledger, and never let it
convert the gap into a pass.

## Worked example — planify-rb

Upstream `main` has four test files and **34** test cases: 26 under `cli`
(`test/cli/test-argument-parser.vala`, `test-task-validator.vala`,
`test-priority-conversion.vala`), 8 under `core`
(`test/core/test-item-sorting.vala`), 1 CalDAV integration test.

The `ruby` branch has `test/test_load.rb`, `test/test_sync.rb` and
`test/drive_main.rb`, and the census counts **173** named `check(...)` cases in
them. They were written for the port; not one of them was written from an
upstream test, and none of the 34 has a counterpart.

So planify-rb's parity ledger opens at **0/34, 34 gaps** — while the port's
suite is five times the size of upstream's. This is the case the skill exists
for. A bigger number is not parity, and a port whose suite is green and
substantial can still have inherited none of the knowledge upstream wrote down.
Those 173 checks are not parity work; they are extra, they stay extra, and they
are listed under `## Extra`. Parity is a floor the port owes upstream, never a
ceiling on what the port may test.

## Rules

- Never lower a test to make it pass. A failing ported test is a port bug found
  — that is the test doing its job.
- Never merge two upstream tests into one Ruby test to save typing. The count
  is the check; collapsing rows disables it.
- Never let a row leave the ledger without either a named port test or a stated
  behaviour still owed. A row with neither is how a skip gets laundered.
- Extra Ruby tests with no upstream counterpart are welcome and are listed in
  an `## Extra` section below the tables, outside the count.
- A test that cannot be made to pass is a gap plus an issue, not a comment-out.
- A binding limitation is a reason a gap is *hard*, never a reason it is closed.
  Record it in `FINDINGS.md` and leave the row a gap.
- If the upstream app has no tests at all, say exactly that: parity is 0/0, it
  is met trivially, and it means the port has no inherited safety net — which
  belongs in the report, not left as an implication.
