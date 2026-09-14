# GTM Intelligence Platform

A lightweight customer data platform built on dbt. It takes product usage, Salesforce and a third-party company feed — three systems with no key in common — and resolves them into one account-level view a sales rep can work from.

**Full write-up:** [`docs/overview.html`](docs/overview.html) is the project report: the problem, the data provided, the exploratory analysis, model-by-model results, and the memo. Open it in a browser. Its DAG is generated from dbt's own manifest and every number in it is read back out of the built warehouse.

**Run it:** `docker run --rm -v "$PWD:/app" gtm-cdp` after `docker build -t gtm-cdp .`, or `make setup && make build` in a virtualenv. Either way you should see `PASS=223 WARN=4 ERROR=0`. Details in [Running it](#running-it).

The brief set the constraint that shaped every design decision here: favour an unresolved mapping over a bad merge, carry a source and a confidence on every resolved mapping, and set a flag on conflicts rather than guessing. Nothing in this project merges on a similarity score, and where evidence disagrees the record goes to a review queue with the reason attached.

---

## Where each part of the brief is answered

| Brief | Where it lives |
|---|---|
| **A** · users → orgs → accounts, deterministic, with an ambiguity flag | `int_user_identity` (exact-email person merge) → `int_memberships` → `int_org_account_resolution` → `int_member_account_resolution`. An account is assigned only when exactly one candidate survives; otherwise `is_ambiguous` and a `resolution_status` say why. Five of six orgs map; Frank spans two accounts and gets none. |
| **A** · classify activity by surface, honestly, with confidence | `int_product_activity`: every event carries `surface`, `evidence_kind` (usage vs intent), `attribution` (deterministic / heuristic / none), `confidence_score` and `actor_type`. The rules are a seed, `ref_surface_signals`, not buried in SQL. |
| **A** · per-member view, rolled up to the account | `fct_member_surface_activity` (person × surface, with "no evidence" as an explicit row) → `fct_account_surface_adoption` (account × surface, plus a plain-English `honest_summary`). |
| **A** · what `user_id` on an object actually represents | It's the credential, not the person. Bob's 12 nightly runs are tagged `actor_type = 'automation'` and never counted as a member using the product; `assert_automation_never_counted_as_active_member` enforces it. Objects attribute through `project → org → account`, never through the creator's membership — `assert_objects_attributed_by_project_not_by_user`. |
| **B** · normalise identifiers into comparable keys | `int_match_keys` — the one place anything is normalised, for both the CRM side and the vendor side, in the same CTEs. Plain SQL. `assert_match_keys_are_normalised` pins the expected output for all 21 entities. |
| **B** · resolve external companies to accounts | `int_signal_company_match_candidates` (every candidate link) → `int_signal_company_resolution` (precedence decides, and only if every other key agrees). |
| **B** · keep the unresolved | Nothing is dropped: `no_external_company_dropped_in_resolution`. Unresolved leaves through one of two doors — `net_new_prospects` when no account could exist, or the review queue when one probably does (a conflict, or no identifiers). `assert_every_external_company_has_one_output` proves each company takes exactly one. |
| **C** · a unified view reps can act on, built to extend | `fct_account_signals` puts every source in one shape (a new source is one `union` branch); `account_360` is the rep view built on top, carrying `adoption_in_plain_english` so the caveats travel with the numbers. |
| **D** · tests you'd actually run | 168 of them — 166 data tests plus 2 unit tests — see [Tests](#tests-youd-actually-run). The interesting ones assert *principles*, not just shapes; the unit tests pin behaviour the seeds can't reach. |
| **D** · the memo | [MEMO.md](MEMO.md) (and `MEMO.pdf`), answering all six questions in order. |
| **Write-up** · the whole thing as a report | [`docs/overview.html`](docs/overview.html) — problem, data provided, exploratory analysis, model-by-model results, and the memo. Its DAG is generated from dbt's manifest and every number in it is read back out of the built warehouse. |
| **Deliverable** · runnable, `dbt build` passes | See below. 223 pass, 4 intentional warnings, 0 errors. |
| **Deliverable** · data issues found | [Data issues found](#data-issues-found) — 15 of them. |
| **Deliverable** · time spent, where I'd invest more | [Time spent](#time-spent-and-where-id-invest-more). |

---

## Running it

Three ways in, all producing the same thing. Pick whichever you already have installed.

| | You need | Best for |
|---|---|---|
| **A · Docker** | Docker only | Nothing to install, guaranteed-clean environment |
| **B · venv** | Python 3.9–3.13 | Iterating on the models, `dbt show`, `dbt docs serve` |
| **C · Snowflake** | credentials | Running the same code against a real warehouse |

Whichever you use, the expected output is:

```
Done. PASS=223 WARN=4 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=227
```

The four warnings are meant to be there. They are data-quality alerts for problems in the seeds (listed under *Data issues found*). I made them warn rather than fail so the pipeline still completes, but the problem shows up in every run instead of being forgotten.

---

### A · Docker

No Python, no dbt, no warehouse. The image pins Python 3.12 because dbt does not support 3.14 yet.

```bash
docker build -t gtm-cdp .
docker run --rm -v "$PWD:/app" gtm-cdp
```

That is the whole thing. The bind mount is what puts `gtm_cdp.duckdb`, `target/` and `logs/` back on your machine; drop it and you get a throwaway container that just proves the build is green.

With Compose, which sets the mount and `DBT_PROFILES_DIR` for you:

```bash
docker compose run --rm dbt                              # full build (default command)
docker compose run --rm dbt dbt test                     # tests only
docker compose run --rm dbt dbt show -s account_360 --limit 10
docker compose run --rm dbt python docs/build_lineage.py # regenerate the design doc's DAG
docker compose run --rm dbt bash                         # poke around inside
```

Two notes. On Linux, files written through the bind mount are owned by root — add `--user "$(id -u):$(id -g)"` if that matters to you; on macOS and Windows Docker Desktop maps ownership for you. And partial parsing is switched off in `dbt_project.yml` on purpose: dbt's parse cache stores absolute paths, so without that flag a container run and a venv run over the same directory poison each other's cache and every seed fails with a confusing `No files found that match the pattern /Users/...`. This project parses in well under a second, so the cache buys nothing.

### B · Local virtualenv

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export DBT_PROFILES_DIR=.        # profiles.yml ships with the project
dbt build                        # seeds -> models -> tests, in dependency order
```

One trap worth naming: **dbt does not support Python 3.14 yet**, and Homebrew's `python3` is already on it. If `pip install` fails, point the venv at 3.12 or 3.13 explicitly — `python3.12 -m venv .venv`, or `uv venv --python 3.12 .venv` if you have `uv`. The Dockerfile pins 3.12 for the same reason.

`requirements.txt` pulls `dbt-core`, `dbt-duckdb`, plus `duckdb` and `markdown` for the two doc generators. The default target is a **local DuckDB file** written to `gtm_cdp.duckdb` in the project root, so there is no warehouse to set up and no credentials to supply.

There is a `Makefile` if you prefer:

```bash
make setup      # create .venv and install requirements.txt
make build      # dbt build
make test       # dbt test
make docs       # rebuild, then regenerate docs/overview.html from the manifest + warehouse
make docker     # build the image and run dbt inside it
make clean      # remove target/, logs/ and the .duckdb file
make help       # list all targets
```

### Looking at the results

```bash
dbt show -s account_360 --limit 10
dbt show --inline "select account_name, priority_rank, action_reasons from {{ ref('account_360') }} order by priority_rank"
dbt docs generate && dbt docs serve      # dbt's own lineage graph + column docs
open docs/overview.html                  # the project report, with the DAG and every result
```

Or open `gtm_cdp.duckdb` in any DuckDB client — the schemas are `raw`, `cleansed` and `unified`:

```bash
pip install duckdb
python -c "import duckdb; duckdb.connect('gtm_cdp.duckdb').sql('select account_name, priority_rank, action_reasons from unified.account_360 order by priority_rank').show(max_width=200)"
```

```bash
# or the DuckDB CLI, if you have it
duckdb gtm_cdp.duckdb -c "select * from unified.rpt_resolution_quality order by metric_order"
```

### C · On Snowflake

The same code runs on Snowflake. `macros/cross_db.sql` holds three shims for the syntax that genuinely differs (JSON extraction, list aggregation, one keyword column name) plus two helpers for the as-of date. Everything else is plain SQL.

```bash
pip install "dbt-snowflake>=1.9"
export SNOWFLAKE_ACCOUNT=... SNOWFLAKE_USER=... SNOWFLAKE_PASSWORD=...
export SNOWFLAKE_ROLE=TRANSFORMER SNOWFLAKE_WAREHOUSE=TRANSFORMING SNOWFLAKE_DATABASE=GTM_CDP
dbt build --target snowflake     # dev: writes DEV_RAW / DEV_CLEANSED / DEV_UNIFIED
dbt build --target prod          # prod: writes RAW / CLEANSED / UNIFIED
```

Dev targets get a schema prefix on purpose (see `macros/generate_schema_name.sql`), so a dev run cannot overwrite production. To use today's date instead of the frozen snapshot, pass `--vars '{as_of_date: today}'`.

> One caveat, stated plainly: `dbt build` passes end to end on DuckDB — verified on dbt-core 1.12.4 with dbt-duckdb 1.11.0, both in a venv and in the Docker image. For Snowflake the project compiles and every compiled file passes a Snowflake-dialect syntax check, but I had no live Snowflake account to run it against.

### Regenerating the report

`docs/overview.html` is the project write-up: problem, data, exploratory analysis, model-by-model results, and the memo. Its DAG comes from dbt's manifest and every number in it is read back out of the built warehouse, so after any change:

```bash
dbt build
python docs/build_lineage.py       # nodes, layers, passes and edges from target/manifest.json
python docs/build_report_data.py   # every figure, from gtm_cdp.duckdb
python docs/build_memo_pdf.py      # MEMO.md -> MEMO.pdf (needs Chrome installed)
```

---

## How the project runs: seeds, DAG, orchestration

### Yes — everything is a dbt seed

All 21 CSVs are dbt seeds, in two folders under `seeds/`:

| Folder | What's in it | Loaded as |
|---|---|---|
| `seeds/raw/` | the **18 delivered `raw_*.csv`**, byte for byte as they arrived, next to the original `SEEDS_README.md` | tables in schema `raw` |
| `seeds/reference/` | **3 `ref_*.csv`** I added — the platform's rules kept as data, not SQL | tables in schema `raw` |

`seed-paths: ["seeds"]` in `dbt_project.yml` picks up both; the sub-folders are for humans, dbt flattens them into one namespace. Nothing preprocesses the CSVs — `dbt seed` reads them directly, which is the point: the delivered files are the source of truth and you can diff them against what was sent.

Two seed configs matter:

- **Column types are pinned** for the fields that would otherwise be guessed wrong. `repo_info` and `metadata` stay `varchar` so the JSON survives as text to be parsed in RAW; `ticker`, `domain`, `linkedin_*` and `segment_pages.user_id` stay `varchar` because they're sparse enough that type inference gets adventurous.
- **`+quote_columns: false`** on purpose. Snowflake upper-cases unquoted seed columns while DuckDB keeps them as written, and `keyword_column()` is the one shim that reconciles the two — needed because one seed has a column literally named `timestamp`.

The three reference seeds are what let rules change without a SQL edit: `ref_surface_signals` (what each signal proves and how confidently), `ref_org_mapping_sources` (contract 0.95 > billing_parent 0.85 > fallback 0.50) and `ref_external_match_rules` (linkedin_slug 0.90 > website_domain 0.85 > linkedin_domain 0.75, with `company_name` marked `can_resolve = false`).

### One command, and what it actually does

```bash
dbt build
```

`build` is seeds → models → tests interleaved in DAG order: each node runs only after its parents, and its tests run the moment it's built. So a broken key in RAW fails before anything downstream of it is computed, rather than after the whole pipeline has run on bad data. That's why the README tells you to run `build` and not `seed && run && test` — the latter would test everything only at the end.

| Command | What it runs |
|---|---|
| `dbt build` | everything: 21 seeds → 18 RAW views → 12 CLEANSED tables → 8 UNIFIED views → 166 data tests + 2 unit tests |
| `dbt build -s tag:cleansed` | just the transformation layer and its tests |
| `dbt build -s +account_360` | `account_360` and every ancestor it needs |
| `dbt build -s int_match_keys+` | the normaliser and everything downstream of it — the blast radius of a key change |
| `dbt test -s tag:unified` | the business-facing assertions on their own |
| `dbt docs generate && dbt docs serve` | the lineage graph and column-level docs |
| `python docs/build_lineage.py` | regenerates the DAG drawn in `docs/overview.html` from `target/manifest.json` |

### The DAG

The version below is the readable summary. The interactive one in
[`docs/overview.html`](docs/overview.html) is **generated from dbt's own
`target/manifest.json`** by [`docs/build_lineage.py`](docs/build_lineage.py) — every node, every
edge, and even the four CLEANSED passes, which are computed as dependency depth rather than
asserted. It cannot drift from the DAG dbt actually builds, and adding a model without a one-line
description fails the generator rather than shipping an undocumented box. Re-run it after any
`dbt build`.

```
  seeds/raw/*.csv  (18)          seeds/reference/*.csv  (3)
        │                                 │
        ▼  dbt seed                       ▼
  ┌─────────────────────────────────────────────────┐
  │ RAW · schema raw · views, 1:1 over each seed    │
  │   stg_product__*  (12)                          │
  │   stg_crm__*      (2)                           │
  │   stg_signals__*  (4)                           │
  └─────────────────────────────────────────────────┘
        │
        ▼  4 passes, tables
  ┌─────────────────────────────────────────────────┐
  │ CLEANSED · schema cleansed                      │
  │  1 key      int_user_identity                   │
  │             int_org_account_resolution          │
  │             int_org_trace_trend                 │
  │             int_match_keys                      │
  │  2 relate   int_memberships, int_api_keys       │
  │             int_account_trace_trend             │
  │             int_signal_company_match_candidates │
  │  3 resolve  int_member_account_resolution       │
  │             int_signal_company_resolution       │
  │  4 classify int_product_activity                │
  │             int_external_signals                │
  └─────────────────────────────────────────────────┘
        │
        ▼  views only
  ┌─────────────────────────────────────────────────┐
  │ UNIFIED · schema unified                        │
  │   dim_members · fct_member_surface_activity     │
  │   fct_account_surface_adoption                  │
  │   dim_signal_companies · fct_account_signals    │
  │   account_360 · net_new_prospects               │
  │   rpt_resolution_quality                        │
  └─────────────────────────────────────────────────┘
```

The reference seeds feed straight into CLEANSED and UNIFIED, not through RAW — they're already clean by definition, and routing rules through a staging view would only add a layer with nothing in it.

### Materialisation, and the reasoning

| Layer | Materialised as | Why |
|---|---|---|
| Seeds | tables | dbt loads CSVs as tables; that's the landing zone |
| RAW `stg_*` | **views** | a rename, a cast and a null-normalisation over one seed. Copying the data would buy no speed and create a second copy to drift |
| CLEANSED `int_*` | **tables** | identity resolution is the expensive, opinionated part. Computing it once means every downstream view reads the *same* answer — if these were views, `account_360` and `rpt_resolution_quality` would each recompute the match ladder and could, after a code change, disagree |
| UNIFIED | **views only** | the brief asks for views, and it's the right call: they're always current, cost nothing to keep fresh, and there's no orchestration question about when a mart was last refreshed |

### Schemas and environments

`macros/generate_schema_name.sql` names the schema after the layer, so the warehouse reads the way the project does. On DuckDB and on a target named `prod` you get `raw` / `cleansed` / `unified`. On any other target the schema is prefixed — `DEV_RAW`, `DEV_CLEANSED`, `DEV_UNIFIED` — so a dev run can't overwrite production.

`as_of_date` is frozen at `2026-07-27` (the last event in the seeds), and every "last N days" window is measured from it, so results are deterministic no matter when you run the project. In production you'd pass `--vars '{as_of_date: today}'`.

### Orchestration in production

*Not built here — the seeds are the whole input — but this is how I'd run it, and the shape the project is already in for it.*

The only layer that changes is RAW. Replace the seeds with landed tables (Fivetran for Salesforce, the product's own CDC or Snowpipe for usage, the vendor's API for external intelligence), declare them in a `sources.yml`, and repoint the 18 `stg_*` models from `ref('raw_x')` to `source('...', 'x')`. That file is written and shipped — [`docs/sources.production.yml`](docs/sources.production.yml), with freshness thresholds per feed. It lives in `docs/` rather than `models/` so `dbt build` on the seeds stays green; moving it is step one of going live. **CLEANSED and UNIFIED don't change at all** — that's the payoff of never letting business logic touch a seed directly. The 3 reference seeds stay seeds, because they're version-controlled rules, not ingested data.

On Airflow (Astronomer), one DAG per cadence rather than one giant task:

```
  ingest sensors ─► dbt source freshness ─► dbt build -s tag:raw+ tag:cleansed
                                                  │
                                                  ▼
                                      dbt build -s tag:unified
                                                  │
                                      ┌───────────┴───────────┐
                                      ▼                       ▼
                             reverse-ETL to SFDC      alert on rpt_resolution_quality
```

with `dbt build --select state:modified+ --defer` in CI so a pull request only rebuilds what it touched. Cadence follows the data: product usage and traces hourly, Salesforce every few hours, the external feed daily — which is also the point at which `fct_account_signals` should become an incremental model with a daily snapshot behind it, since MEMO Q6 needs the history of what a rep saw and when.

Two things I'd add the day this stops being a take-home: `dbt source freshness` gating the run so stale CRM data can't silently produce a confident 360, and the `dq_warn__*` tests promoted from warn to page-someone once the underlying data issues are supposed to be fixed.

---

## Step 1 — Read the data first

Before writing a single model I profiled all 18 seeds: 163 rows across 77 columns. The profile is part of the project, so it can be re-run whenever the seeds change:

```bash
dbt compile -s eda_seed_profile     # then run target/compiled/.../eda_seed_profile.sql
```

It reads column metadata from the warehouse, so it needs a connection to compile. On the DuckDB target that's just the local file.

Eight questions, and what the data said:

| # | Question | Answer |
|---|---|---|
| 1 | Is one `user_id` one person? | **No.** 9 logins, 8 people. `grace@acme.com` signed up twice. |
| 2 | Does a person belong to one org? | **No.** Two of the nine logins sit in two orgs, and one of those spans two different accounts (Frank: Globex and Umbrella). |
| 3 | Does every org have a CRM account? | **No.** Five of six map, and one of those five only through a fallback rule (`org_c_fallback`). |
| 4 | Do objects belong to their creator's org? | **Yes**, all 31 of them. That makes `project → org` a safe attribution path, and a safer one than the user, who may sit in several orgs. |
| 5 | Is there any column that names the client or surface? | **No.** No object records a client, a surface, a user-agent, or which API key created it. `source_url`, `mapping_source` and `key_hash` are the near-misses, and none of them is it. Surface has to be inferred from side-effects. |
| 6 | How much origin evidence is there? | 17 of 22 experiments carry `repo_info`; 3 carry neither JSON field. Across all 31 objects, 12 have no origin evidence at all. |
| 7 | Do the external identifiers join as delivered? | **No.** Not one vendor website equals a CRM domain literally. The 10 non-null websites arrive in seven different shapes: `http` and `https`, with and without `www.`, capitalised hosts, trailing slashes, paths and query strings. After normalising, 7 of 11 companies match on domain and 8 on LinkedIn. That's also when `hooli.com` turns out to belong to two accounts. |
| 8 | What time window does the data cover? | Objects and page views 15–26 Jul, wizard and docs clicks 1–12 Jul, news 17–25 Jul, traces 20–27 Jul (4 orgs over 8 days, rising exactly 0.7 GB a day, so clearly synthetic), tech detections 1 May to 1 Jul and product detections 15 May to 25 Jul. Nothing is recent, so every window is measured from a frozen `as_of_date` instead of `current_date`. |

The first four questions gave me the identity spine. Five and six set how careful the surface layer had to be. Seven is why the matching rules look the way they do, and eight is why every window runs from a fixed date. The full list of oddities is under [Data issues found](#data-issues-found).

---

## Step 2 — Logical architecture

Before the dbt layers, the shape of the problem. The three sources arrive with no shared key. Each one is normalised into comparable keys and resolved onto the account spine, and anything that fails to resolve goes to the review queue or the prospect list.

```
  SOURCES                     COMPARABLE KEYS          RESOLUTION SPINE            SERVED TO SALES
  ─────────────────────       ───────────────────      ────────────────────        ────────────────────
  Product usage                                        login ─► person
   logins, orgs, projects,    email ─────────────►     (exact email)           ┐
   objects, page views,                                                        │
   wizard/docs clicks,        project ─► org ──────►   org ─► account          ├─► account_360
   API keys, traces                                    (source + confidence)   │   member views
                                                                               │   signal feed
  Salesforce                  domain ────────────►                             │   net-new prospects
   accounts (domain,          linkedin slug ──────►    company ─► account      ┘
   linkedin, ticker),         name key (hint only)     (key precedence,
   org → account map                                    conflicts flagged)     ┐
                                                                               ├─► review queue
  External feed                                        unresolved is kept:     │   (conflict, ambiguous,
   companies, news,                                    conflict · ambiguous ───┘    weak link)
   products, tech                                      no account ─────────────► net-new prospects
```

### Which join key, and why that one

| Join | Key used | What the EDA said | Rejected alternative |
|---|---|---|---|
| **login → person** | `lower(trim(email))` | Q1: 9 logins, 8 distinct emails. The email is the credential someone signs in with, so an exact match is just a fact. | Name, or the email domain. `acme.com` on its own covers three different people. |
| **person → org** | `raw_members (user_id, org_id)` | Q2: it really is many-to-many. Two logins sit in two orgs, and Frank's two orgs belong to two accounts. | Assuming one org per user, which would have quietly moved Frank's Umbrella work onto Globex. |
| **object → org** | `project_id → projects.org_id` | Q4: all 31 objects sit in a project whose org their creator belongs to, so the project path is both available and consistent. | `user_id → member org`, which is ambiguous for multi-org people and would need a tie-break. |
| **org → account** | `account_org_map.org_id` + `mapping_source` | Q3: five of six orgs map, and the *source* of each link varies (contract, billing parent, fallback). That variance is what becomes the confidence score. | Matching member email domains to the account domain. Globex has no CRM domain at all, so it would resolve nothing there. |
| **browser event → account** | the person, and only when unambiguous | Q2 and Q5: page views, wizard views and docs clicks carry a `user_id` and nothing else. | Picking the person's "main" org, which is a coin flip for someone in two accounts. |
| **traces → org** | `trace_volume.org_id` | Q8: the grain is org × day with no user column, so this is org-level evidence only. | Splitting GB across members by headcount. That's invented precision. |
| **external company → account** | `linkedin_slug`, then `domain_key`, then the LinkedIn-reported domain | Q7: nothing joins as delivered. After normalising, LinkedIn slugs are unique per entity while `hooli.com` covers two accounts, so LinkedIn leads and domain supports. | Company name. It would send "Hooli Inc" to the wrong Hooli and merge Stark Industries on a name alone. |
| **signal → company** | `company_id` | The feed's own key, and it holds for all 21 news, product and tech rows. One headline's text names a different company than its key, though. | Matching headlines to company names. That's the check, not the join. |

Three rules hold the picture together:

1. **One model builds every key.** `int_match_keys` normalises the Salesforce side and the vendor side in the same CTEs, so the two can't drift apart. It's plain SQL (lower, trim, strip, split) and a test pins its output for all 21 entities.
2. **Attribution follows the strongest path available.** Objects go `project → org → account`, which is a fact about the object. Only org-less events fall back to the person, and only when that person belongs to exactly one account.
3. **Unresolved is an output.** Conflicts and ambiguity go to a review queue with the reason attached; companies and sign-ups with no account become prospects. Both are lists a human can work through.

---

## Step 3 — The shape: RAW → CLEANSED → UNIFIED

| Medallion layer | dbt convention | Schema | Materialized | What happens here |
|---|---|---|---|---|
| **RAW** | seeds + `staging` | `raw` | seeds + **views** | Land the 18 CSVs as delivered, then put a 1:1 typed view on each: rename, cast, turn `''` into null, parse JSON into columns. No business logic. |
| **CLEANSED** | `intermediate` | `cleansed` | **tables** | The transformation layer. Case matching (every identifier built by the same model), de-duplication (logins, memberships, events, cross-feed duplicates), identity resolution, surface classification, confidence scoring. UNIFIED reads only from here, apart from one reconciliation metric. |
| **UNIFIED** | `marts` | `unified` | **views only** | What people read: members, account surface adoption, the account signal feed, `account_360`, net-new prospects, and a resolution-quality scorecard. |

```
seeds (18 raw_* + 3 ref_*)
   │
   ▼  RAW: 18 stg_* views (typed, JSON parsed)
   │
   ▼  CLEANSED
   │    int_user_identity ─► int_memberships ─► int_member_account_resolution ─┐
   │    int_org_account_resolution ─────────────────────────────────────────── ┼─► int_product_activity
   │    int_api_keys ───────────────────────────────────────────────────────── ┘   (surface + confidence + actor)
   │    int_org_trace_trend ─► int_account_trace_trend
   │    int_match_keys  (accounts + companies, the one normaliser)
   │         └─► int_signal_company_match_candidates ─► int_signal_company_resolution ─► int_external_signals
   │
   ▼  UNIFIED (views)
        fct_member_surface_activity ─► dim_members
        fct_account_surface_adoption ┐
        fct_account_signals ─────────┼─► account_360
        dim_signal_companies ────────┴─► net_new_prospects
        rpt_resolution_quality
```

Three small reference seeds hold the platform's rules, so they can be read and changed without touching SQL:

- `ref_surface_signals`: every surface signal, which surface it points at, whether it proves usage or only intent, deterministic or heuristic, a confidence, and in plain words what it can and cannot prove.
- `ref_org_mapping_sources`: `contract 0.95 > billing_parent 0.85 > org_c_fallback 0.50`.
- `ref_external_match_rules`: `linkedin_slug 0.90 > website_domain 0.85 > linkedin_domain 0.75`, with `company_name` set to `can_resolve = false`.

### Transformation map — model by model

CLEANSED builds in four passes, and each pass is only allowed one kind of work: **1** make rows unique and comparable, **2** relate them, **3** decide, **4** classify and merge. A model that both resolves *and* scores is a model nobody can debug six months later.

| Model | Grain | Reads | Joined on | What it decides |
|---|---|---|---|---|
| **`int_user_identity`** | login | `stg_product__users` | self, on `lower(trim(email))` | Which logins are the same person. Exact email only; both ids kept, one flagged as the duplicate. |
| **`int_org_account_resolution`** | org | `stg_product__organizations`, `stg_crm__account_org_map`, `stg_crm__salesforce_accounts`, `ref_org_mapping_sources` | `org_id`, `account_id`, `mapping_source` | Which account an org rolls up to, and how much to trust it. The rule seed turns the link type into a confidence; two accounts means none. |
| **`int_org_trace_trend`** | org | `stg_product__trace_volume` | none — aggregate only | 7-day volume ending on the as-of date, and growth against the 7 days before. Org level, because there is no user column to split it by. |
| **`int_match_keys`** | matchable entity | `stg_crm__salesforce_accounts`, `stg_signals__companies` | `union all`, then one set of CTEs | Nothing yet — that's the point. It only makes both sides comparable, so a key can't be built one way for Salesforce and another for the feed. |
| **`int_account_trace_trend`** | account | `int_org_trace_trend`, `int_org_account_resolution` | `org_id` | Nothing new — it just owns the number. Trace growth used to be recomputed in three marts; it is defined once here and read three times. |
| **`int_memberships`** | person × org | `stg_product__members`, `int_user_identity`, `int_org_account_resolution` | `user_id`, `org_id` | Collapses a person's duplicate logins into one membership row, carrying the org's account resolution with it. |
| **`int_api_keys`** | API key | `stg_product__api_keys`, `int_user_identity` | `user_id` | Whose key it is, plus the free-text name hints (`ci-service`, `dave-cli`) that stay *hints* and never become evidence of usage. |
| **`int_member_account_resolution`** | person | `int_user_identity`, `int_memberships` | `person_id` | One account per person, only if all their orgs agree. Frank spans Globex and Umbrella, so he gets none and is marked ambiguous. |
| **`int_signal_company_match_candidates`** | company × method × account | `int_match_keys`, `ref_external_match_rules` | `linkedin_slug = linkedin_slug`, `website_domain = domain_key`, `linkedin_domain = domain_key`, `name_key = name_key` | Every possible link, one row per key that matched. Deliberately doesn't choose — that's the next model's job. |
| **`int_signal_company_resolution`** | company | `int_match_keys`, `int_signal_company_match_candidates` | `company_id` | The one account, by precedence, only if the key is unique to it and every other key agrees. Otherwise conflict / ambiguous / unmatched — never a guess. |
| **`int_product_activity`** | activity | 7 `stg_product__*` event tables, `int_user_identity`, `int_api_keys`, `int_org_account_resolution`, `int_member_account_resolution`, `ref_surface_signals` | `project_id → projects.org_id`, then `user_id`, `org_id`, `person_id`, `signal_code` | Surface, usage-or-intent, attribution, confidence and human-or-automation for every event. Objects go `project → org → account`; only org-less events fall back to the person. |
| **`int_external_signals`** | signal | `stg_signals__news_events`, `__products`, `__tech_detections`, `__companies`, `int_signal_company_resolution` | `company_id`, plus a dedupe on company × normalised launch | Three feeds as one stream, duplicates kept once and marked corroborated, and a headline that names a different company flagged. |

UNIFIED adds no new logic — no matching, no scoring, no dedupe. It shapes what CLEANSED already decided.

| View | Grain | Reads | Joined on |
|---|---|---|---|
| `dim_members` | person | `int_member_account_resolution`, `int_api_keys`, `fct_member_surface_activity` | `person_id` |
| `fct_member_surface_activity` | person × surface | `int_member_account_resolution`, `int_product_activity` | `person_id`, then a cross join to the four surfaces so "no evidence" is an explicit row |
| `fct_account_surface_adoption` | account × surface | `int_product_activity`, `int_memberships`, `int_account_trace_trend`, `int_match_keys`, `ref_surface_signals` | `account_id`, `org_id` |
| `dim_signal_companies` | external company | `int_signal_company_resolution`, `int_external_signals`, `int_match_keys` | `company_id`, `entity_id` |
| **`fct_account_signals`** | signal | `int_external_signals`, `int_product_activity`, `int_org_account_resolution`, `int_account_trace_trend`, `int_match_keys` | `union all` into one shape, then `account_id` |
| **`account_360`** | Salesforce account | `fct_account_signals`, `fct_account_surface_adoption`, and six `int_*` models for the counts | `account_id` throughout |
| `net_new_prospects` | prospect | `dim_signal_companies`, `int_external_signals`, `int_memberships`, `int_member_account_resolution`, `int_org_account_resolution`, `int_product_activity` | `union all` of two anti-joins: companies with no account, people with no account |
| `rpt_resolution_quality` | metric | seven `int_*` models plus `stg_product__segment_pages` | `union all` of counts — no row-level joins |

The thing holding all of this together: **a join key is built in exactly one place and reused.** `int_match_keys` for the external side, `int_user_identity` for people. No two models can normalise the same thing differently, because no two models normalise anything.

---

## Layer by layer

### RAW — land it, type it, don't interpret it

- `stg_product__*` (12), `stg_crm__*` (2), `stg_signals__*` (4): one view per seed.
- `repo_info` and `metadata` arrive as JSON text. They're parsed once, here, into ordinary columns (`repo_is_dirty`, `repo_author_name`, `meta_ci_run_id`, `meta_source`, and so on) so no later layer has to touch JSON.
- Tests at this layer guard the contract with upstream: primary keys, foreign keys, and whether the JSON actually parses.

### CLEANSED — make things comparable, then resolve them

**1. People (`int_user_identity`, `int_member_account_resolution`)**

Emails are compared case-insensitively with `lower(trim(email))`. Two logins with the exact same email are one person; both user_ids are kept and point at a single `person_id`. Nothing fuzzier gets merged.

Person to account runs login → org membership → org → account. If all of someone's orgs roll up to one account they resolve to it (Alice: Acme plus Acme EU, both ACC001). If their orgs belong to different accounts they're ambiguous and get no single account (Frank: Globex and Umbrella). Someone with one mapped org and one unmapped org is `partially_mapped`, which also means no single account. A person's account confidence is the weakest org link behind it.

**2. Orgs (`int_org_account_resolution`)**

Every org is kept. Confidence comes from how the link was made. An org pointing at two or more accounts stays unresolved. An unmapped org like `org_nomap` is a prospect, not an error.

**3. Product activity by surface (`int_product_activity`)**

Every experiment, dataset, prompt, page view, wizard view, docs click and CLI-named key becomes one row that answers four questions:

| Question | Column | Values |
|---|---|---|
| Which surface? | `surface` | ui · sdk · cli · mcp · unknown |
| Usage or just interest? | `evidence_kind` | usage · intent |
| How sure? | `attribution`, `confidence_score` | deterministic · heuristic · none, 0–1 |
| Who acted? | `actor_type` | human · automation · unknown |

Objects are attributed to the org of their project, not to the orgs their creator belongs to, so Frank's Umbrella experiment lands on Umbrella and nowhere else. Browser events have no org at all, so they're attributed only when the person belongs to exactly one account.

A word on what `user_id` means on an object: it's the login whose session or API key made the call, not necessarily the human who acted. Bob's 12 experiments run nightly between 02:01 and 02:12 with `ci_run_id = gha-10xx` and `author_name = ci-runner`, and his key is named `ci-service`. That's a GitHub Action. So `actor_type = automation`, and Bob shows up as an `automation_identity` in `dim_members`.

**4. External resolution, the core of the CDP (`int_match_keys`, `…_match_candidates`, `…_resolution`)**

Normalisation happens once, in `int_match_keys`, which builds the keys for both sides of the join. Plain SQL, no regex and no macros. The first and last rows below are the shapes the brief calls out; the middle three are real values from the seeds:

| Raw | Key |
|---|---|
| `https://www.Acme.com/products?utm=x` | `acme.com` |
| `http://globex.io/products` | `globex.io` |
| `https://piedpiper.com/?utm_source=news` | `piedpiper.com` |
| `https://www.linkedin.com/company/pied-piper/` | `pied-piper` |
| `http://uk.linkedin.com/company/Acme-Corp/?trk=abc` | `acme-corp` |

Every variant the brief names, and the seed row that exercises it:

| Variant | Seed evidence |
|---|---|
| `http` vs `https` | sc02 `http://globex.io/products` vs sc03 `https://Initech.com` |
| with / without `www.` | sc05 `https://www.hooli.com` vs sc06 `https://hooli.com` |
| capitalised host | sc03 `https://Initech.com` |
| trailing slash | sc01 `https://www.acme.com/`, sc09 LinkedIn `…/company/pied-piper/` |
| path | sc02 `http://globex.io/products` |
| query string | sc09 `https://piedpiper.com/?utm_source=news` |
| LinkedIn with / without `www.` | sc01 `https://www.linkedin.com/…` vs sc04 `https://linkedin.com/…` |
| LinkedIn country sub-domain | **not present in the seeds.** Handled by construction: the slug is whatever sits between `/company/` and the next `/`, `?` or `#`, so the host in front of it is never read. |

Precedence and conflict rules:

1. Only a key that points at exactly one account can decide a match. `hooli.com` belongs to both Hooli and Hooli XYZ, so it can't.
2. The highest-precedence deciding key wins: LinkedIn slug, then website domain, then the LinkedIn-reported domain. LinkedIn leads because subsidiaries get their own page while they often share a domain.
3. Every other key that matched has to agree. If any key points somewhere else, it's a conflict and no account is assigned.
4. If two or more independent keys agree (distinct values, so `initech.com` appearing in two vendor fields counts once), confidence goes up by 0.05, capped at 0.99.
5. Names never decide. A name is only a suggestion for a steward. But when a name points at a *different* account than the winning key, confidence drops by 0.20 and the match is held for review, so none of its signals reach a rep until someone confirms it.

| External company | Outcome | Why |
|---|---|---|
| sc01 Acme Corporation | ✅ ACC001 · 0.95 | LinkedIn, domain and LinkedIn-domain all agree |
| sc02 Globex | ✅ ACC002 · 0.90 | LinkedIn only; the CRM account has no domain |
| sc03 Initech LLC | ✅ ACC003 · 0.85 | domain only (`initech.com` shows up in two vendor fields but counts once); no LinkedIn on the account |
| sc04 Umbrella | ✅ ACC004 · 0.95 | all keys agree |
| sc05 Hooli Inc | 🔎 ACC007 Hooli XYZ · 0.70, held for review | LinkedIn `hooli-xyz` decides, but the name points at ACC006 Hooli, so its signals wait for a steward |
| sc06 Hooli | ✅ ACC006 Hooli · 0.90 | LinkedIn `hooli` decides |
| sc08 Wayne Enterprises | ✅ ACC009 · 0.95 | LinkedIn and LinkedIn-domain agree; the website differs but claims no other account |
| sc09 PiedPiper | ✅ ACC010 · 0.95 | `?utm_source` and the trailing slash normalise away |
| sc11 Acme (dup record) | ⚠️ conflict | `acme.com` says ACC001, LinkedIn `pied-piper` says ACC010 |
| sc07 Stark Industries | ⏸ no identifiers | the name suggests ACC008, so it goes to a steward rather than a merge |
| sc10 Prospect AI | ➕ net-new prospect | valid keys, no account |

The Hooli pair is the case that settled rule 5 for me. Everything about "Hooli Inc" reads like the parent company except the one identifier that's actually unique, so the match is made but parked.

**Unresolved leaves through two doors, not one.** The brief asks that unresolved companies be kept, and none are dropped — but "kept" isn't the same as "prospected". sc10 has clean keys and simply has no account, so it's a net-new prospect. sc11 is a duplicate Acme record and sc07 has no identifiers at all: for both, an account almost certainly already exists, and putting them on a prospecting list would be a second error stacked on the first. They go to the review queue with the reason attached. `assert_every_external_company_has_one_output` checks that each of the 11 companies takes exactly one of those doors.

**5. External signals (`int_external_signals`)**

News, products and tech detections are unioned into one shape. Cross-feed duplicates are merged, so "Acme launches Acme Copilot" from the news feed and "Acme Copilot" from the product feed become a single corroborated signal. Headlines that don't name the company they're keyed to are flagged and never shown to a rep.

### UNIFIED — what people read (all views)

| View | Grain | Use it for |
|---|---|---|
| `dim_members` | person | who they are, which account, member type, evidence per surface. The `*_evidence` columns count **people only** — a CI job under someone's key shows up in `sdk_evidence_any_actor` and `sdk_usage_actor` instead, so Bob reads `no_evidence / usage_proven` |
| `fct_member_surface_activity` | person × surface | per-member activity by surface; every person × surface pair gets a row, including the empty ones |
| `fct_account_surface_adoption` | account × surface | the rollup, plus an `honest_summary` sentence that spells out what the number covers and what it leaves out. A member only counts when a person (or an unknown actor) did it; automation under their key is reported separately. `evidence_level` says at which grain the proof sits — `member`, or `org` when the only evidence is trace ingestion, which is why Initech reads `usage_proven` at 0 % of members without contradicting itself |
| `dim_signal_companies` | external company | every company, resolved or not, with its `next_action` |
| `fct_account_signals` | signal | the extension point: product and external signals in one shape |
| `account_360` | Salesforce account | the rep view — the account, how it uses the product, what's happened lately, and a ranked reason to call. `action_reasons` is ordered strongest-then-freshest, not alphabetically, so the first thing a rep reads is the best reason. Two review queues are kept apart: `external_records_pending_review` (couldn't be resolved) and `external_records_awaiting_confirmation` (resolved, but the name disagrees) |
| `net_new_prospects` | prospect | unmatched external companies plus unmapped product sign-ups |
| `rpt_resolution_quality` | metric | the resolution scorecard, recomputed on every run |

Adding a **source** (intent data, support tickets, billing events) means one more `union` branch in `fct_account_signals`. Since `account_360` takes its action reasons, headlines and review counts from that feed, and alerting or reverse-ETL would read the same place, they pick it up for free. A new **surface signal** or a new **match key** is a row in a reference CSV — and because `fct_account_surface_adoption` derives the surface list and `usage_is_measurable` from `ref_surface_signals` rather than asserting them, the day a real CLI usage signal exists, adding that row is enough to make CLI measurable.

Being precise about the limit: adding a whole new **surface** (a fifth one) also means adding its pivot columns to the three views that pivot surfaces into columns — `dim_members`, `account_360` and the surface columns of the doc page. That's a known cost of presenting surfaces as columns rather than rows; the facts underneath (`fct_member_surface_activity`, `fct_account_surface_adoption`) are already long-format and need no change.

---

## Data issues found

| # | Where | What | How it's handled |
|---|---|---|---|
| 1 | `raw_users` | `u_grace` and `u_grace_dup` share `grace@acme.com` | merged to one person, both ids kept · warn test |
| 2 | `raw_members` | `u_frank` is in Globex (ACC002) **and** Umbrella (ACC004) | person flagged ambiguous; his objects still attribute via their project |
| 3 | `raw_experiments` | all of `u_bob`'s activity is CI (`ci_run_id`, `author_name = ci-runner`, nightly 02:01–02:12, key `ci-service`) | `actor_type = automation`; Bob is an `automation_identity` |
| 4 | `raw_experiments.repo_info` | `commit_time` is `2026-07-20 00:00:00` on every row that has one, and 5 runs predate their own "commit" | treated as a placeholder and never used · warn test |
| 5 | `raw_experiments.metadata` | CI shows up three ways: `ci_run_id`, `ci: "true"` as a string, and `source: ci-daily`; `source` is free text (`lambda-prod`, `manual`) | all three recognised; free-text source is scored heuristic (0.60) |
| 6 | objects | 12 of 31 objects carry no origin information, and prompts have no metadata column at all | `surface = unknown`, never guessed as UI |
| 7 | `raw_segment_pages` | two anonymous views (`anon_x9` on `/` and `/pricing`) | excluded from attribution, counted in the scorecard |
| 8 | `raw_account_org_map` | `org_nomap` is unmapped; `org_initech` is linked only by `org_c_fallback` | prospect / low confidence 0.50 · warn test |
| 9 | `raw_salesforce_accounts` | ACC006 and ACC007 share `hooli.com`; ACC008 has no domain or LinkedIn; ACC002 has no domain; ACC003 and ACC005 have no LinkedIn; ticker stored as `NYSE:WAYN` | shared keys can't decide a match; gaps surface in `account_360.crm_identifier_gaps`; ticker split into exchange and symbol |
| 10 | `raw_signal_companies` | sc11 has Acme's domain with Pied Piper's LinkedIn; sc07 has no identifiers; sc05 is named "Hooli Inc" but links to Hooli XYZ; URLs arrive in every format | conflict, review, and LinkedIn-decides respectively; one normalising model with its output pinned by a test |
| 11 | `raw_news_events` | **n5 is keyed to Wayne (sc08) but reads "Stark Industries hires new CTO"** | `is_entity_mismatch`, never actionable · warn test |
| 12 | news × products | the same launch arrives in both feeds (Acme Copilot, Middle-Out API) | merged into one corroborated signal |
| 13 | `raw_trace_volume` | 8 days only, perfectly linear (+0.7 GB a day for every org), and no `user_id` | 7-day trend at org level only; the growth percentages sit on small bases |
| 14 | all | the data ends 2026-07-27 | windows use `var('as_of_date')`, so every run is deterministic |
| 15 | `raw_salesforce_accounts` | the brief's background names *"accounts, owners, the enterprise book"*, but the file carries only `account_id`, `account_name`, `domain`, `linkedin_company_url`, `ticker` — **no owner, no segment, no tier** | ownership and routing are out of scope; `account_360` is built so an `owner_id` is one join away, and territory/tier would drop straight into the priority rank |

---

## Tests you'd actually run

166 data tests and 2 unit tests. The ones that matter most are named so a failure explains itself:

- **Principles as tests.** `every_resolved_mapping_has_source_and_confidence`, `conflicts_are_flagged_never_resolved`, `company_name_never_decides_a_match`, `flagged_signals_never_reach_reps`.
- **No silent drops.** `no_external_company_dropped_in_resolution`, `no_org_dropped_in_account_mapping`, `account_360_has_every_salesforce_account`, `assert_no_signal_lost_between_layers`, `assert_every_external_company_has_one_output`.
- **Honesty guardrails.** `cli_and_mcp_never_claimed_as_usage`, `no_usage_percentage_for_unmeasurable_surfaces`, `assert_automation_never_counted_as_active_member`, `assert_objects_attributed_by_project_not_by_user`.
- **Confidence gates.** A signal is only actionable if the link that put it on the account is at least 0.70 (`min_attribution_confidence`); vendor news has its own bar, `min_vendor_confidence`, which gates the third-party feed's own score and nothing else. Initech's usage surge sits on a 0.50 fallback org link, so it's held for review instead of pushed to a rep.
- **The normaliser, pinned twice.** `assert_match_keys_are_normalised` holds the expected domain, LinkedIn slug and name key for all 21 real entities, read off the CSVs by hand. If a scheme, a `www.`, a trailing slash or a legal suffix ever survives, it fails.
- **Unit tests, for the cases the seeds don't contain.** Fixed inputs, fixed expected output, no seed data involved — so a refactor that still happens to fit these 21 rows still fails.
  - `match_keys_normalise_every_url_shape` feeds `int_match_keys` the exact shapes the brief names by hand, including the **LinkedIn country sub-domain that no seed row has** (`http://uk.linkedin.com/company/Acme-Corp/?trk=abc` → `acme-corp`), a port and multi-part TLD (`HTTPS://WWW.EXAMPLE.CO.UK:8443/path` → `example.co.uk`), a trailing dot, a fragment, and a name whose leading word is `the` (marked unusable rather than trusted). The CRM row and the vendor row in that test are the same company written two ways, and must come out byte-identical.
  - `resolution_precedence_and_conflict_rules` pins one row per outcome of the match ladder: LinkedIn outranking domain, +0.05 for two independent keys, conflict → no account, shared-key ambiguity, unmatched → prospect, no identifiers → enrich, and a contradicting name costing 0.20 and holding the match.
- **Honesty at the member grain.** `automation_identity_never_shown_as_a_human_user`, `human_evidence_never_exceeds_total_evidence`, `org_level_proof_never_reported_as_member_usage`, `assert_every_person_has_a_row_for_every_surface`.
- **Contracts.** Unique and not-null on every grain, relationships across every foreign key, accepted values on every enum, and 0–1 ranges on every confidence.
- **Data-quality alerts (warn).** The `dq_warn__*` tests cover issues 1, 4, 8 and 11 above.

---

## Project layout

```
gtm_cdp/
├── dbt_project.yml          layers, materializations, flags, vars (as_of_date, thresholds)
├── profiles.yml             dev = DuckDB, snowflake / prod = env vars
├── requirements.txt         dbt-core, dbt-duckdb, duckdb, markdown
├── Dockerfile               python:3.12-slim + requirements; `docker run` gives a green build
├── docker-compose.yml       the same, with the bind mount and DBT_PROFILES_DIR set
├── Makefile                 setup / build / test / docs / memo / docker / clean
├── seeds/                   ALL 21 inputs are dbt seeds
│   ├── raw/                   the 18 delivered CSVs, untouched (+ the original SEEDS_README.md)
│   ├── reference/             3 ref_* CSVs: the rules as data
│   └── _seeds.yml             seed docs + tests on the rule tables
├── macros/                  3 dialect shims, 2 as-of-date helpers, 1 schema-naming hook
├── models/raw/              18 stg_* views, in product/ crm/ signals/
├── models/cleansed/         12 int_* tables + 2 unit tests
├── models/unified/          8 views, incl. account_360
├── tests/                   4 generic + 6 singular tests
├── analyses/                eda_seed_profile.sql, what_can_we_say_about_cli.sql
├── docs/overview.html       the project report — open it in a browser
├── docs/build_lineage.py    regenerates that report's DAG from target/manifest.json
├── docs/build_report_data.py regenerates every figure in it from gtm_cdp.duckdb
├── docs/build_memo_pdf.py   renders MEMO.md -> MEMO.pdf, so the two can't disagree
├── docs/sources.production.yml   the exact diff to swap seeds for landed tables
├── MEMO.md
└── MEMO.pdf                 the memo rendered (1.5 pages), built by docs/build_memo_pdf.py
```

---

## Time spent and where I'd invest more

**Time spent:** roughly 4–6 hours — about an hour reading and profiling the seeds before writing any SQL, two to three on the models and tests, and the rest on the memo and this write-up.

If I had more time, in this order:

1. **Surface telemetry.** Stamp `client_surface` and `api_key_id` on every write (MEMO Q4). It would turn CLI and MCP from unmeasurable into deterministic, which is why it's first.
2. **A labelled match set.** The unit tests pin the *rules*; they can't tell me the rules are right. 100 to 200 steward-verified external→account pairs would let precision be measured instead of assumed, plus a small review UI for the `steward_review` and `confirm_match` queues that writes confirmed matches back.
3. **History.** Snapshot `account_360` and `fct_account_signals` daily, with dbt snapshots or incremental models. You can't learn which signals drive pipeline without knowing what a rep saw and when (MEMO Q6).
4. **Account hierarchy.** Parent and child accounts (Hooli and Hooli XYZ, Acme and Acme EU) so signals roll up without anything being merged.
5. **Delivery.** Reverse-ETL the actionable signals into Salesforce tasks or Slack, with a "wrong account / not useful" button that feeds straight back into the scorecard.
