# Metabase Dashboard Template

## Template Name

Compliance Control Tower

## Source SQL

Use queries from [metabase_compliance_dashboard.sql](metabase_compliance_dashboard.sql).

## Card Mapping

1. KPI - Payment Success Rate 30d

- Query: Query 01
- Visualization: Number
- Metric column: payment_success_rate_pct_30d

2. KPI - Failed Payments 30d

- Query: Query 01
- Visualization: Number
- Metric column: failed_payments_30d

3. KPI - Failed Workflows 30d

- Query: Query 01
- Visualization: Number
- Metric column: failed_workflows_30d

4. KPI - Running Workflows

- Query: Query 01
- Visualization: Number
- Metric column: running_workflows_30d

5. KPI - Ledger Coverage

- Query: Query 09
- Visualization: Number
- Metric column: ledger_coverage_pct

6. KPI - Statement Coverage

- Query: Query 11
- Visualization: Number
- Metric column: statement_coverage_pct

7. Trend - Daily Payment Failure

- Query: Query 02
- Visualization: Line chart
- X axis: day
- Y axis: failure_rate_pct

8. Trend - Daily Workflow Failure

- Query: Query 03
- Visualization: Line chart
- X axis: day
- Y axis: workflow_failure_rate_pct

9. SLA - Workflow Latency

- Query: Query 04
- Visualization: Number cards (3 cards)
- Metrics: avg_duration_seconds, p95_duration_seconds, p99_duration_seconds

10. Triage - Long Running Orchestrations

- Query: Query 05
- Visualization: Table

11. Triage - Error Hotspots

- Query: Query 06
- Visualization: Table

12. Fraud - High Value Transfers

- Query: Query 07
- Visualization: Table

13. Fraud - Velocity Breaches

- Query: Query 08
- Visualization: Bar chart
- Category: payer_account_id
- Value: payments_24h

14. Audit - Missing Ledger Records

- Query: Query 10
- Visualization: Table

15. Data Quality - Account Balance Hygiene

- Query: Query 12
- Visualization: Table

16. Data Quality - Identity Hygiene

- Query: Query 14
- Visualization: Table

## Layout (12 Column Grid)

- Row 1 (6 x width-2): Cards 1 to 6
- Row 2 (2 x width-6): Cards 7 and 8
- Row 3 (3 x width-4): Card 9 split into three KPI cards
- Row 4 (2 x width-6): Cards 10 and 11
- Row 5 (2 x width-6): Cards 12 and 13
- Row 6 (2 x width-6): Cards 14 and 15
- Row 7 (1 x width-12): Card 16

## Suggested Thresholds

- Payment success rate green >= 99, amber 97 to 98.99, red < 97
- Workflow failure rate green <= 1, amber 1.01 to 3, red > 3
- Ledger coverage green >= 99.5, amber 98 to 99.49, red < 98
- Statement coverage green >= 98, amber 95 to 97.99, red < 95

## Notes

- Run each query in PostgreSQL database connection (not Sample Database).
- Save each query as a Question first, then add to dashboard.
- Start with the six KPI cards before adding trend and triage tables.
