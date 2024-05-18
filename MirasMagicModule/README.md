Using MirasMagicModule:
* Copy the whole directory to desired location
* Import it like this, note that it assumes the directory is next to script. Tune accordingly. The comment is mandatory ;)

```powershell
# *Grabs wand* ACCIO MMM!
Import-Module .\MirasMagicModule
if($null -eq (Get-Module MirasMagicModule)){
    Write-Error -Message "Importing MirasMagicModule was unsuccessful" -Category ResourceUnavailable -CategoryActivity "Import-Module .\MirasMagicModule"
    exit
}
```

After import, you can get available commands and help for the commands:
```powershell
Get-Command -Module MirasMagicModule
Get-Help <#command, eg. Get-Ticket#> -detailed
```

Integrated help and tab-complete works in IDE (like Visual Studio Code) if you import the module from the integrated terminal.
