/*
  "What % of the account is using the CLI?"  (MEMO Q3)

  Compile with:  dbt compile -s what_can_we_say_about_cli
  Then run the SQL in target/compiled/... against the warehouse.

  This is the answer we CAN give: intent per account, clearly labelled, next
  to what we can say about code-based usage (SDK, which may include CLI).
*/
select
    cli.account_id,
    cli.account_name,
    cli.known_members                                        as known_product_members,
    'not measurable'                                         as cli_usage,
    cli.members_intent_only                                  as members_with_cli_setup_intent,
    cli.members_with_unattributed_signals                    as intent_from_multi_account_members_not_counted,
    sdk.members_usage_proven                                 as members_with_code_based_usage_sdk_or_cli,
    cli.honest_summary
from {{ ref('fct_account_surface_adoption') }} as cli
inner join {{ ref('fct_account_surface_adoption') }} as sdk
    on cli.account_id = sdk.account_id and sdk.surface = 'sdk'
where cli.surface = 'cli'
  and cli.known_members > 0
order by cli.account_id
