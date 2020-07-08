Param(
    [parameter(Position = 0, Mandatory = $true)][string]$Path, 
    [Parameter(Position = 1,Mandatory = $false)] [switch]$NoClobber,
    [Parameter(Position = 2,Mandatory = $false)] [switch]$Verbose,
    [Parameter(Position = 3,Mandatory = $false)] [switch]$Debug
)
function Write-Log { 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory = $true, 
            ValueFromPipelineByPropertyName = $true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
          
        [Parameter(Mandatory = $false)] 
        [ValidateSet("Error", "Warn", "Info", "Debug")] 
        [string]$Level = "Info" 
    ) 
 
    Begin { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        if ($verbose) { $VerbosePreference = 'Continue' }
        if ($debug) { $DebugPreference = 'Continue' }
    } 
    Process { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
        } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File | Out-Null
        } 
 
        else { 
            # Nothing to see here yet. 
        } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        $writeLog = $true
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR' 
            } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING' 
            } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO' 
            } 
            'Debug' {
                if (!$debug) {
                    $writeLog = $false
                }
                Write-Debug $Message
                $LevelText = 'DEBUG'
            }
        } 
         
        # Write log entry to $Path 
        if ($writeLog) { "$FormattedDate|$LevelText|$Message" | Out-File -FilePath $Path -Append -Encoding ASCII}
    } 
    End { 
    } 
}

Export-ModuleMember Write-Log