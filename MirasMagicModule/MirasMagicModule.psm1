$InformationPreference = "Continue"
function Read-Choice {
    <#
    .SYNOPSIS
    Create prompt for choosing from various options. Returns ID of chosen choice.

    .PARAMETER Message
    The actual question, like "Do you want to continue?"

    .PARAMETER Choices
    The choises for the question as array. like @("Yes","No")

    .PARAMETER DefaultChoice
    ID from choices array for default, which will be selected by just hitting enter. Defaults to 1

    .PARAMETER Title
    Optional title, which is shown above message. Defaults to empty string.

    .EXAMPLE
    Read-Choice -Message "Do you want to continue?" -Choices @("Yes","No")
    will create:

    Do you want to continue?
    [Y] Yes  [N] No  [?] Help (default is "N"):

    #>
    Param(
        [System.String]$Message,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]$Choices,

        [System.Int32]$DefaultChoice = 1,

        [System.String]$Title = [string]::Empty
    )
    [System.Management.Automation.Host.ChoiceDescription[]]$Poss = $Choices | ForEach-Object -Process {
        New-Object System.Management.Automation.Host.ChoiceDescription "&$($_)", ""
    }
    return $Host.UI.PromptForChoice( $Title, $Message, $Poss, $DefaultChoice )
}



function Read-Confirmed() {
    <#
    .SYNOPSIS
    Read input with regex validation

    .PARAMETER question
    What will be required, f.ex. "Please enter username"

    .PARAMETER regex
    The regex string agaist which the input for the question will be validated

    .PARAMETER inputerror
    If the input doesn't match, what to tell to user why it doesn't. It will add inserted input and one space in front of the string.

    .PARAMETER validateinput
    If you want to validate parameter with correction, you can provide test string with this parameter. If input matches with regex, only the possible switch functionality will be executed. Notably in Get-Ticket

    .PARAMETER stripSpaces
    If spaces are unwanted, those can be removed automatically with this switch

    .PARAMETER caps
    If you want the output to be capitalized, use this switch. Notably in Get-Ticket

    .EXAMPLE
    Read-Confirmed -question "Please enter username" -regex "\w" -inputerror "isn't word" -stripSpaces

    #>
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][System.String]$question,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][System.String]$regex,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][System.String]$inputerror,
        [System.String] $validateinput,
        [switch]
        $stripSpaces,
        [switch]
        $caps
    )
    $uinput = $validateinput
    $first = $true
    while ($uinput -notmatch $regex) {
        if ($first -eq $false) {
            Write-Host -ForegroundColor Red "$uinput $inputerror"
        }
        $uinput = Read-Host $question
        $first = $false
    }
    if ($stripSpaces) {
        $uinput = $uinput -replace ' ', ''
    }
    if ($caps) { $uinput = $uinput.toUpper() }
    return $uinput
}



Function New-RandomComplexPassword () {
    <#
    .SYNOPSIS
    Generates strong passwords like *5G%n[5fyI

    .PARAMETER Length
    How long password will be generated, default is 14

    .EXAMPLE
    New-RandomComplexPassword

    .OUTPUTS
    System.String

    #>
    param ( [int]$Length = 14 )
    Add-Type -AssemblyName System.Web | Out-Null
    $RandomComplexPassword = [System.Web.Security.Membership]::GeneratePassword($Length, 2)
    return $RandomComplexPassword
}



Function New-RandomPassword () {
    <#
    .SYNOPSIS
    Generates strong passwords like 2zD9cqr0F1

    .PARAMETER Length
    How long password will be generated, default is 14

    .EXAMPLE
    New-RandomComplexPassword

    .OUTPUTS
    System.String

    #>
    # on my virtual machine, generates one password in 0.863ms (average of 10000 loops)
    param (
        [int] $length = 18
    )

    $charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()

    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)

    $rng.GetBytes($bytes)

    $result = New-Object char[]($length)

    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }

    return -join $result
}



function Get-Ticket {
    <#
    .SYNOPSIS
    Validates JIRA ticket form and prompts interactively if not provided or in incorrect form

    .PARAMETER ticket
    Ticket for the task, default to null which will prompt it interactively

    .EXAMPLE
    Get-Ticket -ticket DACEOPS-666

    .OUTPUTS
    System.String

    #>
    param([string]$ticket = $null)
    return Read-Confirmed -validateinput $ticket -question "Jira-ticket" -regex '(\w{2,}-\d{1,})' -inputerror "is not in acceptable form" -stripSpaces -caps
}


