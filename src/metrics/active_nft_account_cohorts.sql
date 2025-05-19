create or replace function ecosystem.create_active_nft_account_cohort() returns void as $$
begin
  if not exists (
    select 1 from pg_type where typname = '_active_nft_account_cohort'
    ) then
    execute 'create type ecosystem._active_nft_account_cohort as (period text, cohort timestamp, timestamp_range int8range, total bigint)';
  end if;
end;
$$ language plpgsql;

select ecosystem.create_active_nft_account_cohort();

create or replace function ecosystem.active_nft_account_cohorts(
  period text,
  start_timestamp bigint default 0,
  end_timestamp bigint default current_timestamp::timestamp9::bigint
)
returns setof ecosystem . _active_nft_account_cohort
language sql stable
as $$

with all_nft_entries as (
  select timestamp_range, account_id from nft
  where upper(timestamp_range) between start_timestamp and end_timestamp
  or lower(timestamp_range) between start_timestamp and end_timestamp
  and account_id is not null

  union all

  select timestamp_range, account_id from nft_history
  where upper(timestamp_range) between start_timestamp and end_timestamp
  or lower(timestamp_range) between start_timestamp and end_timestamp
  and account_id is not null
  ), actions as (
  -- token associations
  select
  token_account.created_timestamp as consensus_timestamp,
  account_id
  from token_account
  inner join token on token_account.token_id = token.token_id
  where token_account.created_timestamp between start_timestamp and end_timestamp
  and token.type = 'NON_FUNGIBLE_UNIQUE'

  union all

  -- received an nft
  select
  lower(timestamp_range) as consensus_timestamp,
  account_id
  from all_nft_entries

  union all

  -- sent an nft
  select
  upper(timestamp_range) as consensus_timestamp,
  account_id
  from all_nft_entries

  ), cohorts as (
  select
  distinct account_id,
  date_trunc(period, consensus_timestamp::timestamp9::timestamp) as cohort_date
  from actions
  group by 1, 2
  /* order by 1, 2 */
  ), all_cohorts as (

  select
  cohort_date as cohort,
  date_trunc(period, consensus_timestamp::timestamp9::timestamp) as period_start_timestamp,
  count(distinct actions.account_id) as total

  from actions inner join cohorts on actions.account_id = cohorts.account_id
  where consensus_timestamp::timestamp9::timestamp > cohort_date

  group by 1, 2
  order by 1, 2
  ), all_cohorts_with_range as (

  select
  period,
  cohort,
  int8range(
    period_start_timestamp::timestamp9::bigint,
    (lead(period_start_timestamp) over (order by period_start_timestamp rows between current row and 1 following))::timestamp9::bigint
  ) as timestamp_range,
  total

  from all_cohorts
)

select * from all_cohorts_with_range
where timestamp_range != 'empty'
;

$$;
-------------------------------
-- views
-------------------------------
drop materialized view if exists ecosystem.active_nft_account_cohorts;

create materialized view ecosystem.active_nft_account_cohorts as
select *
from
ecosystem.active_nft_account_cohorts('week', (date_trunc('week', now()) - interval '15 weeks')::timestamp::timestamp9::bigint);

create unique index on ecosystem.active_nft_account_cohorts(cohort, timestamp_range);

-------------------------------
-- helpers
-------------------------------
create or replace function ecosystem.active_nft_account_cohort_start_date(_row ecosystem.active_nft_account_cohorts)
returns date
language sql stable
as $$
select lower(_row.timestamp_range)::timestamp9::date;
$$;

create or replace function ecosystem.active_nft_account_cohort_end_date(_row ecosystem.active_nft_account_cohorts)
returns date
language sql stable
as $$
select upper(_row.timestamp_range)::timestamp9::date;
$$;
