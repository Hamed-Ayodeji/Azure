Import-Module ServerManager
Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature
Install-WindowsFeature -Name Web-Asp-Net45
Install-WindowsFeature -Name NET-Framework-Features