<powershell>
$Password = ConvertTo-SecureString "${admin_password}" -AsPlainText -Force

if (Get-LocalUser -Name "labadmin" -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name "labadmin" -Password $Password
} else {
    New-LocalUser -Name "labadmin" -Password $Password -PasswordNeverExpires
}

Add-LocalGroupMember -Group "Administrators" -Member "labadmin" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
</powershell>