function Search-SubnetPingAliveStatus {
    <#
    .SYNOPSIS
    Ping subnet and print ping status of each host

    .PARAMETER ipblock
    The IP address block to ping. /24 blocks with only first three octets, eg. 10.20.30

    .PARAMETER timeout
    Ping timeout in millisecods. Defaults to 10

    .EXAMPLE
    Search-SubnetPingAliveStatus 10.20.30 10

    .OUTPUTS
    PSCustomObject

    #>
    param(
        [string] $ipblock,
        [int] $timeout = 10
    )
    $ping = New-Object System.Net.NetworkInformation.Ping
    1..254 | ForEach-Object {
        [PSCustomObject]@{
            Address    = "{0,15}" -f "$ipblock.$_"
            PingStatus = $($ping.send("$ipblock.$_", $timeout).status)
        }
    }
}

function Get-Remote () {
    <#
    .SYNOPSIS
    Check if current session is remote or local and prompt & re-create credential object if needed.

    .PARAMETER cred
    Adds possibility to give credentials from calling script, faking remote session (and hence injecting these). Eases out debugging as well as you can just pass credential object on remote session

    .PARAMETER CheckOnly
    As the name says. It will only check if the session is remote. This is useful if some cmdlets won't work on remote session (*COUGH* GroupPolicy *COUGH*)

    .OUTPUTS
    Hashtable, boolean remote and PSCredential cred
    #>
    param(
        [parameter(Mandatory = $false)]
        [PSCredential]
        $cred = $null,
        [switch]
        $CheckOnly
    )
    if ($null -ne $env:ssh_client -or $null -eq $env:sessionname) {
        if (-not $CheckOnly.IsPresent) {
            if ($cred -is [PSCredential]) {
                Write-Host "Remote session detected, using provided credential object"
            }
            else {
                Write-Host "Remote session detected. Some cmdlets won't work without re-creating credential object. Autodetected username '$($env:USERNAME)'"
                $user = $env:USERNAME
                $pass = Read-Host -AsSecureString "Please enter your $($env:userdomain) password"
                $cred = New-Object System.Management.Automation.PSCredential($user, $pass)
            }
        }
        $remote = $true
    }
    else {
        if ($cred -is [PSCredential]) {
            Write-Host "Local session detected but credential object provided. Faking remote session"
            $remote = $true
        }
        else {
            $remote = $false
        }
    }
    return @{remote = $remote; cred = $cred }
}

function Remove-StringDiacritic {
    <#
    .SYNOPSIS
        This function will remove the diacritics (accents) characters from a string. Fails on some characters like Ł and ø

    .PARAMETER String
        Specifies the String on which the diacritics need to be removed

    .PARAMETER NormalizationForm
        Specifies the normalization form to use
        https://msdn.microsoft.com/en-us/library/system.text.normalizationform(v=vs.110).aspx

    .EXAMPLE
        PS C:\> Remove-StringDiacritic "L'été de Raphaël"

        L'ete de Raphael
    #>
    param (
        [String]
        $String = [String]::Empty
    )
    $normalized = $String.Normalize( [Text.NormalizationForm]::FormD )
    return ($normalized -replace '\p{M}', '')
}

