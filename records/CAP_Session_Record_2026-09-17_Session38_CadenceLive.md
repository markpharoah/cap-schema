# commercial ● ACCOUNTING

**SESSION RECORD — SESSION 38: DUE DATES HOME, CADENCE LIVE, MULTICUBE ON THE DECK**
Commercial Accounting Practice (CAP) · 17 September 2026 · HANDOVER TO SESSION 39

---

## Outcome — ALL APPLIED, ALL COMMITTED (through dd8d5fd)

**Due dates live on jobs — ruling honoured (41-job-duedate.ps1).**
`cap_duedate` (DateOnly) added to cap_job; 60 s cache pause built in;
**202 jobs backfilled** from their latest task date, `cap_periodstart /
cap_periodend` backfilled from the Key in each description (ARREARS
keys → financial year bounds). Harborne untouched (no key). A Jobs-level
flight deck view is now possible and is the recommended primary view.

**Cadence ratified and built.** Second job source beside obligations:
cadence-driven jobs that exist because the engagement says so. Mark's
MultiCube service lines (CFO Strategic Management, Dispute Resolution,
Systems Design, Weekly KPI, Management Accounts, Forecasting &
Budgeting, Cashflow Management) resolve to three shapes —
**CFO Monthly Cycle** (8 tasks: month-end data · KPI weeks 1–4 ·
management accounts [milestone] · cashflow · strategic review
[Completed, 100% anchor]; 10/20/35/15/20), **Budget & Forecast**
(3 tasks, quarterly; Q4 = annual budget), **Project** (Scope · Work ·
Deliver · Close; stamped once, lives until closed). Seeded by
42-templates-cadence.ps1. CFO Strategic Management is the engagement
type, not a job.

**MultiCube exists (43-multicube.ps1).** Plan mode printed every
picklist on cap_entity / cap_engagement with values; apply created
**MultiCube Stockfeeds Pty Ltd [MUL0001]** (cap_type Company 764820001,
cap_status Active 764820000) and engagement "MultiCube Stockfeeds - CFO
services" (cap_engagementtype Virtual CFO 100000011, Monthly fixed, AS
scope No).

**The crank (44-stamp-cadence.ps1).** Plan/apply; monthly-fixed
engagements → `CODE · CFO <Mon YYYY>` from CFO Monthly Cycle, due last
day of month, period = month; `-Forecast` adds `Budget & Forecast Q<n>
FY<yy>`; `-Project CODE -ProjectName` stamps a Project job. Idempotent
on name (demonstrated live: four SKIPs on the second call). Stamped:
**CEL0001, IEI0003, ELE0001, MUL0001 · CFO Sept 2026**;
**MUL0001 · Enviro Straw dispute**; **MUL0001 · Systems design**.

**IEI resolved.** IEI = Association of Electrical Inspectors Ltd =
LodgeIT code **IEI0003** (entity already existed; the earlier
"Institute of Electrical" name-probe was the wrong string). 37 patched
to set it by code; rhythm Monthly fixed applied.

**Picklist values on record** (from 43 plan): cap_entity.cap_status
764820000 Active / 001 Inactive / 002 Prospect / 003 Former / 100000000
Merged / 100000001 Contact; cap_entity.cap_type 764820000 Individual /
001 Company / 002 Trust / 003 Partnership / 004 SMSF / 005 Other / 006
Association; cap_engagementtype 100000000 Annual Accounting … 100000010
Tax Only, 100000011 Virtual CFO; cap_regulatorycapacity 100000000 Tax
Agent (TASA) … 100000005 None; cap_evidencebasis 764820000 Established /
001 Documented.

---

## Rulings ratified this session

1. **Cadence jobs** are a distinct job source: Billing Rhythm is the
   gearing; the stamper is the crank; run on the 1st beside the AS sweep.
2. **Weekly KPIs are four tasks under one monthly job** — a missed week
   is visible; the deck shows one row.
3. **Projects are stamped once and live until closed;** milestones
   carry the real stages.
4. **Retainer WIP question** ("is the fixed fee underwater?") is answered
   by time entries charged to cadence jobs — Session 39 candidate.

---

## Craft lessons

- **Angle-bracket placeholders in printed hints get pasted literally;**
  print real example values.
- **ApplicationRequired columns are not enforced by the Web API** — set
  them anyway (cap_status on entity create).
- **A fresh window after reboot is Windows PowerShell 5.1**, not pwsh:
  Restricted policy, no `??`, different error format. `pwsh` first.
- **HITCH reachability:** sleep Never (was already), Ethernet adapter
  "allow the computer to turn off this device" unticked, active hours
  to be set; screen-off is irrelevant. 16/9 dead air was MC's provider.

---

## Session commits (in order)

53fb789 Session 38 Part 1: IEI rhythm, cap_duedate on jobs + backfill, cadence/project templates
(commit) Session 38 Part 2: MultiCube entity/engagement, cadence stamper
dd8d5fd 43: set entity status Active on create

---

## NEXT — fly it before building more

**Standing cadence (habit, not session):** 1st of month `44 -Month
YYYY-MM`; each AS quarter: ATO exports + LodgeIT snapshot → deviations
→ NEW entrants → 39/40; after each lodgement run: re-export.

**Immediate:** Jobs-level "Flight deck — jobs" view (Active, sort Due
asc; Due · Entity · Name · Engagement · Template). Complete tasks by
deactivating — percent derives from what is closed. LodgeIT hygiene,
8 AS forms (28 Oct instalment entrants first), create-list, keep-or-
release verdict, then re-export → 39 → 40 (flywheel's first full turn).

**Session 39 candidates:** time entries against jobs (retainer WIP);
stewardship task injection (37 ruling 6); Jobs view derivations
(percent/stage/court readout — the parked argument); panel-hands +
protection billing rulings; gold register doctrine file; customer
visibility surface (showcustomer already set everywhere); sibling DOBs;
Coolabah "how deep".
