# AxMclub.com — operator tooling
A short guide to the free apps used to manage this VPS.
## Install in one shot
On the VPS, elevated PowerShell:
```powershell
cd C:\apps\axmclub
git pull
.\deploy\install-server-tools.ps1
# or: .\deploy\install-server-tools.ps1 -IncludeRainmeter
```
Installs **VS Code**, **Notepad++**, **Sysinternals Suite**, **bottom**, **AnyDesk**, and **jq** via winget. Optionally installs **Rainmeter** with `-IncludeRainmeter`.
## Tools that need browser / Store steps
### Windows Admin Center (the big one)
The closest thing to a "free Plesk" for Windows Server. Browser UI for services, files, scheduled tasks, performance, certificates, firewall, registry.
1. On the VPS, open **https://aka.ms/WACDownload** in Edge.
2. Download the MSI (~120 MB).
3. Run the installer. Accept the cert prompts; choose port `6516` (default).
4. After install, browse to **https://localhost:6516** on the VPS.
5. Click **+ Add** → **Server connection** → enter `localhost` → **Add**.
6. Optional remote access: open port `6516` in Windows Firewall + Cloudflare (or, better, expose via a Cloudflare Tunnel).
### Files (modern Explorer)
Microsoft Store app. Tabs, dual-pane, dark mode.
1. Start menu → **Microsoft Store**.
2. Search **Files** (publisher: Files).
3. Click **Get**.
If the Store isn't installed on Server SKU, download the appx from https://files.community/ and sideload via PowerShell:
```powershell
Add-AppxPackage -Path .\Files.msixbundle
```
### UptimeRobot (external uptime monitoring)
1. https://uptimerobot.com → **Sign up free**.
2. **Add New Monitor**:
   - Type: **HTTP(S)**
   - Friendly name: `AxMclub home`
   - URL: `https://axmcamclub.com/`
   - Monitoring interval: **5 minutes**
3. Click **Create**, then add a second monitor:
   - Type: **HTTP(S) Keyword**
   - URL: `https://axmcamclub.com/api/stats`
   - Keyword: `members`
   - Alert: **When keyword is NOT present**
4. **My Settings → Alert Contacts** → add email + (optionally) Telegram bot.
### AnyDesk (replaces UltraVNC)
Faster, smoother remote desktop than UltraVNC. The installer puts AnyDesk on the VPS as both a host and a client.
1. The install script (`install-server-tools.ps1`) installs AnyDesk on the VPS automatically.
2. Open AnyDesk on the VPS once -- it shows a 9-digit **AnyDesk ID** under "This Desk".
3. Install AnyDesk on your dev box: `winget install AnyDeskSoftwareGmbH.AnyDesk`.
4. From your dev box, type the VPS's AnyDesk ID into the "Remote Desk" box and hit **Connect**.
5. The VPS will prompt to accept the connection (or set an unattended-access password under **Settings -> Security**; only do this if the AnyDesk install is on a server you fully trust).
Free for personal use; commercial use needs a license.
### CrowdSec (skip for now)
Their Windows agent is preview / experimental as of this writing. Linux-first project. Revisit when they GA Windows.
## Daily-use shortcuts
After install, pin these to the VPS taskbar:
- **Process Explorer** (`procexp`) — better Task Manager
- **TCPView** (`tcpview`) — see who's connected to what port
- **VS Code** — `code C:\apps\axmclub` to edit the project
- **Notepad++** — `notepad++ C:\Caddy\logs\caddy.out.log` then **View → Document → Monitoring** to live-tail Caddy logs
## Useful quick commands (in any VPS PowerShell)
```powershell
# Tail Caddy log live
Get-Content C:\Caddy\logs\caddy.out.log -Tail 30 -Wait
# See active TCP connections
Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table
# Pretty-print db.json (requires jq: winget install jqlang.jq)
Get-Content C:\apps\axmclub\data\db.json | jq '.users | keys'
# Check service health
Get-Service axmclub, caddy | Format-Table Name, Status, StartType
# Quick HTTPS smoke test from the VPS itself
(Invoke-RestMethod https://axmcamclub.com/api/stats)
```