Function Get-AzureConnection {
    <#
    .SYNOPSIS
        Check and get/change Azure connection and correct context. Can handle the different principal connections
    #>
    [CmdletBinding(DefaultParameterSetName = "Interactive")]
    param(
        [Parameter(ParameterSetName = "Interactive")]
        [string[]]
        $Scopes,
        [Parameter(ParameterSetName = "Interactive")]
        [Parameter(ParameterSetName = "ClientSecret", Mandatory)]
        [String]
        $TenantId,
        [Parameter(ParameterSetName = "Interactive")]
        [Parameter(ParameterSetName = "ClientSecret", Mandatory)]
        [String]
        $SubscriptionId,
        [Parameter(ParameterSetName = "Interactive")]
        [Parameter(ParameterSetName = "UserManagedIdentity", Mandatory)]
        [Parameter(ParameterSetName = "ClientId", Mandatory)]
        [string]
        $ClientId,
        [Parameter(ParameterSetName = "Interactive")]
        [Parameter(ParameterSetName = "Identity")]
        [Parameter(ParameterSetName = "ClientId")]
        [Parameter(ParameterSetName = "ClientSecret")]
        [ValidateSet("Process")]
        $ContextScope,
        [Parameter(ParameterSetName = "Identity", Mandatory)]
        [Parameter(ParameterSetName = "AzIdentity", Mandatory)]
        [Parameter(ParameterSetName = "UserManagedIdentity", Mandatory)]
        [switch]
        $Identity,
        [Parameter(ParameterSetName = "ClientSecret", Mandatory)]
        [PSCredential]
        $ClientSecretCredential,
        [Parameter(ParameterSetName = "AzToken", Mandatory)]
        [Parameter(ParameterSetName = "Token", Mandatory)]
        [SecureString]
        $AccessToken,
        [Parameter(ParameterSetName = "AzToken", Mandatory)]
        [Parameter(ParameterSetName = "AzIdentity", Mandatory)]
        [string]
        $AccountId,
        [switch]
        $UseAzCmdlets
    )
    if ($UseAzCmdlets.IsPresent) {
        try {
            $CurrentContext = Get-AzContext -ErrorAction Stop
            $ContextsAvailable = Get-AzContext -ListAvailable -ErrorAction Stop
        }
        catch {
            $CurrentContext = $null
            $ContextsAvailable = $null
        }
        if (($null -ne $CurrentContext) -and ($CurrentContext.Tenant.Id -ne $TenantId) -and ($CurrentContext.Subscription.Id -ne $SubscriptionId)) {
            if ($null -ne $ContextsAvailable) {
                $PotentialContext = $ContextsAvailable | Where-Object { $_.Tenant.Id -eq $TenantId -and $_.Subscription.Id -eq $SubscriptionId }
            }
            else {
                $PotentialContext = $null
            }
            if ($null -eq $PotentialContext) {
                $ConnectSplat = @{}
                if ($null -ne $ContextScope) {
                    $ConnectSplat.Add("Scope", $ContextScope)
                }
                if ($PSCmdlet.ParameterSetName -eq "Interactive") {
                    if ($null -ne $TenantId) {
                        $ConnectSplat.Add("TenantId", $TenantId)
                    }
                    if ($null -ne $SubscriptionId) {
                        $ConnectSplat.Add("SubscriptionId", $SubscriptionId)
                    }
                    if ($null -ne $ClientId) {
                        $ConnectSplat.Add("AccountId", $ClientId)
                    }
                }
                if ($PSCmdlet.ParameterSetName -eq "ClientSecret") {
                    $ConnectSplat.Add("TenantId", $TenantId)
                    $ConnectSplat.Add("SubscriptionId", $SubscriptionId)
                    $ConnectSplat.Add("Credential", $ClientSecretCredential)
                    $ConnectSplat.Add("ServicePrincipal", $true)
                }
                if ($PSCmdlet.ParameterSetName -eq "AzToken") {
                    $ConnectSplat.Add("AccessToken", $AccessToken)
                    $ConnectSplat.Add("AccountId", $AccountId)
                }
                if ($PSCmdlet.ParameterSetName -eq "UserManagedIdentity") {
                    $ConnectSplat.Add("ClientId", $ClientId)
                    $ConnectSplat.Add("Identity", $true)
                }
                if ($PSCmdlet.ParameterSetName -eq "ClientId") {
                    $ConnectSplat.Add("ClientId", $ClientId)
                }
                if ($PSCmdlet.ParameterSetName -eq "Identity") {
                    $ConnectSplat.Add("Identity", $true)
                }
                if ($PSCmdlet.ParameterSetName -eq "AzIdentity") {
                    $ConnectSplat.Add("AccountId", $AccountId)
                    $ConnectSplat.Add("Identity", $true)
                }
                if ($PSCmdlet.ParameterSetName -eq "Token") {
                    $ConnectSplat.Add("AccessToken", $AccessToken)
                }
                try {
                    $CurrentContext = Connect-AzAccount @ConnectSplat -ErrorAction Stop
                    $ContextsAvailable = Get-AzContext -ListAvailable -ErrorAction Stop
                }
                catch {
                    return $null
                }
                $PotentialContext = $ContextsAvailable | Where-Object { $_.Tenant.Id -eq $TenantId -and $_.Subscription.Id -eq $SubscriptionId }
                if ($null -eq $PotentialContext) {
                    throw "Wanted context not found (TenantId '$TenantId'; SubscriptionId '$SubscriptionId')"
                }
                else {
                    $CurrentContext = $PotentialContext | Select-AzContext
                }
            }
            else {
                if ($PotentialContext.count -eq 1) {
                    $CurrentContext = $PotentialContext | Select-AzContext
                }
                else {
                    if ($PotentialContext.count -gt 1) {
                        Write-Error "Found multiple contexts"
                        Write-Output "For correct tenant and subscription:`n$($PotentialContext | Format-Table Name, Account, @{l="SubscriptionName";e={$_.Subscription.Name}}, @{l="TenantId";e={$_.Tenant.Id}} | Out-String -Width 300)Please remove unwanted context(s) with Remove-AzContext"
                        exit 1
                    }
                    else {
                        # Just a fail-safe, context isn't null but it's count is less than 1, or doesn't have count property
                        Write-Error "Found '$($PotentialContext.count)' Az contexts?! Exiting"
                        exit 1
                    }
                }
            }
        } # else: already correct context, going to return that
    }
    else {
        <# Graph API requires bit more - implementing later.
        try {
            $CurrentContext = Get-MgContext -ErrorAction Stop
        }
        catch {
            $CurrentContext = $null
        }
        if ($null -eq $CurrentContext) {
            $ConnectSplat = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                if ($key -ne "Context") {
                    $ConnectSplat.Add($key, $PSBoundParameters.$key)
                }
            }
            $CurrentContext = Connect-MgGraph @ConnectSplat -NoWelcome
        }
        # #>
    }
    return $CurrentContext
}

