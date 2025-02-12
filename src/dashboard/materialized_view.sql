-- drop materialized view if exists ecosystem.hashgraph_dashboard;

-- create materialized view ecosystem.hashgraph_dashboard as (
--   with accounts as (
--     select
--       ecosystem.dashboard_active_accounts('7 days') as accounts_7,
--       ecosystem.dashboard_active_accounts('30 days') as accounts_30,
--       ecosystem.dashboard_active_accounts('90 days') as accounts_90,
--   ), developers as (
--     select
--       ecosystem.dashboard_active_developer_accounts('7 days') as developer_7,
--       ecosystem.dashboard_active_developer_accounts('14 days') as developer_14,
--       ecosystem.dashboard_active_developer_accounts('30 days') as developer_30,
--       ecosystem.dashboard_active_developer_accounts('60 days') as developer_60,
--       ecosystem.dashboard_active_developer_accounts('90 days') as developer_90,
--       ecosystem.dashboard_active_developer_accounts('180 days') as developer_180
--   ), contracts as (
--     select
--       ecosystem.dashboard_active_contracts('7 days') as contracts_7,
--       ecosystem.dashboard_active_contracts('14 days') as contracts_14,
--       ecosystem.dashboard_active_contracts('30 days') as contracts_30,
--       ecosystem.dashboard_active_contracts('60 days') as contracts_60,
--       ecosystem.dashboard_active_contracts('90 days') as contracts_90,
--       ecosystem.dashboard_active_contracts('180 days') as contracts_180
--   ), revenue as (
--     select
--       ecosystem.dashboard_revenue('7 days') as revenue_7,
--       ecosystem.dashboard_revenue('14 days') as revenue_14,
--       ecosystem.dashboard_revenue('30 days') as revenue_30,
--       ecosystem.dashboard_revenue('60 days') as revenue_60,
--       ecosystem.dashboard_revenue('90 days') as revenue_90,
--       ecosystem.dashboard_revenue('180 days') as revenue_180
--   )

--   select * from accounts, developers, contracts, revenue
-- );
create materialized view ecosystem.hashgraph_dashboard as (
    with accounts as (
        select
            total as accounts_7,
            previous_total as accounts_7_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_7_growth
        from ecosystem.dashboard_active_accounts('7 days'),
        select
            total as accounts_30,
            previous_total as accounts_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_30_growth
        from ecosystem.dashboard_active_accounts('30 days'),
        select
            total as accounts_90,
            previous_total as accounts_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_90_growth
        from ecosystem.dashboard_active_accounts('90 days')
    ), contracts as (
        select
            total as contracts_7,
            previous_total as contracts_7_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_7_growth
        from ecosystem.dashboard_active_contracts('7 days'),
        select
            total as contracts_30,
            previous_total as contracts_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_30_growth
        from ecosystem.dashboard_active_contracts('30 days'),
        select
            total as contracts_90,
            previous_total as contracts_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_90_growth
        from ecosystem.dashboard_active_contracts('90 days')
    )

    select * from accounts, contracts
);
