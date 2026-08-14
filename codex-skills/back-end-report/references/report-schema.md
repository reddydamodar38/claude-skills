# Workbook Schema

Keep the original sheets unchanged and in order: Read Me, Node Summary, Server Comparison, GC Comparison, Smaps End, and Config Changes.

Insert Executive Summary, Database Summary, SQL Comparison, AWR Summary, Instance Summary, Ndump Summary, CMB Summary, Artifact Coverage, and Errors & Warnings before server-detail tabs. Keep headers-only sheets when evidence is absent.

Executive Summary includes overall severity, core and extended regressions/improvements, SQL plan additions/removals, new error signatures, evidence-backed configuration correlations, limitations, routes, and provenance links.

Use frozen headers, autofilters, wrapped assessment/source columns, numeric and percentage formats, metric-aware severity colors, plan-change emphasis, valid local evidence hyperlinks, and charts when findings exist. Render structured assessments as readable severity, confidence, evidence, cause, and route text.

Run `scripts/validate_workbook.ps1 -RequireExtended` after rendering. Validation checks sheet order and names, exact extended headers, filters, freeze panes, styles, numeric formats, conditional formatting, formula errors, hyperlinks, and chart minimums.

