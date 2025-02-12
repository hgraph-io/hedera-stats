-- drop materialized view if exists ecosystem.hashgraph_dashboard;
create materialized view ecosystem.hashgraph_dashboard as (
    with accounts as (
      select * from (
        select
            total as accounts_7,
            previous_total as accounts_7_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_7_growth
        from ecosystem.dashboard_active_accounts('7 days')
      ), (
        select
            total as accounts_30,
            previous_total as accounts_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_30_growth
        from ecosystem.dashboard_active_accounts('30 days')
      ), (
        select
            total as accounts_90,
            previous_total as accounts_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as accounts_90_growth
        from ecosystem.dashboard_active_accounts('90 days')
      )

    ), developers as (
      select * from (
        select
            total as developers_7,
            previous_total as developers_7_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as developers_7_growth
        from ecosystem.dashboard_active_developer_accounts('7 days')
      ), (
        select
            total as developers_30,
            previous_total as developers_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as developers_30_growth
        from ecosystem.dashboard_active_developer_accounts('30 days')
      ), (
        select
            total as developers_90,
            previous_total as developers_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as developers_90_growth
        from ecosystem.dashboard_active_developer_accounts('90 days')
      )
    ), retail as (
      select * from (
        select
          (accounts_7 - developers_7) / (accounts_7_previous - developers_7_previous)
        as retail_90
        from accounts, developers
      ), (
        select
          (accounts_7 - developers_7) / (accounts_7_previous - developers_7_previous)
          / (accounts_7_previous - developers_7_previous) * 100 as retail_7_growth
        from accounts, developers
      ), (
        select
          (accounts_30 - developers_30) / (accounts_30_previous - developers_30_previous)
          / (accounts_30_previous - developers_30_previous) * 100 as retail_30_growth
        from accounts, developers
      ), (
        select
          (accounts_90 - developers_90) / (accounts_90_previous - developers_90_previous)
          / (accounts_90_previous - developers_90_previous) * 100 as retail_90_growth
        from accounts, developers
      )
    ), contracts as (
      select * from (
        select
            total as contracts_7,
            previous_total as contracts_7_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_7_growth
        from ecosystem.dashboard_active_contracts('7 days')
      ), (
        select
            total as contracts_30,
            previous_total as contracts_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_30_growth
        from ecosystem.dashboard_active_contracts('30 days')
      ), (
        select
            total as contracts_90,
            previous_total as contracts_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as contracts_90_growth
        from ecosystem.dashboard_active_contracts('90 days')
      )
    ), revenue as (
      select * from (
        select
            total as revenue_7,
            previous_total as revenue_7_previous,
            (total::decimal - previous_total) / previous_total
            * 100 as revenue_7_growth
        from ecosystem.dashboard_revenue('7 days')
      ), (
        select
            total as revenue_30,
            previous_total as revenue_30_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as revenue_30_growth
        from ecosystem.dashboard_revenue('30 days')
      ), (
        select
            total as revenue_90,
            previous_total as revenue_90_previous,
            (total::decimal - previous_total)
            / previous_total
            * 100 as revenue_90_growth
        from ecosystem.dashboard_revenue('90 days')
      )
    )
    select * from accounts, developers, retail, contracts, revenue
);
