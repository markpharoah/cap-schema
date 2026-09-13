# commercial ● ACCOUNTING

**SESSION RECORD — DATA DAY: KNIT RESOLVED, GRAPH ENRICHED, GATE LIVE**
Commercial Accounting Practice (CAP) · 13 September 2026 (full day) · HANDOVER

---

## Outcome — ALL APPLIED

The 96-row knit-candidates file is RESOLVED and the whole pipeline ran to
completion: **31** (10 merges incl. SCH0009/YAT0007/WHI0001 found by the
sweep; 15 Relative-of retypes + 1 late (row 49 McIntosh); Jacek–Thomas
sibling edge; Stuart Bowey DOD 18/09/2023; dupes swept) → **30** (names
converged both tables: 8+1 engagements, 234+5 edges, incl. the Fastlane
colonoscopy — entity name fixed at source, 6 derived names followed
automatically) → **33** (Relationships tab LIVE on cap_entity form: two
stacked subgrids "This entity is…" / "Others, to this entity…"; menu
label renames failed 400, cosmetic, tab supersedes them) → **32**
(cap_dateofbirth created; **167 DOBs + 3 death dates** — Yates '21,
Munro M '21, Croall '23 — conflicts 0, 10 Merged skipped, notincap 0).

**KINSHIP PLAUSIBILITY GATE: 0 flags on the full graph from stored
dates.** The gate is live furniture — every future import walks it.

Verifications: PHA0001~PHA0002 spouse = 1, LEI0001~BIR0001 = 1,
Schilbach web correct (one Thomas, Jacek sibling, Emily child,
Michele spouse edge confirming derivation doctrine).

Baseline: 309 entities (10 Merged), ~236 active edges, 17 rel types,
167 individuals dated, 3+1 deceased dated.

## Scripts (commit all; git log is truth)

_connect.ps1 (device-code auth, refresh cache in %LOCALAPPDATA%\CAP —
commit script, never cache) · 30-resync-names · 31-knit-ingestion ·
32-enrich-individuals · 33-relationships-tab. knit-actions.csv +
LodgeIT client export stay in data\ (gitignored — real names).

## Rulings (doctrine-grade)

1. **Kinship graph serves care and protection** — family tree,
   birthdays, continuity of care, succession, elder-abuse risk. VERY
   seriously held.
2. **Primary spine + derivation**: Spouse/Parent-Child/Sibling stored;
   cousin/uncle/in-law DERIVE. Relative-of = assertion evidence until
   derivable, then retires. Underivable Relative edge = data gap.
3. **Edges outlast engagements** — kinship views never filter client
   status; deceased stay on the tree WITH dates (that IS the
   protection). Edge-statecode filtering is correct (rejected edges hide).
4. **Derived names resync by script, never hand-edited** — proven live
   by the Fastlane cascade.
5. **CAP graph master; LodgeIT lodgement gateway** — kinship never
   flows back; LodgeIT gets duplicate fixes + identity scalars only.
6. Kill = merge + Merged status + audit note, never delete. False
   edges deactivate (rejection is evidence). DOD = evidence not label,
   drives comms suppression. Kerri is Kerri.
7. **Scripts travel by zip** (browser/OS blocks bare .ps1).

## Craft lessons (five, hard-won today)

1. FormXml ids are schema-validated GUIDs — no vanity markers.
2. PublishAllXml demands Content-Type json + "{}" body (inconsistently
   enforced — fix everywhere anyway).
3. **Preview paths must run against the world as-is, not the world
   apply will make** (dynamic $select for not-yet-created columns).
4. Date parsing: InvariantCulture always — '/' in a format string
   means "the culture's separator", not slash.
5. Metadata creation is eventually consistent — first write after a
   column CREATE may need a beat/retry (rerun-safe design absorbed it).
Plus: Harborne is codeless by design — every clientcode path guards null.

## Chase list (DOB gaps, 23 active individuals — fold into LodgeIT
Needs register)

Priority: AXF0001 Axford Peter (AA engagement). Squint: YAT0006 Yates,
Mark — possible THIRD Mark Yates vs YAT0003/0007 merge. Rest: De
Castella Damien, Wozniak ×2, Wells B, Ruberto (also no email — blocks
signing packs), Fraser, Gaelia, De Judicibus, Leslie J, Sanhueza
Tapia, Underwood, Collins M, Bowey Sam, Taylor M, Van Den Brand A,
Baker M, Lewit, Lewis B, Perez, Ryan B. Plus register standing items:
LodgeIT-side merges GATE any relationship reseed; 15 entities missing
TFN; Former ≠ archive (deceased may owe date-of-death returns).

## Carried / next block

- **Fresh-coffee argument (top of queue): Family Tree page +
  PROTECTION PANEL** — walk the graph, render derived relations;
  cap_roletype grows Attorney/EPOA · Guardian of · Executor of ·
  Authorised contact; authority + kinship isolation + ledger flow.
- Service Tier field + triage pass (the 40 Tax Only decisions).
- Derivation check script (retire derivable Relative-of edges).
- Harborne job view (carried since Day 1) · re-arm required levels ·
  job-form derivation argument · contact model design argument
  (addresses/emails deliberately deferred) · own Entra app
  registration · ATO bridge staged (a: automate CAP→LodgeIT now;
  b: DSP read services when portal earns; c: AS maybe; ITR stays
  LodgeIT) · menu label rename retry if ever bothered (tab makes it moot).

---

*Commercial Accounting · session record · 96 rows of spouse fiction in;
a typed, dated, deduplicated, plausibility-checked family graph out —
with a tab to show for it. The graph knows the families. Next it learns
to protect them.*