Function Get-User {
    <#
    .SYNOPSIS
        Abstraction function to enable different backends for getting user from domain.

    .DESCRIPTION
        This function enables simpler querying of users by utilizing splatting according to script requirements without too complex logic in the script itself
    #>
    [CmdletBinding(DefaultParameterSetName = "Local")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Filter,
        [Array]
        $Properties = @(),
        [Parameter(ParameterSetName = "Local", Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Server,
        [Parameter(ParameterSetName = "Local", Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        $Credential,
        [Parameter(ParameterSetName = "PSRemoting", Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]
        $Session,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        $Context,
        [Parameter(ParameterSetName = "EntraID", Mandatory)]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        [Switch]
        $EntraID,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon")]
        [swtich]
        $UseAzCmdlets,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        [swtich]
        $NoReconnect
    )
    if ($PSCmdlet.ParameterSetName -match "EntraID") {
        if (-not $NoReconnect.IsPresent) {
            $AzureSplat = @{}
            if ($UseAzCmdlets.IsPresent) {
                $AzureSplat.Add("UseAzCmdlets", $true)
            }
            if ($null -ne $Context) {
                $AzureSplat.Add("TenantId", $Context.Tenant.Id)
                $AzureSplat.Add("SubscriptionId", $Context.Subscription.Id)
            }
            try {
                Get-AzureConnection @AzureSplat | Out-Null
            }
            catch {
                return $null
            }
        }
        $_Filter = ($Filter -replace " -", " ") -replace "distinguishedName", "UserPrincipalName"
        try {
            $AzUser = Get-AzADUser -Filter $_Filter
        }
        catch {}
        $dn = $null
        if ($null -ne $AzUser.AdditionalProperties.onPremisesDistinguishedName) {
            $dn = $AzUser.AdditionalProperties.onPremisesDistinguishedName
        }
        $sam = $null
        if ($null -ne $AzUser.AdditionalProperties.onPremisesSamAccountName) {
            $sam = $AzUser.AdditionalProperties.onPremisesSamAccountName
        }
        # Skipping objectClass and objectClass
        $User = [PSCustomObject]@{
            SID               = @{value = $AzUser.Id }
            UserPrincipalName = $AzUser.UserPrincipalName
            distinguishedName = $dn
            Enabled           = $AzUser.AccountEnabled
            Name              = $AzUser.DisplayName
            GivenName         = $AzUser.GivenName
            Surname           = $AzUser.Surname
            SamAccountName    = $sam
        }
        foreach ($property in $Properties) {
            if ($null -ne $AzUser.$property) {
                $User | Add-Member -MemberType NoteProperty -Name $property -Value $AzUser.$property
            }
        }
    }
    else {
        $Splat = @{"Filter" = $Filter }
        if ($Properties.Count -gt 0) {
            $Splat["Properties"] = $Properties
        }
        if ($PSCmdlet.ParameterSetName -eq "Local") {
            $Splat["Server"] = $Server
            $Splat["Credential"] = $Credential
            try {
                $User = Get-AdUser @Splat
            }
            catch {}
        }
        if ($PSCmdlet.ParameterSetName -eq "PSRemoting") {
            try {
                # Super clunky but you can't just @($Using:Splat) as that's actually inserting the splat-hashtable as an array as only parameter - which doesn't work.
                $User = Invoke-Command -Session $Session -ArgumentList $Splat -ScriptBlock { $Splat = $args[0]; Get-ADUser @Splat }
            }
            catch {}
        }
    }
    return $User
}
Function Get-GroupMember {
    <#
    .SYNOPSIS
        Abstraction function to enable different backends for getting group members from domain.

    .DESCRIPTION
        This function enables simpler querying of group mmebers by utilizing splatting according to script requirements without too complex logic in the script itself
    #>
    [CmdletBinding(DefaultParameterSetName = "Local")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Group,
        [Switch]
        $Recursive,
        [Parameter(ParameterSetName = "Local", Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Server,
        [Parameter(ParameterSetName = "Local", Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        $Credential,
        [Parameter(ParameterSetName = "PSRemoting", Mandatory)]
        [System.Management.Automation.Runspaces.PSSession]
        $Session,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        $Context,
        [Parameter(ParameterSetName = "EntraID", Mandatory)]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        [Switch]
        $EntraID,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon")]
        [switch]
        $UseAzCmdlets,
        [Parameter(ParameterSetName = "EntraID")]
        [Parameter(ParameterSetName = "EntraID-NoRecon", Mandatory)]
        [switch]
        $NoReconnect
    )
    if ($PSCmdlet.ParameterSetName -eq "EntraID") {
        if (-not $NoReconnect.IsPresent) {
            $AzureSplat = @{}
            if ($UseAzCmdlets.IsPresent) {
                $AzureSplat.Add("UseAzCmdlets", $true)
            }
            if ($null -ne $Context) {
                $AzureSplat.Add("TenantId", $Context.Tenant.Id)
                $AzureSplat.Add("SubscriptionId", $Context.Subscription.Id)
            }
            try {
                Get-AzureConnection @AzureSplat | Out-Null
            }
            catch {
                return $null
            }
        }
        try {
            $results = Get-AzADGroupMember -GroupDisplayName $Group -WarningAction SilentlyContinue
        }
        catch {}
        $Members = foreach ($user in $results) {
            $dn = $null
            if ($null -ne $user.AdditionalProperties.onPremisesDistinguishedName) {
                $dn = $user.AdditionalProperties.onPremisesDistinguishedName
            }
            $sam = $null
            if ($null -ne $AzUser.AdditionalProperties.onPremisesSamAccountName) {
                $sam = $AzUser.AdditionalProperties.onPremisesSamAccountName
            }
            # Skipping objectClass and objectClass
            [PSCustomObject]@{
                SID               = @{value = $user.Id }
                UserPrincipalName = $user.UserPrincipalName
                distinguishedName = $dn
                SamAccountName    = $sam
            }
        }
    }
    else {
        $Splat = @{"Identity" = $Group }
        if ($Recursive.IsPresent) {
            $Splat["Recursive"] = $true
        }
        if ($PSCmdlet.ParameterSetName -eq "Local") {
            $Splat["Server"] = $Server
            $Splat["Credential"] = $Credential
            try {
                $Members = Get-ADGroupMember @Splat
            }
            catch {}
        }
        if ($PSCmdlet.ParameterSetName -eq "PSRemoting") {
            try {
                # Super clunky but you can't just @($Using:Splat) as that's actually inserting the splat-hashtable as an array as only parameter - which doesn't work.
                $Members = Invoke-Command -Session $Session -ArgumentList $Splat -ScriptBlock { $Splat = $args[0]; Get-AdGroupMember @Splat }
            }
            catch {}
        }
    }
    return $Members
}

Function FilterUPN {
    <#
    .SYNOPSIS
    Basically as Where-Object, but with enough data, it's orders of magnitude faster. See the comments in cases for Where-Object example.
    With enough data will meet threshold of on-the-fly compiling, which is the main reason for the performance.

    .NOTES
    Yes, the amount of different ParameterSets is pure madness but this filter is rather versatile so ¯\_(ツ)_/¯
    #>
    [CmdLetBinding()]
    param(
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "notnull")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "isnull")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "array")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "invert-array")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "reverse-array")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "reverse-invert-array")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "string")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "invert-string")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "multidimensionalarray")]
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        $pipe,
        [parameter(Mandatory, ParameterSetName = "notnull")]
        [parameter(Mandatory, ParameterSetName = "isnull")]
        [parameter(Mandatory, ParameterSetName = "array")]
        [parameter(Mandatory, ParameterSetName = "reverse-array")]
        [parameter(Mandatory, ParameterSetName = "invert-array")]
        [parameter(Mandatory, ParameterSetName = "reverse-invert-array")]
        [parameter(Mandatory, ParameterSetName = "string")]
        [parameter(Mandatory, ParameterSetName = "invert-string")]
        [parameter(Mandatory, ParameterSetName = "multidimensionalarray")]
        [parameter(Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        [string]
        $field,
        [parameter(Mandatory, ParameterSetName = "array")]
        [parameter(Mandatory, ParameterSetName = "reverse-array")]
        [parameter(Mandatory, ParameterSetName = "invert-array")]
        [parameter(Mandatory, ParameterSetName = "reverse-invert-array")]
        [parameter(Mandatory, ParameterSetName = "multidimensionalarray")]
        [parameter(Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        $array,
        [parameter(Mandatory, ParameterSetName = "string")]
        [parameter(Mandatory, ParameterSetName = "invert-string")]
        [parameter(Mandatory, ParameterSetName = "multidimensionalarray")]
        [parameter(Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        [string]
        $string,
        [parameter(Mandatory, ParameterSetName = "multidimensionalarray")]
        [parameter(Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        [switch]
        $multidimensional,
        [parameter(Mandatory, ParameterSetName = "notnull")]
        [switch]
        $NotNull,
        [parameter(Mandatory, ParameterSetName = "isnull")]
        [switch]
        $IsNull,
        [parameter(Mandatory, ParameterSetName = "reverse-array")]
        [parameter(Mandatory, ParameterSetName = "reverse-invert-array")]
        [Alias("FieldIsArray")]
        [switch]
        $reverse,
        [parameter(Mandatory, ParameterSetName = "invert-array")]
        [parameter(Mandatory, ParameterSetName = "reverse-invert-array")]
        [parameter(Mandatory, ParameterSetName = "invert-string")]
        [parameter(Mandatory, ParameterSetName = "invert-multidimensionalarray")]
        [switch]
        $invert
    )
    Process {
        # This might be tad slower than if-elseif-elseif but it's more readable. Amount of evaluations should be lower however, and switch is about as fast as if-elseif-elseif-elseif
        switch ($PSCmdlet.ParameterSetName) {
            "notnull" {
                if ($null -ne $pipe.$field) {
                    # Where-Object {$null -ne $_.field}
                    $pipe
                }
                break
            }
            "isnull" {
                if ($null -eq $pipe.$field) {
                    # Where-Object {$null -eq $_.field}
                    $pipe
                }
                break
            }
            "array" {
                if ($pipe.$field -in $array) {
                    # Where-Object {$_.field -in $array}
                    $pipe
                }
                break
            }
            "invert-array" {
                if ($pipe.$field -notin $array) {
                    # Where-Object {$_.field -notin $array}
                    $pipe
                }
                break
            }
            "reverse-array" {
                # !! NOTE: this doesn't care the type of $array - it's just an object, even if it's typically string despite variable name.
                if ($pipe.$field -contains $array) {
                    # Where-Object {$_.field -contains $array}
                    $pipe
                }
                break
            }
            "reverse-invert-array" {
                # !! NOTE: this doesn't care the type of $array - it's just an object, even if it's typically string despite variable name.
                if ($pipe.$field -notcontains $array) {
                    # Where-Object {$_.field -notcontains $array}
                    $pipe
                }
                break
            }
            "string" {
                if ($pipe.$field -eq $string) {
                    # Where-Object {$_.field -eq "string"}
                    $pipe
                }
                break
            }
            "invert-string" {
                if ($pipe.$field -ne $string) {
                    # Where-Object {$_.field -ne "string"}
                    $pipe
                }
                break
            }
            "multidimensionalarray" {
                if ($pipe.$array.$field -eq $string) {
                    # Where-Object {$_.array.field -eq "string"}
                    $pipe
                }
                break
            }
            "invert-multidimensionalarray" {
                if ($pipe.$array.$field -ne $string) {
                    # Where-Object {$_.array.field -ne "string"}
                    $pipe
                }
                break
            }
        }
    }
}

Function Invoke-ApiQuery {
    <#
    .SYNOPSIS
    As Invoke-RestMethod but parses and returns the response if web request returned 4xx or 5xx error, unlike Invoke-RestMethod
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $Uri,
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method = "Get",
        $Body,
        [string]
        $ContentType = "application/json",
        [PSCredential]
        $Credential,
        [switch]
        $DisableKeepAlive,
        [string]
        $Authentication,
        [System.Collections.IDictionary]
        $Headers
    )
    try {
        $response = Invoke-RestMethod @PSBoundParameters
    }
    catch {
        if ($null -ne $_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $response = $reader.ReadToEnd()
        }
        else {
            $response = $_
        }
        throw $response
    }
    return $response
}

Function New-HttpQueryUri {
    <#
    .SYNOPSIS
    Generate URI for GET request with query parameters.
    #>
    param(
        [Parameter(Mandatory)]
        [Hashtable]
        $QueryParameters,
        [Parameter(Mandatory)]
        [string]
        $Uri
    )
    $UriBuilder = [System.UriBuilder]::new($Uri)
    $nvCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($key in $QueryParameters.Keys) {
        $nvCollection.Add($key, $QueryParameters.$key) | Out-Null
    }
    # nvCollection is internally HttpValueCollection, which has override for .ToString()
    # That uses class [System.Web.HttpUtility]::UrlEncodeUnicode to encode the uri
    # which results unicode values to the output, so, %uXXXX, which isn't wanted.
    # Hence, we need to create the whole URI here with [System.UriBuilder] and decode
    # unicode encoded uri for the query parameters as that is actually encoding it
    # correctly. #Just.NETthings 😩
    $uribuilder.Query = [system.web.httputility]::UrlDecode($nvCollection.ToString())
    return $uribuilder.Uri.AbsoluteUri
}

Function Test-DCConnectivity {
    <#
    .SYNOPSIS
    Resolve DC DNS address and try to get test user with provided credentials, returning IP address if user was found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]
        $dc,
        [Parameter(Mandatory)]
        [string]
        $Username,
        [Parameter(Mandatory)]
        [PSCredential]
        $Credential
    )
    try {
        $dcip = [array][System.Net.Dns]::GetHostEntry($dc).addresslist.ipaddresstostring
    }
    catch {
        $dcip = @($dc)
    }
    if ($UserName -match "\\") {
        $testuser = ($UserName -split "\\")[1]
    }
    else {
        $testuser = $UserName
    }
    $ReachedDCIP = foreach ($ip in $dcip) {
        try {
            if ($UserName -match "@") {
                $user = Get-ADUser -Filter "UserPrincipalName -eq '$($UserName)'" -Server $ip -Credential $Credential -ErrorAction Stop
            }
            else {
                $user = Get-ADUser $testuser -Server $ip -Credential $Credential -ErrorAction Stop
            }
        }
        catch {
            throw $_
        }
        if ($user) {
            $ip
        }
    }
    return $ReachedDCIP
}

Function Write-Info {
    <#
    .SYNOPSIS
    Syntax is almost identical to string formater, but print to information stream and prefix it with timestmap. Supports intentation with spaces.
    #>
    param(
        [int]
        $intentation = 0,
        [Alias("f")]
        [string[]]
        $infoStrings = @(),
        [string]
        $template = ""
    )
    $formatArray = @("") + $infoStrings
    Write-Information ("{0,$intentation}$(Get-Timestamp) $template" -f $formatArray)
}

Function Get-Timestamp {
    <#
    .SYNOPSIS
    Returns [<timestamp>] with format of yyyy-MM-dd HH:mm:ss.fff
    #>
    return "[$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff"))]"
}
