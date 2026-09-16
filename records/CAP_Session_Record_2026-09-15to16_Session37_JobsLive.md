# commercial ● ACCOUNTING

**SESSION RECORD — SESSION 37: JOBS AT BOOK SCALE, THE FLIGHT DECK EXISTS**
Commercial Accounting Practice (CAP) · 14–16 September 2026 · HANDOVER TO SESSION 38

---

## Outcome — ALL APPLIED, ALL COMMITTED (through 7adfcd8 on 16/9; views built 17/9)

**202 jobs stamped, 0 skipped, 0 flagged.** Every open obligation the
practice carries now exists as a cap_job with template tasks, courts,
weights, milestones and a due date, keyed to its entity and engagement,
born from a dated LodgeIT snapshot and reproducible from git. Four days
earlier the count was one job named Harborne.

**Session redirected before it opened.** The 14/9 handover proposed
"the panel grows hands" (protection-review jobs). Mark's stated pain was
job tracking on ~$20k of doable work; the fresh LodgeIT export was the
feed. Ruling: lodgement-driven jobs first, panel-hands rides behind.

**Schema (37-billing-rhythm.ps1).** cap_engagement gains
`cap_billingrhythm` (Local choice 764820000 Annual on completion /
764820001 Monthly fixed / 764820002 Quarterly fixed; default Annual) and
`cap_asscope` (Boolean "AS scope (CA does BAS/IAS)", default Yes).
Data pass: EIV ELE0001, Celmec CEL0001 monthly; Marbec TRU0001 (family
trust) quarterly; LEW0003 Lewis William and LEW0005 W E Lewis &
Associates AS scope = No. IEI and MultiCube deferred (see 38).

**Templates (38-templates-seed.ps1).** Beside "Annual Accounting -
Year End": **Tax Only Return** (4 tasks, 10/50/25/15, milestone Return
signed, 100% anchor on lodge), **Activity Statement** (3 tasks,
30/50/20), **Amendment** (2 tasks, 70/30). Nav property resolved from
metadata: `cap_JobTemplateId`.

**Proposer (39-propose-jobs.ps1).** Reads newest
`data\lodgeit-allstatus-YYYY-MM-DD.xlsx` (naming convention ratified;
ImportExcel module), pulls the AS-scope suppression list LIVE from
Dataverse, classifies every New/Draft form under the ratified grain,
writes `job-proposals.csv` (Accept column) and
`stewardship-register.csv`. First run: **216 proposals / 22 stewardship
rows** — reconciled to the Python v2 model (212) exactly: the 4 extra
were Bowey Samuel ITR 2024/25 and Schilbach SMSFAR 2022/23, which the ATO
shows lodged but LodgeIT still shows open (Part 0 hygiene not yet done).
The proposer reports its source truthfully; the mirror was stale.

**Applier (40-apply-jobs.ps1).** Plan mode default (probes cap_job
shape, resolves nav props `cap_JobId` / cap_entity / cap_engagement /
cap_jobtemplate, prints every job it would stamp); `-Apply` stamps.
Idempotent on job name `CODE · Period`. Ticks applied by rule: everything
except the 4 ATO-lodged rows and arrears for RYA0002 Holly Ryan (5),
HOL0002 her fund (4), GUR0001 Gurney (1) — held pending keep-or-release.
**202 of 216 ticked; 202 stamped.** Due dates landed on final-stage
tasks (cap_job had no cap_duedate — see 38).

**Templates named by alias.** Proposer shorthand "Year End" / "Year End
(SMSF)" → real template "Annual Accounting - Year End" (SMSF rides Year
End until its own template exists).

**First live quarterly sweep — before it was scheduled.** Fresh ATO
reports (15/9) diffed against 31/8: all 12 stale-snapshot ITR rows
cleared (Pelham ×3, both Clapps, John & Barbara, TeamFHS, Woodward,
Wynne, Watson, Dylan Jeffery); Doravale and Pharoah Investments UT 2026
went Return Not Necessary. AS population 48→100 rows: 37 of 45 new names
are the September-quarter cycle issuing for known clients; **8 are
genuine — ATO obligation with no LodgeIT form:** Orchestrate Coaching
(R, PAYGI new, 28/10), Van Den Brand Super Fund (R, PAYGI new, 28/10),
Grey Weima Holdings (F, 28/10), Shellbie Park (X, 28/10), Brylie Hammet
(A, GST+PAYGI, 25/11), Audacious Ergonomics (F, 25/11), Royal
partnership (D, 25/11), Square Corner Unit Trust (D, 25/11). The two
Form-R rows are the predicted species: fresh PAYG instalment entrants
with variation windows closing 28 October.

**Deviations register (ATO vs LodgeIT, genuine class).** Peter Axford
(not in LodgeIT; last lodged 2018 — up to 8 years), Marc Salzmann (last
lodged 2015), Kaer Morhen Family Trust (never), Mick Hammett Super Fund
(2024–26), JR & BJ Pharoah Super Fund (2023–26), Coolabah (ATO: never
lodged income tax; LodgeIT forms 2017–2026; TFN 456670234 not recorded
in LodgeIT). TFN gaps in LodgeIT: Coolabah, Audacious, Royal
partnership, Van Den Brand fund. Housekeeping: 4 mark-as-lodged + 4
TFNs (`lodgeit-housekeeping.csv`).

**Views (17/9, designer, system views only).** Task table: **Flight
deck - by due date** (Active, Court = Practice, Due Date contains data,
sort Due asc — collapses to one row per job), **Practice court - open**
(Active + Practice, sort Job then Stage Sequence), **Customer court —
chase list** (Active + Customer, sort Job). Related columns Entity (Job)
and Engagement (Job) display through the lookup. Duplicate system views
deleted in the maker portal. Personalization: English (Australia),
24-hour.

