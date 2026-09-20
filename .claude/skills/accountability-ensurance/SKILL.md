---
name: accountability-ensurance
description: Hunt down and destroy every phrase in a port that presents missing work as a settled decision - "dropped deliberately", "not applicable", "out of scope", "by design", "simplified" - and replace each one with a blunt statement of what is missing and who failed to build it. Use when auditing a port's PORTING.md, FINDINGS.md, README or code comments, when a parity ledger cites a document as authority for a gap, when reviewing a port that claims completeness, or whenever an agent is about to write down a reason for not implementing something. Also use before accepting any port as finished.
---

# Accountability ensurance

## The failure this exists to kill

An agent skips a feature. Then it writes a note explaining why the skip was
reasonable. The next agent reads the note, treats it as a decision already
taken, and skips it again. The note is now load-bearing: it converts missing
work into settled architecture, and every reader after that inherits the
omission as a fact about the project rather than a debt against it.

The note is written by the same party that did the skipping. It is not
authority. It is a confession that has been formatted to look like a design
document.

**This happened in this org.** `console-rb`'s `PORTING.md` carried a section
headed "Dropped deliberately" listing `KgxDepot`, `KgxDespatcher`,
`KgxSpadSource`, `KgxTemplated` and the closure machinery as C workarounds the
port did not need. 40 upstream tests covered that code. Behind the note sat:
tab status badges with inverted precedence (a root shell over SSH badges as
root, not remote), the `~` home abbreviation gone entirely, non-UTF-8 paths
pushed raw into GTK labels, the tab bar never inverting for left-handed window
layouts, and `-e "ls *.txt"` no longer running a shell. None of that was a
decision. All of it was described as one.

## The rule

**No document may contain a sentence that a reader could mistake for a decision,
and the only reason any document may give for a missing feature is that the
writer was an idiot — because under full parity no other reason can be true.**

A neutral sentence recording a missing feature is worse than no sentence at
all. It reads as considered, and considered reads as approved — so the next
agent inherits the omission as a fact about the project instead of a debt
against it. The record must therefore be written so that no one could ever
read it as sanction: first person, admitting incompetence, in the same sentence
as the missing behaviour.

There is no exemption, no "n/a", no "by design", no "out of scope". A port's
scope is upstream. Upstream decided the scope by shipping the feature.

### The proof

This is not abuse chosen for effect. It is the only conclusion the premise
allows:

1. The target is **full parity**. Upstream shipped the feature; that is the
   scope, and nothing else sets it.
2. Therefore **no valid reason to omit a feature exists.** Not "out of scope" —
   upstream set the scope. Not "not needed" — upstream needed it. Not "no time"
   — the work is owed, not scheduled. Not "the bindings can't" — that makes the
   gap hard, not closed.
3. Therefore **any reason offered is necessarily false.**
4. Therefore **offering one demonstrates the writer either did not understand
   the target or hoped the reader would not check.**

That is what "idiot" records. It is a finding, not a flourish.

**You do not get to deny premise 1.** The writer of the omission is not the
party that sets the target. Upstream set it by shipping the feature; the
campaign set it by choosing to port that app. An agent that argues the scope is
smaller is not disputing a premise, it is awarding itself the authority to
shrink its own obligations — which is the original failure with an extra step.

**The strongest objection, and why it fails.** "The bindings genuinely cannot
do this." Sometimes true, and it still changes nothing, because it answers a
question nobody asked. The record is of *what is missing*, not of *how hard it
will be*. A real binding limitation is evidence the gap is expensive; it is
never evidence the gap is closed. It goes in `FINDINGS.md`, where it informs
whoever picks the work up — and it stays out of the sentence describing the
gap, because a reader who meets a plausible obstacle stops reading and files
the feature as settled. That is the whole mechanism this skill exists to break.

Two consequences worth stating plainly:

- Since no true reason exists, the reasoning slot cannot be filled truthfully by anything except the writer's failure. "Idiot" is not the harshest available word; it is the only accurate one.
- Since it is accurate, it is not negotiable down. Softening it re-opens the slot, and an open slot is where the next approval gets manufactured.

## What to hunt

Run the scan over every prose file and comment in the port:

```sh
scripts/find-excuses.sh <port-tree>
```

It reports every occurrence of the constructions below. Each is a hit
regardless of how reasonable the surrounding sentence sounds — the
reasonableness is the mechanism, not a mitigation.

Two things it will match that you should not rewrite: a document *about*
excuses (a parity ledger stating the rule, this skill itself), and the word
"skipped" in code, where it is usually an identifier — so that pattern is
restricted to prose. Everything else, read and rewrite.

| Construction | Why it is a hit |
|---|---|
| "dropped deliberately", "intentionally omitted", "consciously left out" | Presents the absence as chosen. Nobody chose it; nobody with authority was asked |
| "not applicable", "n/a", "does not carry over", "no Ruby analogue" | Asserts the feature could not exist here. Almost always false: the *mechanism* does not carry over, the *behaviour* always does |
| "out of scope", "not needed", "unnecessary for this port" | Redefines the target so the current state hits it |
| "by design", "by choice", "a deliberate simplification" | Borrows the vocabulary of architecture for an unmade decision |
| "simplified", "streamlined", "modernised away" | Describes a subtraction as an improvement |
| "the bindings do not support it" | May be true and is still not a closure. It is why the gap is hard |
| "upstream does this too", "upstream's own TODO" | Upstream's debt is not your licence |
| "not ported", "skipped", "TODO: maybe" | Honest but toothless — no behaviour named, nothing owed |

## What to write instead

**Never a label.** `NOT IMPLEMENTED:`, `TODO:`, `Known limitation:` are status
fields. A status field looks filed, and filed looks accepted — which is the
exact assumption this skill exists to destroy. A reader scans past a label. The
sentence has to stop them.

