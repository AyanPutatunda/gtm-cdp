# GTM Intelligence Platform

A lightweight customer data platform built on dbt. It takes **product usage**, **Salesforce** and a **third-party company feed** — three systems with no key in common — and resolves them into one account-level view a sales rep can work from.

Runs on a local DuckDB file. **No warehouse, no credentials, no cloud account.** The same code targets Snowflake through three dialect shims.

📊 **[`docs/overview.html`](docs/overview.html) is the full project report** — problem, data provided, exploratory analysis, model-by-model results, and the memo.

> **Open it in a browser, not on GitHub.** GitHub serves `.html` files as source text, so clicking the link above from github.com shows the markup rather than the page. Clone or download the repo and open the file locally:
> ```bash
> git clone https://github.com/AyanPutatunda/gtm-cdp.git
> open gtm-cdp/docs/overview.html        # macOS · Linux: xdg-open · Windows: start
> ```
> It is self-contained — no build step, no server, no internet needed.

Everything below is how to run the project yourself.

---

## Highlights

**An unresolved mapping beats a bad merge.** That line from the brief drove every design decision. Nothing here matches on a similarity score. Where evidence disagrees, the record goes to a review queue with the reason attached instead of a winner being picked.

| | |
|---|---|
| **Honest about what the data can't prove** | No column in the 18 files records a client, user agent or API key id, so **CLI and MCP usage is not measurable** — only intent. That's enforced by a test (`cli_and_mcp_never_claimed_as_usage`) that fails the build, not a footnote. |
| **Unresolved leaves through two doors** | Clean keys and no account → net-new prospect. A conflict or no identifiers at all → review queue, because an account probably already exists and prospecting it would compound the error. A test proves each company takes exactly one door. |
| **Judgement calls are data, not SQL** | Match precedence, surface confidence and org-mapping trust each live in a reference CSV. Changing what the platform believes is a reviewable diff, not a model rewrite. |
| **One normaliser, one definition per number** | `int_match_keys` builds the CRM keys and vendor keys in the same CTEs, so they cannot drift. Trace growth lives in one model and is read three times. |
| **Machine vs. human kept separate** | 12 nightly CI runs under a member's key prove the *account* uses the SDK, but never make that person an active user. |
| **Tests assert principles, not just shapes** | 166 data tests + 2 unit tests. The interesting ones are named so a failure explains itself: `conflicts_are_flagged_never_resolved`, `company_name_never_decides_a_match`, `org_level_proof_never_reported_as_member_usage`. |
| **The report generates itself** | The lineage diagram is read from dbt's `target/manifest.json`; every figure is read back out of the built warehouse. Nothing on the page is hand-typed. |

**Architecture:** `raw` (18 typed staging views) → `cleansed` (12 intermediate tables, in four passes: compare → relate → decide → classify) → `unified` (8 marts).

---

## Data issues found

The brief asks what data issues turned up. Fifteen. Four are wired to `warn`-severity tests rather than silenced, so they resurface in **every** run — that's why a green build reports `WARN=4`.

