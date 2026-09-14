# Take-Home Seeds — Lightweight CDP

18 CSVs mirroring a slice of our real Snowflake schema (synthetic data), in three groups. Load them as dbt seeds.

## Load into dbt

1. Copy every `raw_*.csv` into your dbt project's `seeds/` directory.
2. `dbt seed`, then build your models on top. `dbt build` should pass.

`repo_info` / `metadata` are JSON stored as text — parse in staging (`try_parse_json` on Snowflake, `::json` / DuckDB `json`). Empty string = absent/null. Read the data before modeling it; grains, formats, and populated-ness vary on purpose.

## Group 1 — Product usage (internal)
| Table | Grain |
|---|---|
| `raw_users` | one per user (`user_id`, `email`) |
| `raw_members` | user↔org (many-to-many) |
| `raw_organizations` | one per org (`plan`) |
| `raw_projects` | one per project (→ org) |
| `raw_experiments` | one per experiment — has `repo_info` (JSON, nullable) + `metadata` |
| `raw_datasets` | one per dataset — has `metadata` |
| `raw_prompts` | one per prompt |
| `raw_segment_pages` | web UI page views (`user_id` nullable) |
| `raw_cli_wizard` | CLI-setup events (browser) |
| `raw_docs_mcp_events` | docs "install/copy MCP" clicks (browser) |
| `raw_api_keys` | one per API key (`key_hash` only — no secret) |
| `raw_trace_volume` | **org × day** ingestion GB (no `user_id`) |

## Group 2 — CRM (Salesforce)
| Table | Notes |
|---|---|
| `raw_salesforce_accounts` | `account_id`, `account_name`, `domain` (**some null**), `linkedin_company_url` (**some null**), `ticker` |
| `raw_account_org_map` | org → account (`mapping_source`); not every org is mapped |

## Group 3 — External signals (third-party intelligence)
Signals key to `raw_signal_companies` by `company_id`. That company table's **only** identifiers are a messy website URL, a LinkedIn URL, and a LinkedIn domain — there is **no Salesforce id**. You resolve it.

| Table | Grain |
|---|---|
| `raw_signal_companies` | one per external company — `company_website` (full URL), `linkedin_url`, `linkedin_domain` |
| `raw_news_events` | one per news event (→ company_id, `confidence`, `found_at`) |
| `raw_products` | one per detected product (→ company_id) |
| `raw_tech_detections` | one per tech detection (→ company_id) |
