# Cross-Platform Service Management & Supervision

Standards for background daemon execution, service supervision, and process
lifecycles across platforms.

---

## 1. Local Development: `pitchfork`

For managing background dependencies (API servers, workers, mock services)
during local development:

```toml
# pitchfork.toml

[services.api]
command = "cargo run --bin server"
watch = ["src/", "Cargo.toml"]
autostart = true

[services.worker]
command = "cargo run --bin worker"
watch = ["src/worker/"]
autostart = false
```

---

## 2. Linux: Systemd User Services

For persistent user-level services on Linux systems:

```ini
# ~/.config/systemd/user/<app>.service

[Unit]
Description=<App Name> User Service
After=network.target

[Service]
Type=exec
ExecStart=%h/.local/bin/<app> daemon
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10s

# Ephemeral runtime directory in $XDG_RUNTIME_DIR/<app>
RuntimeDirectory=<app>
WorkingDirectory=%h

[Install]
WantedBy=default.target
```

- Enable and start: `systemctl --user enable --now <app>.service`
- Check logs: `journalctl --user -u <app>.service -f`

---

## 3. macOS: Launchd Agents

For persistent user-level services on macOS:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.<user>.<app></string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/<app></string>
        <string>daemon</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>~/Library/Logs/<app>/stdout.log</string>

    <key>StandardErrorPath</key>
    <string>~/Library/Logs/<app>/stderr.log</string>
</dict>
</plist>
```

- Install location: `~/Library/LaunchAgents/com.<user>.<app>.plist`
- Bootstrap: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.<user>.<app>.plist`

---

## 4. Windows 11: Service Management & Tasks

### A. Windows Service Control Manager (SCM)

For headless Windows services:

- Implement standard SCM control code handlers:
  - `SERVICE_CONTROL_STOP` $\rightarrow$ Trigger graceful shutdown.
  - `SERVICE_CONTROL_SHUTDOWN` $\rightarrow$ Immediate state flush.
- Install via PowerShell (Administrator):
  ```powershell
  New-Service -Name "<App>" -BinaryPathName "C:\path\to\<app>.exe daemon" -StartupType Automatic
  Start-Service -Name "<App>"
  ```

### B. User-Level Scheduled Tasks (Windows 11)

For persistent background user tasks without Administrator privileges:

```powershell
$action = New-ScheduledTaskAction -Execute "$HOME\.local\bin\<app>.exe" -Argument "daemon"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "<App>UserService" -Action $action -Trigger $trigger -Settings $settings
```

---

## 5. Process Lifecycle & Signal Contract

All daemons and services must obey deterministic signal contracts:

| Signal / Event | Action Required |
| :--- | :--- |
| `SIGTERM` / `SIGINT` | Stop accepting new requests, drain existing tasks, flush state to disk, and exit 0 within 10 seconds. |
| `SIGHUP` | Reload configuration from `$XDG_CONFIG_HOME/<app>/` without dropping connections. |
| Unhandled Panic / Crash | Write crash traceback to `$XDG_STATE_HOME/<app>/crash.log` and exit with non-zero status. |
