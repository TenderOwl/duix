<#
.SYNOPSIS
Reads the tree of UI Automation of a window and prints it.

.DESCRIPTION
The bridge of UI Automation serves the semantics tree of the widgets to the
assistive technologies of Windows. The script asks the system for the tree of
a window and prints the elements it finds, so the bridge can be checked
without a screen reader.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tool\verify_uia.ps1 -Title "DUI accessibility"

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tool\verify_uia.ps1 -ProcessId 1234
#>
param(
    [string]$Title = '',
    [int]$ProcessId = 0,
    [int]$Depth = 16
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$root = [System.Windows.Automation.AutomationElement]::RootElement

if ($ProcessId -gt 0) {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $ProcessId)
} elseif ($Title -ne '') {
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $Title)
} else {
    throw 'Give the title of the window or the id of the process.'
}

$windows = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Children, $condition)

if ($windows.Count -eq 0) {
    throw 'The window was not found.'
}

$window = $windows.Item(0)
Write-Output ("window: {0}" -f $window.Current.Name)

$walker = [System.Windows.Automation.TreeWalker]::RawViewWalker

function Show-Tree {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$Level
    )

    if ($Level -gt $Depth) {
        return
    }

    $current = $Element.Current
    $type = $current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
    $rect = $current.BoundingRectangle
    $flags = ''
    if ($current.HasKeyboardFocus) {
        $flags += ' focused'
    }
    if (-not $current.IsEnabled) {
        $flags += ' disabled'
    }
    if (-not $current.IsControlElement) {
        $flags += ' not-control'
    }
    Write-Output ('{0}{1} "{2}"{3} [{4},{5} {6}x{7}]' -f
        ('  ' * $Level), $type, $current.Name, $flags,
        [int]$rect.X, [int]$rect.Y, [int]$rect.Width, [int]$rect.Height)

    $child = $walker.GetFirstChild($Element)
    while ($child -ne $null) {
        Show-Tree -Element $child -Level ($Level + 1)
        $child = $walker.GetNextSibling($child)
    }
}

Show-Tree -Element $window -Level 0
