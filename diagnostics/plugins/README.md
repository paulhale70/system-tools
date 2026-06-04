# Diagnostics plugins

Drop any `.ps1` file in this folder and it will be dot-sourced as the
last step of `Invoke-SystemDiagnostics` (after the built-in section 10).
Plugins have access to all the helpers:

| Helper | Use |
| --- | --- |
| `Write-Section "Title"`              | Print a section banner. |
| `Add-Summary 'OK'\|'WARN'\|'FAIL' msg` | Add a verdict to `00-SUMMARY.txt` + HTML. |
| `Try-Run 'label' { ... }`            | Wrap risky code; failures become FAIL verdicts. |
| `Save-Text 'name.txt' $content`      | Write a file into the current report folder. |
| `$ReportDir`                         | The current report folder path. |
| `$script:reportDir`, `$script:summary` | Shared run state. |

Example plugin (`disk-temperature.ps1`):

```powershell
Write-Section 'Disk temperature'
Try-Run 'SMART temperature' {
    $info = Get-CimInstance -Namespace root\wmi -Class MSStorageDriver_ATAPISmartData -ErrorAction Stop |
        Select-Object InstanceName, VendorSpecific
    if ($info) {
        $info | Format-List | Out-String | Save-Text 'plugin-disk-temp.txt'
        Add-Summary 'OK' "Disk SMART temperature captured ($($info.Count) drives)."
    } else {
        Add-Summary 'WARN' 'No disk temperature data available.'
    }
}
```

The desktop GUI's **Plugins** tab lists everything in this folder and
lets you enable/disable per-plugin without removing the file
(disabled plugins are renamed `.ps1.disabled`).

A simple `_sample.ps1.disabled` ships alongside this README so you
can see the contract; rename it to `.ps1` to activate.