| # | Where | What | How it's handled |
|---|---|---|---|
| 1 | `raw_users` | `u_grace` and `u_grace_dup` share `grace@acme.com` | Merged to one person, both ids kept · **warn test** |
| 2 | `raw_members` | `u_frank` is in Globex (ACC002) **and** Umbrella (ACC004) | Person flagged ambiguous; his objects still attribute via their project |
| 3 | `raw_experiments` | All of `u_bob`'s activity is CI — nightly 02:01–02:12, `author_name = ci-runner`, key `ci-service` | `actor_type = automation`; Bob becomes an `automation_identity` |
| 4 | `raw_experiments.repo_info` | `commit_time` is `2026-07-20 00:00:00` on every row, and 5 runs predate their own "commit" | Treated as a placeholder, never used downstream · **warn test** |
| 5 | `raw_experiments.metadata` | CI appears three ways: `ci_run_id`, `ci: "true"` as a string, `source: ci-daily`. `source` is free text | All three recognised; free-text source scored heuristic (0.60) |
| 6 | objects | 12 of 31 carry no origin information; `raw_prompts` has no metadata column at all | `surface = unknown`, never guessed as UI |
| 7 | `raw_segment_pages` | Two anonymous views (`anon_x9`) with no user | Excluded from attribution, counted in the scorecard so the gap stays visible |
| 8 | `raw_account_org_map` | `org_nomap` unmapped; `org_initech` linked only by `org_c_fallback` | Prospect / confidence 0.50 — which is why Initech's usage surge is held · **warn test** |
| 9 | `raw_salesforce_accounts` | ACC006 and ACC007 share `hooli.com`; ACC008 has neither domain nor LinkedIn; ticker stored as `NYSE:WAYN` | Shared keys can't decide a match; gaps surface in `crm_identifier_gaps`; ticker split into exchange + symbol |
| 10 | `raw_signal_companies` | sc11 has Acme's domain with Pied Piper's LinkedIn; sc07 has no identifiers; sc05 is named "Hooli Inc" but links to Hooli XYZ; URLs arrive in 7 formats | Conflict, review, and LinkedIn-decides respectively; one normalising model, output pinned by a test |
| 11 | `raw_news_events` | **n5 is keyed to Wayne (sc08) but reads "Stark Industries hires new CTO"** | `is_entity_mismatch`, never actionable, never shown as latest headline · **warn test** |
| 12 | news × products | The same launch arrives in both feeds (Acme Copilot, Middle-Out API) | Merged into one corroborated signal rather than counted twice |
| 13 | `raw_trace_volume` | 8 days only, perfectly linear at +0.7 GB/day for every org, and no `user_id` | 7-day trend at org level only; growth percentages sit on small bases and the report says so |
| 14 | all | The data ends `2026-07-27` | Windows use `var('as_of_date')`, so every run is deterministic |
| 15 | `raw_salesforce_accounts` | The brief names *"accounts, **owners**, the enterprise book"*, but the file has no owner, segment or tier column | Ownership and routing are out of scope; `account_360` is built so an `owner_id` is one join away |

---

# Replication

Three ways to run it. **Pick one.** All produce the same result.

