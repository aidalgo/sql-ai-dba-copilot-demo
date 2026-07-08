# SSMS Copilot — Ask Mode prompts

Copy/paste these into the **GitHub Copilot Ask** pane in SSMS 22.7+. Ask Mode is
read-only: it explains and rewrites text/queries but cannot run modification
statements. Have the relevant query, stored procedure, or execution plan open (or
selected) so Copilot has context.

> Tip: Open the regressed procedure (`Demo.usp_GetRegionalSalesByYear_Regressed`
> or `Demo.usp_GetCustomerInvoiceSummary_Regressed`) before asking, so the
> answers are grounded in the demo code.

## Explain a procedure / spot concerns
```
Explain what this stored procedure does and identify possible performance concerns.
```

## Make a query sargable
```
Rewrite this query to be more sargable without changing the business logic.
```

## Interpret an execution plan
```
Based on this execution plan, explain the likely bottleneck in simple DBA terms.
```

## Push back on partitioning
```
What evidence would you need before recommending partitioning for this table?
```

## Validate an index recommendation
```
Review this index recommendation and tell me what else I should validate before creating it.
```

---

### How to use these in the demo
1. Open the regressed stored procedure in a query window.
2. Run the **Explain** prompt — Copilot should call out `YEAR(InvoiceDate) = @Year`
   as non-sargable.
3. Run the **sargable rewrite** prompt — compare its suggestion to
   `Demo.usp_GetRegionalSalesByYear_Fixed`.
4. Display an actual execution plan (Ctrl+M, then run a single call) and use the
   **execution plan** prompt to translate scan vs seek into plain language.
5. Use the **partitioning** and **index** prompts to show Copilot reasoning about
   evidence rather than jumping to a fix.

Remember: the first answer is a starting point. Validate every suggestion against
Query Store, the execution plan, and workload evidence before acting.
