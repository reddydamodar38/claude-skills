# CleanPlant Patterns

Use these examples as quick pattern-matching references while cleaning an Eggplant script.

## Step Wrapper Conversion

Before:

```text
Log "Step 2: Open the patient chart"
...
Log "End Step 2"
```

After:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Step 2: Open the patient chart"
...
EndTestCase wfStep
```

Only convert explicit step-wrapper logs. Keep ordinary runtime logging as-is.

## Rules of the Road Removal

Remove patterns like:

```text
if imagefound (text:"OK",SearchRectangle: "UTIL/Screen".center) then
    click {text:"OK",SearchRectangle: "UTIL/Screen".center}
    wait 1
    click {text:"Password",SearchRectangle: "UTIL/Screen".center}
    TypeHiddenText sutPassword, returnKey
end if

"DSK/Utilities".dismissRulesOfRoad
wait 10
```

## Platform/App-Domain Cleanup

Remove patterns like:

```text
Params platform, appDomainName, millenniumDomain

if platform is empty then set platform to "EOD"
if appDomainName is empty then set appDomainName to "FPSG"
if millenniumDomain is empty then set millenniumDomain to "FPSG"
```

Then remove now-unused globals tied to the same flow.

## Storefront Login Replacement

Replace direct-login blocks like:

```text
if domain is "FPDomain" then
    "UTIL/Common".selectPlatform platform, citrixApp, citrixURL, citrixCredentialID, sutUsername, sutPassword, appDomainName
    WaitFor imgWait*4, text:"Password",SearchRectangle:"UTIL/Screen".center
    "MIL/Millennium".login millUsername, millPassword, millenniumDomain
else
    "Common".openSupportFolderFromStoreFront
    "Common".loginExe millUsername, millPassword, citrixApp
end if
```

with:

```text
If not ImageFound(imageName:"PowerChart/Icon_Powerchart", waitFor:(imgWait/2))
    Run "CTX/AbilitiesCitrixMethods".SCL_LaunchAndLoginCitrix citrixShortcut, sutUsername, sutPassword
    WaitFor imgWait*7, "Textbox_Login_Username"
    Run "MIL/Millennium".login millUsername, millPassword
End If
```

If that storefront launch section is already uncommented and otherwise correct in the main script, leave it as-is. Treat any active `WaitFor imgWait*<number>, "Textbox_Login_Username"` line as a valid match instead of rewriting the block just to force the multiplier to `7`.

When an active launch block already matches this structure, preserve the whole block unchanged when the only differences are the `imgWait*<number>` multiplier and the choice of `millUsername` versus the matching `millUsername*` login variable.

## Recording Artifact Removal

Remove:

```text
StartMovie ["WorkflowName"]
StopMovie
CaptureScreen {Name:"SomeStep"}
CaptureScreen
```

Keep exception-only capture patterns like:

```text
catch exception
    LogError("Failed Workflow Step:" && wfStep && " - " && the exception)
    CaptureScreen {Name:"ExceptionScreen"}
end try
```

Do not strip `LogError(...)` from that pattern. Exception-path logging stays.

## Preserve Optional Workflow Gates

Keep patterns like:

```text
If ImageFound(text:"Scan or manually", SearchRectangle:"UTIL/Screen".center, WaitFor:imgWait) then
    Click {text:"Serial Number", HotSpot:[0,30], EnableAggressiveTextExtraction:"YES", SearchRectangle:"UTIL/Screen".center, WaitFor:imgWait}
    ...
End If
```

Do not rewrite that shape into an unconditional `WaitFor` when the guarded block performs optional workflow-driving actions.

## App-Specific Exit Normalization

Use the exit sequence that matches the application the workflow launched.

PowerChart (including Appbar-launched PathNet workflows):

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Exit out of PowerChart."
wait 2
    TypeText altKey, "t"
    wait 2
    TypeText "x"
EndTestCase wfStep
```

RevenueCycle:

```text
Run "CTX/AbilitiesCitrixMethods".wfTestCase "Exit out of Revenue Cycle."
wait 2
TypeText altKey, "f", "x"
EndTestCase wfStep
```

