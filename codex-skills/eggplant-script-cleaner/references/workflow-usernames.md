# Workflow Usernames

Use this reference when a CleanPlant task touches a DataLoader `millUsername` or `millUsername*` value.

## Source Of Truth

Authoritative source for applying Millennium usernames/passwords:

`C:\Users\KS078306\Desktop\codex-skills\eggplant-script-cleaner\references\accepted-workflow-username-mappings.csv`

Use this file first and do not override it with workbook-derived values.

- `status = mapped`: apply `resolved_usernames`, `position`, and `resolved_mill_password`
- `status = no_match_preserve_existing`: keep existing DataLoader and `*_LoginData.csv` username/password values unchanged
- workflow missing in accepted mapping file: keep existing DataLoader and `*_LoginData.csv` username/password values unchanged

## Lookup Process

1. Open `accepted-workflow-username-mappings.csv`.
2. Match exact `workflow` name to the target workflow.
3. If matched and `status = mapped`, use `resolved_usernames` (split by `|`), `position` (split by `|`), and `resolved_mill_password`.
4. If matched and `status = no_match_preserve_existing`, preserve current values.
5. If no mapping row exists for the workflow, preserve current values.
6. Append trailing `1` to a username only when a mapped value in `resolved_usernames` does not already include it.
7. If multiple usernames are mapped, keep username-to-position pairing by index (`resolved_usernames[0]` -> `position[0]`, and so on).
8. If multiple usernames are mapped, read the target `.script` and derive role order primarily from login `wfTestCase` labels (for example `Login into PowerChart as a Physician Hospitalist.`).
9. If those login `wfTestCase` labels do not exist, derive role order from preserved section markers/comments such as `//Part1: Physician workflow ...` that label each login segment.
10. For PowerChart workflows, treat `PopUps.assignRelationship "<Role Text>"` as an additional role indicator when label/comment evidence is ambiguous.
11. Auto-reorder mapped usernames to match the inferred script role order before writing `millUsername1`, `millUsername2`, and so on.
12. If script role order cannot be derived from `wfTestCase` labels, preserved part comments, or PowerChart `assignRelationship`, keep the accepted mapping CSV order and preserve the same username-to-position index pairing.

## Write Rules

Use these patterns when updating hardcoded login defaults:

- one username:
  `Set millUsername = "<username>" //{<position>}`
- multiple usernames:
  `Set millUsername1 = "<username1>" //{<position1>}`
  `Set millUsername2 = "<username2>" //{<position2>}`
  `Set millUsername3 = "<username3>" //{<position3>}`

Use the numbered variables only when the mapped workflow has multiple usernames.

For mapped workflows with multiple usernames, script role order from `wfTestCase` labels is mandatory when detectable; if labels are missing, use preserved part comments. Do not keep `resolved_usernames` list order when it conflicts with inferred role order.
When mapped usernames are written, append the mapped position comment to each username assignment in exact format `//{<position>}`.
When usernames are reordered to match script login order, move the paired position comments with them.

When touching hardcoded login defaults from a mapped row, use:

`Set millPassword = "scale"`

If the script already uses numbered password variables, keep the file's naming pattern consistent while still using the literal password value `"scale"` when the mapping row is `mapped`.

## CSV Sync

When CleanPlant also syncs the login CSV, copy mapped usernames into `*_LoginData.csv` and set matching `millPassword` to `scale` for `status = mapped`.

If `status = no_match_preserve_existing` (or the workflow is not present in the accepted mapping file), do not rewrite login CSV username/password values.

Examples:

```text
millUsername,millPassword
ABL_Quick_Registration1,scale
```

```text
millUsername1,millPassword,millUsername2
ABL_PhaChrgCredit_Pt1_B1,scale,ABL_PhaChrgCredit_Pt1_AA1
```

## Guardrails

- Treat `accepted-workflow-username-mappings.csv` as authoritative for username/password application.
- Treat the accepted `position` field as authoritative for username-to-role pairing (`resolved_usernames` index aligned with `position` index).
- Require inline position comments on DataLoader username assignments in exact format `//{<position>}`.
- Do not perform workbook username lookup for Millennium username mapping in this skill revision.
- Do not force replacements when the mapping status is `no_match_preserve_existing`.
- Do not force replacements when the workflow has no accepted mapping row.
- After applying mapped values, verify DataLoader `millUsername*`/`millPassword*` and `*_LoginData.csv` are aligned.
- If alignment is wrong, auto-update DataLoader and `*_LoginData.csv` values to match inferred script role order (primary: `wfTestCase` labels; fallback: preserved part comments; additional PowerChart indicator: `PopUps.assignRelationship`).
- Do not introduce `\` characters in mapped usernames.
