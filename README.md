# windows-10

Self-hosted **Windows 10** RDP runner for GitHub Actions.

This repository contains a workflow that turns a Windows 10 64-bit machine into an
RDP box reachable over Tailscale, and a script that registers that machine as a
self-hosted runner.

> Why self-hosted? GitHub-hosted runners only offer Windows Server images
> (`windows-2025`, `windows-2022`) and `windows-11-arm`. There is **no** hosted
> Windows 10 image — but Windows 10 64-bit **is** officially supported as a
> self-hosted runner.

---

## 1. Register the Windows 10 machine as a runner

On the Windows 10 machine, open **PowerShell as Administrator** and run:

```powershell
# get a fresh registration token (valid 1 hour) from any machine with gh installed:
gh api -X POST repos/Sweetcoinss/windows-10/actions/runners/registration-token --jq .token
```

Then on the Windows 10 machine:

```powershell
iwr https://raw.githubusercontent.com/Sweetcoinss/windows-10/main/register-runner.ps1 -OutFile $env:TEMP\register-runner.ps1
& $env:TEMP\register-runner.ps1 -RegistrationToken "PASTE_TOKEN_HERE"
```

The script downloads the official `actions/runner` (v2.338.0), registers it with the
label `windows-10`, installs it as a Windows service and starts it.

### Requirements

| Requirement | Why |
| --- | --- |
| Windows 10 **Pro / Enterprise**, 64-bit | RDP cannot be hosted on Home |
| Administrator rights | The workflow edits the registry, services and firewall |
| Node.js 18+ | Needed by the `Install OpenCode` step (`winget install OpenJS.NodeJS.LTS`) |
| Repository secret `TAILSCALE_AUTH_KEY` | Already configured in this repo |

---

## 2. Run the workflow

```powershell
gh workflow run my-custom-rdp.yml --repo Sweetcoinss/windows-10
gh run list --repo Sweetcoinss/windows-10
```

Or from the UI: **Actions → Windows RDP New → Run workflow**.

The job will start as soon as a runner with the `windows-10` label is online.

---

## What the workflow does

| Step | Action |
| --- | --- |
| 1 | Enables RDP, disables NLA, opens TCP 3389 |
| 2 | Creates admin user `RDP` / `12345`, disables UAC |
| 3 | Installs OpenCode (`opencode-ai`) and the `lm` launcher |
| 4 | Installs Tailscale |
| 5 | Connects Tailscale using `secrets.TAILSCALE_AUTH_KEY` |
| 6 | Installs Rtl Terminal |
| 7 | Keeps the session alive for 6 hours |

The workflow is an exact copy of `Sweetcoinss/my-rdp-repo`'s `my-custom-rdp.yml`,
with a single change:

```diff
-runs-on: windows-latest
+runs-on: [self-hosted, windows-10]
```

> **Note:** `timeout-minutes` is 3600 (60 minutes) while the last step waits 6 hours,
> so the job is cut off after one hour unless you raise that value.
