# Hedera Stats Workflow

This document outlines the process for effectively managing and updating Hedera Stats, focusing on creating, integrating, testing, formalizing, and publishing new statistics functions. For those curious, this is our internal workflow.

## Tools

- `pg_cron`
- `pg_activity`
- `psql`

## General Guidelines

Follow these guidelines throughout the workflow:

- Restrict the scope to the `ecosystem_metric` table.
- Verify that the documented methodology matches the logic implemented in the functions.
- Always perform updates on testnet before applying them to mainnet.
- Understand reversion procedures before making any changes.
- Monitor jobs closely to avoid overwhelming the nodes.
- Name functions using `lowercase_snake_case` format.

## Create New Functions (Stats)

_Functions perform data computation in-line with methodologies. This step finds the data and attempts to get the desired outputs._

**Connect to Hedera Stats database:**

```bash
psql -h <host> -p <port> -U <user> -d <database>
```

_Note: You will need to host your own mirror node._

1. Determine data availability using a probing query.

   - If data is unavailable, escalate to the engineering team.
   - If data is available, save the query for reference.

2. Name the new function as `statistic_name`.

3. Create a description & methodology for the new function.

4. Compose the SQL script and logic for the function.

5. Test the function:

   - Paste the function into an executable environment.
   - Update the function and check for any error outputs.
   - Test results with the following query (replace `<statistic_name>` accordingly):

     ```sql
     SELECT
       lower(int8range)::timestamp9,
       upper(int8range)::timestamp9,
       total
     FROM
       ecosystem.<statistic_name>(
         'day',
         (now() - INTERVAL '7 days')::timestamp9::bigint
       );
     ```

   - Verify outputs for all required periods (e.g., hourly, daily).

6. Save the function as a SQL file.

## Integrate New Functions (Stats)

_This step focuses on adding new functions to the repository._

1. Review the SQL file for the new function.

2. Add the new function name, methodology and description to `metric_descriptions.sql`.

3. Identify procedures that will need to be updated.

4. Create a new branch and open a pull request (PR).

## Test New Functions and procedures (Stats)

_This step focuses on testing the functions and procedures._

1. Open an executable environment.

2. Ensure all functions from the PR are active in the database.

3. Update the procedures based on the PR changes.

4. Run the procedures from the PR:

   ```sql
   -- Enter hour, day, week etc. for <period>
   CALL ecosystem.load_metrics_<period>();
   
   -- For backfilling/new metrics
   CALL ecosystem.load_metrics_init_temp-1();
   ```

5. Monitor outputs and allow the functions to run, populating the tables as needed.

6. Monitor function activity using `pg_activity`:

   ```bash
   pg_activity -U <user> -d <database> -h <host> -p <port>
   ```

7. Test SQL retrievability and data outputs for all periods.

8. Test GraphQL retrievability and data outputs for all periods.

9. Verify there are no issues.

### Handling Issues During Activation

- Revert all updated functions to the versions from the main branch of the repository.
- Revert all updated procedures to the versions from the main branch of the repository.
- Re-test data outputs to confirm the reversion is complete and queries return expected results.
- Log the issue in the PR and resume troubleshooting.

**See details of a procedure:**

```sql
SELECT
    n.nspname AS schema_name,
    p.proname AS procedure_name,
    pg_get_functiondef(p.oid) AS definition
FROM
    pg_proc p
JOIN
    pg_namespace n ON p.pronamespace = n.oid
WHERE
    p.prokind = 'p'
    AND n.nspname = 'ecosystem'
    -- Replace <name> with name of procedure.
    AND p.proname = '<name>';
```

**See currently loaded procedures:**

```sql
SELECT proname, proargtypes, proargnames
FROM pg_proc
WHERE pronamespace = 'ecosystem'::regnamespace;
```

**Drop/remove a procedure:**

```sql
-- Replace <period> with hour, day, week etc
DROP PROCEDURE IF EXISTS ecosystem.load_metrics_<period>();
```

## Formalize New Functions and Procedures (Stats)

1. Perform a final review of all changes in the repository.

2. Update the Hedera Stats spreadsheet as needed.

3. Notify stakeholders and the community for broader feedback.

## Publish New Statistic

1. Approve the PR and merge it into the base branch.

2. Review the Hedera Stats spreadsheet.

3. Update required documentation:

   - Hgraph Docs.
   - GitHub README.

4. Create any necessary examples and supporting content.

5. Publish updates and notify shareholders and the community.

6. Move the new stats to the “Official” tab in the Hedera Stats spreadsheet.

## Update/Activate Cron Jobs

_This step focuses on updating/configuring cron jobs._

**Creating new job:**

1. Verify functions & procedures are correct.

2. Review `pg_cron_metrics.sql` and make required updates.

3. Create new PR.

4. Test cron job for at least 1 period.

   - If needed, tweak job schedule to trigger immediately.

5. Review scheduled cron jobs.

6. Merge PR.

### Tips

View running cron jobs:

```sql
select * from cron.job;
```

Unschedule a cron job:

```sql
-- Replace <number> with jobid
select cron.unschedule(<number>);
```

## Delete Data

Preview data to be deleted:

```sql
SELECT *
FROM ecosystem.metric
WHERE name = '<metric_name>'
  AND period = '<period>';
```

Delete data:

```sql
DELETE FROM ecosystem.metric
WHERE name = '<metric_name>'
  AND period = '<period>';
```
