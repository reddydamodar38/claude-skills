---
name: cmb-copy
description: Copy CMB/SCP temp logs from ABLCAPUTIL app-node cmb_temp.zip artifacts into the shared ABL folder using the SCP397-style layout. Use when the user provides only an SCP/CMB name or number such as SCP2030, 2030, cmb_2030_*, or asks to copy cmb_<scp>_* files for the known ABLSCALE3 ST comparison runs.
---

# CMB Copy

Copy matching `cmb_<id>_*` files from ABLSCALE3 app-node `*_cmb_temp.zip` artifacts to the shared ABL destination.

## Default Behavior

When the user provides only a name/number:

- Accept `SCP2030`, `2030`, `cmb_2030_*`, `cmb_2030`, or similar.
- Derive the source file pattern:
  - If the numeric SCP is less than 1000, left-pad to four digits for the CMB filename, e.g. `SCP397` -> `cmb_0397_*`.
  - Otherwise use the number as-is, e.g. `SCP2030` -> `cmb_2030_*`.
- Derive the destination folder as `\\cernerwhq1\india\ABL\SCP<number-without-leading-zeroes>`.
- Copy to the same layout used by `\\cernerwhq1\india\ABL\SCP397`:

```text
\\cernerwhq1\india\ABL\SCP2030
  \2026.2.01ST6
    \20260406_2026.2.01ST6_3000_R43_MidLevel
      \ABLSCALE3APP01
      \ABLSCALE3APP02
    \20260407_2026.2.01ST6_3000_R46_MidLevel
      \ABLSCALE3APP01
      \ABLSCALE3APP02
  \2026.3.01ST6
    \20260527_2026.3.01ST6_3000_R20_MidLevel
      \ABLSCALE3APP01
      \ABLSCALE3APP02
    \20260603_2026.3.01ST6_3000_R48_MidLevel
      \ABLSCALE3APP01
      \ABLSCALE3APP02
```

## Known Source Runs

Use these source ZIPs by default:

```text
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.2.01ST6\20260406_2026.2.01ST6_3000_R43_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.2.01ST6\20260406_2026.2.01ST6_3000_R43_MidLevel\ABLSCALE3APP02\ablscale3app02_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.2.01ST6\20260407_2026.2.01ST6_3000_R46_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.2.01ST6\20260407_2026.2.01ST6_3000_R46_MidLevel\ABLSCALE3APP02\ablscale3app02_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260527_2026.3.01ST6_3000_R20_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260527_2026.3.01ST6_3000_R20_MidLevel\ABLSCALE3APP02\ablscale3app02_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip
\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP02\ablscale3app02_cmb_temp.zip
```

Inside each ZIP, copy only entries under:

```text
cerner/d_ablscale3/temp/
```

## Preferred Script

Use `scripts/copy-cmb.ps1` instead of rewriting extraction logic.

Examples:

```powershell
& "$skillDir\scripts\copy-cmb.ps1" -Name SCP2030
& "$skillDir\scripts\copy-cmb.ps1" -Name 2030
& "$skillDir\scripts\copy-cmb.ps1" -Name 'cmb_2030_*'
```

When running from Codex, use escalated permissions if needed because the script reads `\\dh2ffs01\...` and writes `\\cernerwhq1\india\ABL\...`.

## Safety

- Do not create flat folders such as `R20_ABLSCALE3APP01`; always use release/run/node layout.
- Overwrite same-named copied files in the destination only when the user is asking to refresh/copy the same CMB set.
- Do not delete older incorrectly placed folders unless the user explicitly asks to clean them up.
