-- RAW layer: one row per project; a project belongs to exactly one org.
select
    nullif(trim(project_id), '')        as project_id,
    nullif(trim(org_id), '')            as org_id,
    nullif(trim(name), '')              as project_name
from {{ ref('raw_projects') }}
