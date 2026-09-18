# CAP — Gold Register
*Productisation debts: every sole-practitioner shortcut, recorded the day it is taken, with what "going for gold" would revisit. Ratified as doctrine 15 Sep 2026 ("please don't lock me out of going for gold"). Ignorance stops being bliss the day it's a list.*

| # | Debt | Taken | Why it was right for one practice | What productisation revisits | Reversible? |
|---|---|---|---|---|---|
| G1 | Single unmanaged environment (CAP Production); no dev/test split | 8 Sep 2026 | One builder, one tenant, schema-as-code in git makes the env reproducible | Managed solution export; dev → test → prod pipeline; solution versioning per release | Yes — managed exports exist for the day distribution happens |
| G2 | Security model of one: no security roles beyond the builder, no column security, audit off | 8 Sep 2026 | Sole user; TFNs protected by tenant login + Tailscale posture | Security roles (practice / customer / auditor), column-level security on TFN/ABN/bank, auditing on, row ownership by business unit | Yes — layers on, doesn't fight the schema |
| G3 | Licensing economics unexamined: Dataverse per-seat assumed | 15 Sep 2026 | One seat | Customer access via Power Pages (per-login/per-capacity), or own data tier; cost model per tenant | Commercial decision, not technical |
| G4 | LodgeIT is the lodgement gateway; ATO bridge (SBR/DSP) not built | Standing | Free via QBO partner status; API is inbound-only (verified Jul 2026 docs) | Own DSP registration and SBR integration; or LodgeIT read API if it ships | Yes — proposer input changes format, downstream unchanged |
| G5 | Scripts hold tenant/client IDs and env URL as literals | 8 Sep 2026 | One environment | Parameter file / per-env config; secrets in credential store only | Trivial |
| G6 | Views built in the designer, not scripted (system views, solution-aware) | 17 Sep 2026 | Faster; still travels with the solution | Export views as part of solution; or script savedquery FetchXML for reproducibility | Yes |
| G7 | Cadence stamper and AS sweep are hand-run scripts on the 1st | 17 Sep 2026 | One operator with a calendar habit | Scheduled flow / Azure automation per tenant | Yes |
| G8 | BAS check engine to remain Python outside Dataverse (Session 40 plan) | 18 Sep 2026 | Proven script exists; "outside tools for now" | Hosted engine (Azure Function) writing to Dataverse; or Dataverse plugin | Yes — results contract is the interface |

**Rule:** a new row is added in the same session as the shortcut, never later. A row is closed (struck through, dated) when the debt is repaid.
