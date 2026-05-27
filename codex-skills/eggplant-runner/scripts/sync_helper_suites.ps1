param(
  [string]$HostName = "10.191.205.92",
  [string]$UserName = "root",
  [string]$KeyPath = "C:/Users/prakash/.ssh/id_gatling",
  [string]$RemoteWorkspace = "/root/eggplant",
  [string]$AutomationHostPath = "/root/eggplant/ABL_VA_NBS.suite"
)

$ErrorActionPreference = "Stop"
$eggplantSuitesPath = "$RemoteWorkspace/EggplantSuites"

function Invoke-External {
  param([string]$Exe, [string[]]$CmdArgs)
  & $Exe @CmdArgs | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed ($LASTEXITCODE): $Exe $($CmdArgs -join ' ')"
  }
}

function Invoke-Ssh {
  param([string]$RemoteCommand)
  $sshArgs = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", $KeyPath,
    "$UserName@$HostName",
    $RemoteCommand
  )
  Invoke-External -Exe "ssh" -CmdArgs $sshArgs
}

function Escape-ForSingleQuotes {
  param([string]$Text)
  return ($Text -replace "'", "'""'""'")
}

Write-Host "Running helper-suite sync/check on $HostName ..."

$remoteScript = @"
set -e
suite_root='$AutomationHostPath'
helper_root='$eggplantSuitesPath'
tmp_refs=`$(mktemp)
tmp_missing=`$(mktemp)
tmp_unresolved=`$(mktemp)
resolved=0

collect_refs_from_dir() {
  local target_dir="`$1"
  [ -d "`$target_dir" ] || return 0
  find "`$target_dir" -type f \( -name 'SuiteInfo' -o -name '*.script' \) -print0 2>/dev/null | \
    while IFS= read -r -d '' f; do
      grep -Eho '/home/eggplant/EggplantSuites/[^"'"'"'[:space:]]+\.suite|/C:/EggplantSuites/[^"'"'"'[:space:]]+\.suite|C:/EggplantSuites/[^"'"'"'[:space:]]+\.suite|C:/EggPlantSuites/[^"'"'"'[:space:]]+\.suite|C:/Eggplantsuites/[^"'"'"'[:space:]]+\.suite|N:/Wayne_Wertz/VA-Repos/[^"'"'"'[:space:]]+\.suite|/N:/Wayne_Wertz/VA-Repos/[^"'"'"'[:space:]]+\.suite|<Suite_[Rr]oot>/\.\./[^"'"'"'[:space:]]+\.suite|\./[^"'"'"'[:space:]]+\.suite' "`$f" 2>/dev/null || true
    done
}

map_to_host() {
  local ref="`$1"
  case "`$ref" in
    /home/eggplant/EggplantSuites/*) printf '%s/%s\n' "`$helper_root" "`${ref#/home/eggplant/EggplantSuites/}" ;;
    /C:/EggplantSuites/*) printf '%s/%s\n' "`$helper_root" "`${ref#/C:/EggplantSuites/}" ;;
    C:/EggplantSuites/*) printf '%s/%s\n' "`$helper_root" "`${ref#C:/EggplantSuites/}" ;;
    C:/EggPlantSuites/*) printf '%s/%s\n' "`$helper_root" "`${ref#C:/EggPlantSuites/}" ;;
    C:/Eggplantsuites/*) printf '%s/%s\n' "`$helper_root" "`${ref#C:/Eggplantsuites/}" ;;
    /N:/Wayne_Wertz/VA-Repos/*) printf '%s/%s\n' "`$helper_root" "`${ref#/N:/Wayne_Wertz/VA-Repos/}" ;;
    N:/Wayne_Wertz/VA-Repos/*) printf '%s/%s\n' "`$helper_root" "`${ref#N:/Wayne_Wertz/VA-Repos/}" ;;
    "<Suite_root>/../"*) printf '%s/%s\n' "`$helper_root" "`${ref#<Suite_root>/../}" ;;
    "<Suite_Root>/../"*) printf '%s/%s\n' "`$helper_root" "`${ref#<Suite_Root>/../}" ;;
    ./*) printf '%s/%s\n' "`$helper_root" "`${ref#./}" ;;
    *) printf '%s\n' "`$ref" ;;
  esac
}

{
  collect_refs_from_dir "`$suite_root"
  collect_refs_from_dir "`$helper_root"
} | while IFS= read -r ref; do
  [ -z "`$ref" ] && continue
  map_to_host "`$ref"
done | sort -u > "`$tmp_refs"

while IFS= read -r expected; do
  [ -z "`$expected" ] && continue
  [ -d "`$expected" ] && continue
  printf '%s\n' "`$expected" >> "`$tmp_missing"
done < "`$tmp_refs"

if [ ! -s "`$tmp_missing" ]; then
  echo "Helper sync: no missing suites found."
  rm -f "`$tmp_refs" "`$tmp_missing" "`$tmp_unresolved"
  exit 0
fi

echo "Helper sync: attempting to resolve missing suites..."
while IFS= read -r miss; do
  [ -z "`$miss" ] && continue
  base=`$(basename "`$miss")
  cand=`$(find "`$helper_root" -type d -iname "`$base" 2>/dev/null | head -n 1 || true)
  if [ -n "`$cand" ] && [ -d "`$cand" ]; then
    mkdir -p "`$(dirname "`$miss")"
    ln -sfn "`$cand" "`$miss"
    echo "Linked: `$miss -> `$cand"
    resolved=`$((resolved + 1))
  else
    echo "`$miss" >> "`$tmp_unresolved"
  fi
done < "`$tmp_missing"

echo "Helper sync resolved by symlink: `$resolved"
if [ -s "`$tmp_unresolved" ]; then
  echo "Unresolved missing helper suites:"
  cat "`$tmp_unresolved"
  rm -f "`$tmp_refs" "`$tmp_missing" "`$tmp_unresolved"
  exit 2
fi

rm -f "`$tmp_refs" "`$tmp_missing" "`$tmp_unresolved"
echo "Helper sync complete: all referenced suites resolved."
"@

$escapedScript = Escape-ForSingleQuotes -Text $remoteScript
Invoke-Ssh "bash -lc '$escapedScript'"
Write-Host "Done."
