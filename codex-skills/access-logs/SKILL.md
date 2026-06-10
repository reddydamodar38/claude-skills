---
name: access-logs
description: Collect access or CMB log files from ABLCAPUTIL test-run artifacts and organize them by subproject, test run, and node. Use when Codex needs to copy files matching patterns such as cmb_0373_* from zip-internal temp paths like ABLCAPUTIL\<subproject>\<run>\<node>\*_cmb_temp.zip\cerner\d_<domain>\temp into a shared destination such as \\cernerwhq1\india\ABL\scp397\<subproject>\<run>\<node>.
---

# Access Logs

Use this skill when the user asks to collect, move, copy, extract, or share access/CMB logs from ABLCAPUTIL run folders.

Default to copying files, not moving or deleting. Zip archive sources are read-only: extract matching files out of the archive into the destination. Do not attempt to remove files from zip archives.

## Inputs

- `SourcePath`: one or more source paths. A source may be a normal directory or a zip-internal path such as:
  - `\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip\cerner\d_ablscale3\temp`
- `DestinationRoot`: shared destination root, for example:
  - `\\cernerwhq1\india\ABL\scp397`
- `Pattern`: file name pattern to collect. Default to `cmb_0373_*` unless the user specifies a different pattern.

## Destination Layout

Organize output by subproject, test run, and node:

```text
<DestinationRoot>\<subproject>\<test-run>\<node>\<matching files>
```

For ABLCAPUTIL zip-internal paths, infer:

- subproject: folder immediately after `ABLCAPUTIL`
- test run: folder immediately before the node folder
- node: folder immediately before the `*.zip` file

Example:

```text
\\cernerwhq1\india\ABL\scp397\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP01\cmb_0373_0001.out
```

## Workflow

1. Confirm the user provided source paths and a destination root.
2. Prefer copy/extract. Only perform destructive moves when the user explicitly asks and the source is a normal file system path, not a zip archive.
3. Run `scripts/copy-access-logs.ps1` with the user-provided source paths, destination root, and pattern.
4. Report:
   - total files copied
   - destination root
   - per-subproject, per-run, and per-node counts
   - missing zip/source paths or no-match sources

## Script

Use the bundled script for deterministic collection:

```powershell
$sources = @(
  '\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP01\ablscale3app01_cmb_temp.zip\cerner\d_ablscale3\temp',
  '\\dh2ffs01\ablpub\ablscale3\ABLCAPUTIL\2026.3.01ST6\20260603_2026.3.01ST6_3000_R48_MidLevel\ABLSCALE3APP02\ablscale3app02_cmb_temp.zip\cerner\d_ablscale3\temp'
)

.\access-logs\scripts\copy-access-logs.ps1 `
  -SourcePath $sources `
  -DestinationRoot '\\cernerwhq1\india\ABL\scp397' `
  -Pattern 'cmb_0373_*'
```

## Safety

- Use `-WhatIf` first when the destination or source list is uncertain.
- Keep zip archives read-only.
- Do not flatten across subprojects, runs, or nodes; duplicate file names are common.
- If source paths are inaccessible, report them instead of silently skipping.
