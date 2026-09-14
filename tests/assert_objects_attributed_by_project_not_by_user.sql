/*
  Objects belong to the org of their PROJECT, never to whichever org the
  user happens to be in. Frank is in Globex and Umbrella; his experiment in
  p_umbrella1 must land on Umbrella's account. Returns misattributed rows.
*/
select a.activity_id, a.account_id, o.account_id as expected_account_id
from {{ ref('int_product_activity') }} as a
inner join {{ ref('stg_product__projects') }} as p on a.project_id = p.project_id
inner join {{ ref('int_org_account_resolution') }} as o on p.org_id = o.org_id
where o.account_id is not null
  and coalesce(a.account_id, '<null>') <> o.account_id