| Path | You need | First run | After |
|---|---|---|---|
| **[A · Docker](#a--docker)** | Docker, nothing else | ~90s | ~10s |
| **[B · Python venv](#b--python-venv)** | Python 3.10+ | ~60s | ~5s |
| **[C · Snowflake](#c--snowflake)** | credentials | — | — |

Whichever you use, the last line should read:

```
Done. PASS=223 WARN=4 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=227
```

> **`WARN=4` is correct.** Those are the four data-quality alerts from the table above. **`ERROR=0` is the thing to check.**

---

## Step 0 · Get the project

```bash
git clone https://github.com/AyanPutatunda/gtm-cdp.git
cd gtm-cdp
```

Or unzip the archive and `cd` into it. Confirm you're in the right place:

```bash
ls
```

You should see `dbt_project.yml`, `seeds/`, `models/`, `Dockerfile`, `requirements.txt`.

Every command below runs from this directory.

---

## A · Docker

Nothing to install but Docker. The image pins `python:3.12-slim`.

### A1. Build the image

```bash
docker build -t gtm-cdp .
```

Takes about 90 seconds, mostly `pip install`. Ends with `naming to docker.io/library/gtm-cdp:latest`.

### A2. Run the pipeline

```bash
docker run --rm -v "$PWD:/app" gtm-cdp
```

That's the whole thing. Expect `PASS=223 WARN=4 ERROR=0`.

The `-v "$PWD:/app"` bind mount is what puts `gtm_cdp.duckdb`, `target/` and `logs/` back on your machine. Drop it and you get a throwaway container that just proves the build is green:

```bash
docker run --rm gtm-cdp
```

### A3. Run other commands in the container

Use Compose — it sets the mount and `DBT_PROFILES_DIR` for you:

```bash
docker compose run --rm dbt                                   # full build (default)
docker compose run --rm dbt dbt test                          # tests only
docker compose run --rm dbt dbt show -s account_360 --limit 10
docker compose run --rm dbt python docs/build_lineage.py      # regenerate the report's DAG
docker compose run --rm dbt bash                              # shell inside the image
```

### A4. Notes

- **Linux:** files written through the mount are owned by `root`. Add `--user "$(id -u):$(id -g)"` if that matters. macOS and Windows Docker Desktop map ownership for you.
- **Partial parsing is off** in `dbt_project.yml`, on purpose. dbt's parse cache stores *absolute* paths, so without that flag a container run and a venv run over the same directory poison each other's cache and every seed fails with `No files found that match the pattern /Users/...`. This project parses in well under a second, so the cache buys nothing.

---

## B · Python venv

### B1. Check your Python version

```bash
python3 --version
```

**Must be 3.10 or newer** — `dbt-core` and `dbt-duckdb` both declare `requires-python >= 3.10`. Anything from 3.10 up works, including 3.14 (verified).

If yours is older, point the venv at a newer one: `python3.12 -m venv .venv`, or `uv venv --python 3.12 .venv` if you have `uv`.

### B2. Create the virtualenv and install

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

That installs `dbt-core`, `dbt-duckdb`, plus `duckdb` and `markdown` for the doc generators.

### B3. Point dbt at the shipped profile

```bash
export DBT_PROFILES_DIR=.
```

`profiles.yml` ships in the project root. The default target is a local **DuckDB file** at `gtm_cdp.duckdb` — no warehouse, no credentials.

### B4. Verify the connection

```bash
dbt debug
```

Expect `Connection test: OK connection ok` and `All checks passed!`.

### B5. Build everything

```bash
dbt build
```

`build` interleaves seeds → models → tests in DAG order, so a broken key fails *before* anything downstream is computed. Expect:

```
Finished running 21 seeds, 12 table models, 166 data tests, 2 unit tests, 26 view models
Done. PASS=223 WARN=4 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=227
```

### B6. Or run the stages one by one

If you'd rather watch it happen in pieces:

```bash
dbt seed     # load the 21 CSVs        -> PASS=21  WARN=0 ERROR=0 TOTAL=21
dbt run      # build the 38 models     -> PASS=38  WARN=0 ERROR=0 TOTAL=38
dbt test     # run all 168 tests       -> PASS=164 WARN=4 ERROR=0 TOTAL=168
```

`dbt build` is preferred because the split version tests everything only at the very end, after the whole pipeline has already run on possibly-bad data.

### B7. Useful selectors

```bash
dbt build -s tag:cleansed          # just the transformation layer and its tests
dbt build -s +account_360          # the rep view and every ancestor it needs
dbt build -s int_match_keys+       # the normaliser and everything downstream (blast radius)
dbt test -s tag:unified            # the business-facing assertions on their own
dbt ls --resource-type model       # list all models
```

### B8. Or use the Makefile

Picks a suitable interpreter, sets `DBT_PROFILES_DIR`, and needs no activation:

```bash
make setup      # create .venv and install requirements.txt
make build      # dbt build           -> PASS=223 WARN=4 ERROR=0
make test       # dbt test            -> PASS=164 WARN=4 ERROR=0
make docs       # rebuild + regenerate docs/overview.html
make memo       # render MEMO.md -> MEMO.pdf (needs Chrome)
make docker     # build the image and run dbt inside it
make clean      # remove target/, logs/ and the .duckdb file (keeps .venv)
make help       # list all targets
```

---

## Querying the DuckDB database

After a build, `gtm_cdp.duckdb` sits in the project root with three schemas:

| Schema | Contents |
|---|---|
| `raw` | 21 loaded seeds + 18 typed staging views |
| `cleansed` | 12 intermediate tables — where the resolution happens |
| `unified` | 8 marts — what people read |

The eight objects worth querying:

```
unified.account_360                     one row per Salesforce account — the rep view
unified.fct_account_signals             every signal in one shape
unified.fct_account_surface_adoption    account × surface adoption
unified.fct_member_surface_activity     person × surface activity
unified.dim_members                     one row per person
unified.dim_signal_companies            every external company + how it resolved
unified.net_new_prospects               companies with no CRM account
unified.rpt_resolution_quality          19 resolution metrics
```

### Option 1 · Python (no extra install — `duckdb` is in `requirements.txt`)

```bash
python -c "import duckdb; duckdb.connect('gtm_cdp.duckdb').sql('select account_name, priority_rank, action_reasons from unified.account_360 order by priority_rank').show(max_width=200)"
```

For anything multi-line, use a heredoc — it avoids shell quote-escaping entirely:

```bash
python <<'EOF'
import duckdb
con = duckdb.connect('gtm_cdp.duckdb', read_only=True)
con.sql("""
  select account_id, known_members, members_intent_only, pct_members_usage_proven
  from unified.fct_account_surface_adoption
  where surface = 'cli' and known_members > 0
  order by account_id
""").show(max_width=200)
EOF
```

### Option 2 · DuckDB CLI

```bash
brew install duckdb          # macOS. Or: https://duckdb.org/docs/installation/
duckdb gtm_cdp.duckdb
```

Then at the `D` prompt:

```sql
.tables
select * from unified.rpt_resolution_quality order by metric_order;
.quit
```

Or one-shot, without entering the shell:

```bash
duckdb gtm_cdp.duckdb -c "select * from unified.rpt_resolution_quality order by metric_order"
```

### Option 3 · Through dbt

```bash
dbt show -s account_360 --limit 10
dbt show --inline "select account_name, priority_rank, action_reasons from {{ ref('account_360') }} order by priority_rank"
```

### Queries worth running first

**The rep view — who to call and why:**

```sql
select account_name, priority_rank, action_reasons
from unified.account_360 order by priority_rank;
```

**How the external feed resolved** — 8 resolved, 1 conflict, 1 unmatched, 1 with no identifiers:

```sql
select company_id, company_name, resolution_status, account_id,
       match_method, match_confidence, next_action
from cleansed.int_signal_company_resolution order by company_id;
```

**The honesty check** — CLI usage is `null`, never `0`, because absent evidence is not evidence of absence:

```sql
select account_id, surface, known_members, members_usage_proven,
       members_intent_only, pct_members_usage_proven, evidence_level, honest_summary
from unified.fct_account_surface_adoption
where surface = 'cli' and known_members > 0;
```

**Resolution scorecard** — the 19 metrics behind the memo:

```sql
select area, metric, numerator, denominator, rate
from unified.rpt_resolution_quality order by metric_order;
```

**Net-new prospects** — an output, not an error:

```sql
select * from unified.net_new_prospects;
```

---

## Confirming it reproduced

Beyond `ERROR=0`, three checks. These are the numbers the report and memo argue from:

| # | Check | How | Expected |
|---|---|---|---|
| 1 | Build | `dbt build` | `PASS=223 WARN=4 ERROR=0 ... TOTAL=227` |
| 2 | Node counts | in the run summary | `21 seeds, 12 table models, 166 data tests, 2 unit tests, 26 view models` |
| 3 | External resolution | query below | 8 resolved, 1 conflict, 1 unmatched, 1 no_identifiers |

```bash
duckdb gtm_cdp.duckdb -c "select resolution_status, count(*) from cleansed.int_signal_company_resolution group by 1 order by 2 desc"
```

---

## Regenerating the report

`docs/overview.html` takes its lineage from dbt's manifest and its figures from the built warehouse, so after any change:

```bash
source .venv/bin/activate && export DBT_PROFILES_DIR=.

dbt build                          # must run first — the generators read its output
python docs/build_lineage.py       # nodes, layers, passes and edges from target/manifest.json
python docs/build_report_data.py   # every figure, from gtm_cdp.duckdb
python docs/build_memo_pdf.py      # MEMO.md -> MEMO.pdf (needs Chrome installed)
```

`make docs` runs the first three in order. Both generators fail loudly rather than silently writing a stale page: `build_lineage.py` errors if a model has no description, and refuses to run without `target/manifest.json`.

To browse dbt's own lineage graph and column docs instead:

```bash
dbt docs generate && dbt docs serve
```

---

## C · Snowflake

The same code runs on Snowflake. `macros/cross_db.sql` holds three shims for the syntax that genuinely differs — JSON extraction, list aggregation, one keyword column name — plus two as-of-date helpers. Everything else is plain SQL.

```bash
pip install "dbt-snowflake>=1.9"

export SNOWFLAKE_ACCOUNT=...  SNOWFLAKE_USER=...  SNOWFLAKE_PASSWORD=...
export SNOWFLAKE_ROLE=TRANSFORMER  SNOWFLAKE_WAREHOUSE=TRANSFORMING  SNOWFLAKE_DATABASE=GTM_CDP

dbt build --target snowflake     # dev  -> DEV_RAW / DEV_CLEANSED / DEV_UNIFIED
dbt build --target prod          # prod -> RAW / CLEANSED / UNIFIED
```

Dev targets get a schema prefix on purpose (`macros/generate_schema_name.sql`), so a dev run cannot overwrite production. To use today's date instead of the frozen snapshot: `--vars '{as_of_date: today}'`.

> **Stated plainly:** `dbt build` passes end to end on DuckDB — verified on dbt-core 1.12.4 with dbt-duckdb 1.11.0, in a venv and in the Docker image. For Snowflake the project compiles and every compiled file passes a Snowflake-dialect syntax check, but I had no live Snowflake account to run it against.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `pip install` fails on dbt | Python older than 3.10 | `python3.12 -m venv .venv`, or use Docker |
| `command not found: dbt` | venv not activated | `source .venv/bin/activate` |
| `Could not find profile named 'gtm_cdp'` | dbt can't see `profiles.yml` | `export DBT_PROFILES_DIR=.` from the project root |
| `No files found that match the pattern /Users/...` on every seed | Stale cross-environment parse cache | `rm -rf target/` and re-run. Shouldn't happen — `partial_parse` is off |
| `gtm_cdp.duckdb not found` from a doc generator | Never built | Run `dbt build` first |
| `WARN=4` | **Not a problem** | The four intentional data-quality alerts |

---

## Project layout

```
gtm_cdp/
├── dbt_project.yml            layers, materializations, flags, vars
├── profiles.yml               dev = DuckDB, snowflake / prod = env vars
├── requirements.txt           dbt-core, dbt-duckdb, duckdb, markdown
├── Dockerfile                 python:3.12-slim + requirements
├── docker-compose.yml         the same, with bind mount + DBT_PROFILES_DIR
├── Makefile                   setup / build / test / docs / memo / docker / clean
├── seeds/
│   ├── raw/                     the 18 delivered CSVs, untouched
│   └── reference/               3 ref_* CSVs — the rules as data
├── models/
│   ├── raw/                     18 stg_* views (product / crm / signals)
│   ├── cleansed/                12 int_* tables + 2 unit tests
│   └── unified/                 8 marts, incl. account_360
├── macros/                    3 dialect shims, 2 date helpers, 1 schema hook
├── tests/                     4 generic + 6 singular tests
├── analyses/                  eda_seed_profile.sql, what_can_we_say_about_cli.sql
├── docs/
│   ├── overview.html            the project report
│   ├── build_lineage.py         regenerates its DAG from target/manifest.json
│   ├── build_report_data.py     regenerates its figures from gtm_cdp.duckdb
│   ├── build_memo_pdf.py        MEMO.md -> MEMO.pdf
│   └── sources.production.yml   the exact diff to swap seeds for landed tables
├── MEMO.md                    the six memo questions, answered
└── MEMO.pdf                   the memo, rendered
```

---

## Time spent, and where I'd invest more

**Roughly 4–6 hours** — about an hour profiling the seeds before writing any SQL, two to three on the models and tests, and the rest on the memo and write-up.

### Fix the foundations first

1. **Surface telemetry.** Stamp `client_surface` and `api_key_id` on every write at the API gateway. It turns CLI and MCP from unmeasurable into deterministic, which is why it's first.
2. **A labelled match set.** 100–200 steward-verified external→account pairs, so resolution precision is measured rather than asserted, plus a small review UI for the two queues that writes confirmed matches back.
3. **History.** Snapshot `account_360` and `fct_account_signals` daily. Without it, "which signals actually drive pipeline" cannot be answered at all.
4. **Account hierarchy.** Parent and child, so Hooli and Hooli XYZ roll up without anything being merged.
5. **Delivery.** Reverse-ETL into Salesforce tasks or Slack, with a "wrong account" button feeding straight back into the scorecard.

### Then the interface: conversational analytics

Reps and GTM leaders do not write SQL, and a dashboard only answers questions someone anticipated. The natural next surface is **asking the 360 a question in plain language** — but only on top of the layers below, in this order. Doing it earlier produces a confident hallucination machine.

6. **A semantic layer over the marts.** Metrics defined once, with their grain, valid filters and caveats attached: `active_members` (people, never automation), `cli_intent_rate` (denominator = product members, *not* headcount), `trace_growth_7d` (org-level only). dbt's own Semantic Layer / MetricFlow fits, since the marts are already single-grain and the honesty rules already exist as columns — `evidence_level`, `usage_is_measurable`, `honest_summary`. This is the piece that makes everything after it safe.

7. **Text-to-SQL grounded in that layer**, not in the raw schema. The model picks *metrics and dimensions*, never writes free-form SQL against 39 raw tables. That constrains the output space enough to be reliable, keeps every answer traceable to a definition someone reviewed, and means a metric change propagates to the assistant automatically.

8. **Expose it over MCP.** One server publishing the semantic layer as tools — `query_metric`, `describe_account`, `list_signals` — so the same grounded surface works from Claude, an internal Slack bot, or a rep's IDE without three separate integrations. Each tool returns the caveat alongside the number, because `honest_summary` travels with the row rather than being reattached by the caller.

9. **The guardrail is the whole point.** Ask this platform *"what % of the account is using the CLI?"* and the honest answer is that no such number exists — that is the memo's Q3. An ungrounded text-to-SQL bot will happily invent one by counting `cli_setup_wizard` rows. So the semantic layer has to carry refusals as first-class objects: `cli_usage` is defined as **unmeasurable**, and the assistant returns *"CLI usage is not measurable from this data; here is CLI setup intent instead, at 33% of 3 known members at Globex."*

10. **Evaluate the agent the way we evaluate the pipeline — with Braintrust, and continuously.** This is the part that makes 6–9 an actual product rather than a demo, and it dogfoods nicely: the seeds themselves describe experiments, datasets, prompts, evals and traces, so the agent built on this data gets judged by the same discipline the data is about.

### How that eval loop works

**The dbt tests are already the spec.** Every honesty rule that fails the build today is a scorer waiting to be written. `cli_and_mcp_never_claimed_as_usage` and `no_usage_percentage_for_unmeasurable_surfaces` are assertions about *the data*; the agent needs the same assertions about *its answers*.

**Offline first — a golden question set as a Braintrust dataset.** Seed it from the six memo questions and every trap in the data: the CLI percentage that must be refused, Initech's `usage_proven` at 0% of members, the Hooli pair, the mis-keyed Wayne headline, Frank's two accounts, Bob's CI runs. Five scorers, most of them deterministic rather than LLM-judged:

| Scorer | Type | Asks |
|---|---|---|
| `refusal_correctness` | binary, coded | Does it refuse the unmeasurable, and *only* the unmeasurable? Both directions matter — a bot that refuses everything scores well on honesty and is useless. |
| `numeric_accuracy` | exact match | Does the number equal what the warehouse returns for that metric? |
| `caveat_retention` | LLM judge | Does the answer carry the denominator and the `evidence_level`, or does it strip them? |
| `grounded_attribution` | coded | Does it cite the metric and model it came from, so the answer is checkable? |
| `no_invented_entities` | coded | Does it mention only accounts, companies and people that exist? |

Ground truth stays current for free, because it is generated the same way this report is. `docs/build_report_data.py` already reads expected values out of the built warehouse; pointing it at the eval fixtures means **the expected answers rebuild whenever the data does**, so the golden set can never quietly go stale against the models.

**Then online.** Offline evals only cover questions someone thought of. Log every production call through Braintrust and score a sample continuously with the reference-free scorers — `refusal_correctness`, `caveat_retention`, `grounded_attribution` all work without a known answer. Alert on the trend, not the incident: a slow slide in caveat retention after a prompt change is the failure mode that ships quietly.

**Then self-improving, with a hard floor.** Production failures and every rep's "that's wrong" become new rows in the golden set, so the regression suite grows from real misuse rather than imagination. Prompt and semantic-layer changes ship as Braintrust experiments compared against the current baseline. The honesty scorers are gated at **100%** — a version that trades one refusal for better fluency does not ship, however good the aggregate looks. Everything else is a judgement call about score deltas; that one is not.

**And it has to survive change.** New source, changed metric definition, re-run seeds: the eval suite runs in CI right after `dbt build`, because a semantic change is exactly as capable of breaking an answer as a prompt change is. Adding a fourth signal source is one `union` branch in `fct_account_signals` — and one new set of eval cases, or the agent will confidently answer questions about it having never been tested on it.

The sequencing matters more than the components. A conversational surface built on the marts as they stand would be impressive in a demo and untrustworthy in a QBR — and without step 10 there is no way to know which one you have.
