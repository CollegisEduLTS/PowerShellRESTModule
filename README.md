PowerShell Modules for Blackboard Learn REST API
Collegis Education

This repo contains two modules we've developed, for use with all of our powershell scripts that we've created to help manage many of our processes with Blackboard Learn.

# The paramters are path, NoClobber, Verbose, Debug
Import-Module "<path>\CLGS_Logging.psm1" -ArgumentList <logfile name>, $false, $false, $debug

# The parameters are the baseUrl, key, secret
Import-Module "<path>\CLGS_Learn_REST_API.psm1" -ArgumentList <base Learn URL>, <REST API key>, <REST API secret>