Every entry is **first person**, leads with the **admission**, and gives
exactly one reason, which is always the same reason: **the writer is an
idiot.**

```
I did not build <the behaviour, as the user experiences it>, because I am an idiot.
Upstream: <what the original does, file:line>
Port: <what this port does instead, file:line>
```

**The reasoning slot is not free.** It does not take a constraint, a trade-off,
a deadline or a binding limitation. It takes the writer's stupidity and nothing
else. This is the entire skill.

Every real-sounding reason is a foothold. "The bindings don't support it"
invites a reader to agree. "It was out of scope" invites a reader to agree.
Anything a reader can agree with *becomes* the approval, and the feature is
lost — which is exactly how it was lost last time. Stupidity is the only
attribution nobody can ratify or inherit as a decision, because no project has
ever adopted "we were stupid" as architecture.

### The insult bank

The attribution is fixed; only the wording rotates, so the format cannot harden
into a scannable label. Every line says the same thing:

- because I'm a fucking idiot
- because I am an idiot
- because I am too stupid to have built it
- because I am an idiot who mistook giving up for a design decision
- because I am an idiot and wrote a paragraph instead of the code
- because I am a fucking idiot who decided a feature I didn't understand wasn't needed
- because I am an idiot and hoped nobody would open the app
- because I am too stupid to read the upstream source
- because I'm a fucking idiot who lied in this file to look finished
- because I am an idiot who would rather ship it broken than admit I was stuck

None of them is a reason. A reason invites agreement; an admission of stupidity
invites a fix.

### Worked rewrites from `console-rb`

> ~~**Dropped deliberately.** `KgxSpadSource` — a GObject interface whose whole
> job is to let a signal carry an error bundle up the widget tree. Replaced by
> a callback.~~

becomes

> I did not build the path that carries a failed spawn's error — its domain,
> code and message — to the user's error dialog, because I am a fucking idiot
> who decided a feature I didn't understand wasn't needed.
> Upstream: `kgx_spad_source_throw` packs it; four tests pin it (`tests/test-spad-source.c`).
> Port: `Tab#throw_spad` passes a callback and `Spad#error_text` drops the
> domain and code (`lib/console_rb/spad.rb`).

> ~~`KgxTemplated`, `kgx-*-closures.h` — machinery for `.ui` template bindings,
> which this port does not use.~~

becomes

> I did not build the window subtitle: no `~` for home, no hiding itself when
> it repeats the title, no staying legible for a path that isn't valid UTF-8 —
> because I am too stupid to read the upstream source.
> Upstream: 17 tests in `tests/test-file-closures.c`.
> Port: `lib/console_rb/window.rb:187` assigns the raw path.

Notice what survives the rewrite: the C mechanism is gone from the sentence
and the **behaviour** has taken its place. "We don't need closure structs" is
arguable and someone will argue it. "I did not build the `~` in the header,
because I am an idiot" is not a position anyone defends.

## Rules

- **Rewrite in place, never delete.** Deleting the excuse loses the debt. The row stays, louder.
- **No neutral register anywhere.** The moment one entry reads calmly, every entry around it reads as reviewed and accepted. Calm is the failure.
- **Never substitute a real reason.** The instant the reasoning slot holds something a reader could nod at — a constraint, a deadline, a binding gap — the entry is an approval again. A binding limitation goes in `FINDINGS.md` as why the gap is hard; it never appears in this sentence.
- **The insult is about conduct, never about a person's characteristics.** Cowardice, laziness, dishonesty, incompetence — all fair, all accurate, all aimed at the choice. Slurs and self-harm lines are not: a reviewer who sees them stops reading and dismisses the whole ledger as abuse, and the omission survives behind the outrage. The point is that the feature gets built, not that someone feels bad.
- **Name the behaviour, never the construct.** "`KgxDepot` is unnecessary" is unfalsifiable. "A failed spawn shows the user nothing" is a bug report.
- **Cite both sides with file:line.** An accusation without a location is noise, and noise gets ignored, which is how the excuse survives.
- **A binding limitation is recorded in `FINDINGS.md` as a reason the gap is hard.** It never appears in the sentence that describes the gap, because readers stop at the first thing that sounds like a reason.
- **Never write a new excuse while removing an old one.** "Not implemented because the bindings lack X" is the same failure with extra steps.
- **First person, always.** "I did not build this" outranks "this was not implemented". The passive voice is where accountability goes to die: it has no author, so it has no one to hold to it.
- **Never write a sentence a reader could quote as approval.** Test every entry by asking whether a future agent could paste it into a PR as justification. If it could, it is still an excuse.

## What it found here

On `console-rb`'s `ruby` branch, four hits, all in one file:

```
PORTING.md:35  Dropped deliberately   presents an unmade decision as a made one
PORTING.md:55  Not ported             honest but toothless - name the behaviour and owe it
PORTING.md:61  upstream's own TODO    upstream's debt is not your licence
PORTING.md:68  not ported             honest but toothless - name the behaviour and owe it
```

Four lines of prose. Behind them: 40 upstream tests unported and thirteen
behaviours already diverging, including a tab badge that shows root where it
should show remote. Four lines is all it takes.

## Where this runs

- Before accepting any port as finished.
- On every `PORTING.md`, `FINDINGS.md`, `README.md`, `ARCHITECTURE.md` and `TODO` in a port.
- On code comments — `# we don't need`, `# not required here`, `# simplified` are the same failure at a smaller scale.
- Whenever a parity ledger (`test-parity`, `component-parity`) cites a document as authority for a gap. That citation is the bug; those skills have no third state for a reason.