**LodgeIT API.** Verified from LodgeIT's own docs (July 2026): APIs are
inbound only (financial/BAS/SMSF import); no outbound form-status
endpoint; Client read-only API v1 "in the works"; Time Tracker API
"coming next"; webhooks on roadmap, no docs. Email sent to Andrew Noble
and support@ (first attempt bounced: MAILTO: address type from a copied
hyperlink; re-sent). Manual all-status export remains the feed.

---

## Rulings ratified this session (now doctrine — see jobs-doctrine)

1. **Job grain.** One job per entity per return year (current and each
   arrears year); activity statements per obligation, managed-AS clients
   only. Prior-year arrears: one job per year, that year's AS forms
   folded in as tasks — including overdue amendment forms (Coolabah
   FY2022 carries three).
2. **Amendments.** An amendment to a lodged form is its own small job
   (Amendment template), keyed with its amendment number; completed
   history stays immutable.
3. **Composite key.** entity | type | period start | period end |
   amendment. Year alone collides on monthly lodgers (Celmec, EIV,
   Goodyear).
4. **Billing Rhythm** on cap_engagement; five exceptions by hand.
5. **Flight-deck principle.** The system ranks, it doesn't ring. Views
   are consulted, not notified. The only master caution is the
   deviations/NEW-entrant report, shown once when something changes.
6. **AS scope — amended same day.** "Scope limits work, never sight."
   No = no AS jobs generated. Obligations are NOT dropped: they land in
   the stewardship register, and each in-scope job for that client
   carries one standing task "Stewardship review: ATO position incl.
   out-of-scope AS" (to be added to proposer/applier — pending).
   showcustomer default No for that task.
7. **Snapshot convention.** `data\lodgeit-allstatus-YYYY-MM-DD.xlsx`;
   the all-status export is the single feed (Lodged side validates,
   New/Draft side proposes, transitions between snapshots are movement).
8. **Quarterly AS sweep** as a standing job; NEW-entrant caution light;
   new PAYGI entrants get first task "Review instalment — vary if
   needed" due the instalment date.
9. **Zip is the only writer.** Terminal-side edits to a script either
   return to the master copy or don't happen (the 2c overwrite lesson).
10. **System views only**, built in the maker portal; personal views are
    not solution-aware.
11. **Gold path.** Nothing built closes productisation. Known debts:
    unmanaged single environment, security model of one, licensing
    economics. A gold-register doctrine file is to be started.

---

## Craft lessons (added to pre-flight law)

- **MSAL:** `-Silent` and `-Interactive` are rival parameter sets; use
  try/catch (silent from cache, interactive fallback).
- **Metadata read endpoint serves stale 404s** for freshly created
  attributes while the write side knows the truth: an "already exists"
  (0x80047013) immediately after a 404 probe means skip, not conflict.
  Scripts 38+ catch it yellow; 41 pauses 60 s after column create.
- **Navigation property names are case-sensitive and set at
  relationship creation** (`cap_JobTemplateId`, `cap_JobId`) — never
  assume; read `ManyToOneRelationships.ReferencingEntityNavigationPropertyName`.
- **Dates crossing a boundary get explicit culture + a formats array**
  (`d/M/yyyy`, `dd/MM/yyyy`… with en-AU). LodgeIT writes `1/07/2026`.
- **No `-f` inside hashtable literals** (parser error); precompute.
- **Windows PowerShell 5.1 vs pwsh 7:** `.ForEach` on a single object
  fails in 5.1; execution policy is Restricted in 5.1 after a reboot.
  House shell is `pwsh`; `Set-ExecutionPolicy RemoteSigned -Scope
  CurrentUser` applied.
- **Zips published while Mark is on another machine never reach HITCH;**
  re-present from the chat on HITCH. Locate before expanding.
- **NDR "NoConnectorForAddressType"** = recipient stored as MAILTO: type
  from a copied hyperlink; retype plain and clear autocomplete.

---

## Session commits (in order)

f32bddf Session 37 Part 1: billing rhythm + AS scope (stewardship ruling), template probe
(fix) MSAL silent/interactive rival parameter sets — try/catch fallback
(commit) Session 37 Part 2: three templates seeded from probe; proposer with live AS-scope + stewardship register
432d6ad Fix: resolve nav property from metadata for lookup bind; no -f inside hashtable literals
c108fd7 Proposer reads dated lodgeit-allstatus-*.xlsx snapshots (naming convention ratified)
ccb2642 Fix: en-AU date parse, single-digit day/month tolerated
7adfcd8 Re-apply snapshot glob after zip overwrite
(commit) Session 37 Part 3: apply jobs (plan/apply modes, nav props from metadata)
(commit) Fix: alias proposer 'Year End' shorthand to 'Annual Accounting - Year End'

---

## Standing carried into 38

- Part 0 mirror hygiene (4 mark-as-lodged, 4 TFNs) and the 8 AS forms —
  LodgeIT UI.
- Create-list: Axford Peter (entity exists in CAP; LodgeIT forms
  needed), Salzmann, Kaer Morhen Trust, Hammett fund, JR & BJ Pharoah
  fund. Then re-export → 39 → 40.
- Keep-or-release verdict on ~20 OnATOList = N clients (+ Holly Ryan
  pair, Gurney held).
- Stewardship task injection into proposer/applier (ruling 6).
- Panel-hands and the three protection billing rulings; sibling DOBs
  CSV; Harborne's job view; gold register.
- Tailscale live 16/9 (HITCH 100.88.29.13, Gurty 100.97.75.69); HITCH
  sleep Never, NIC power-off disabled 17/9.
