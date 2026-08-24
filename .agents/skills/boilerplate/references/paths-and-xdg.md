# Standard Paths & XDG Compliance

Path resolution standards across platforms, applications, and workspaces.

---

## 1. Universal Default: XDG Base Directory Specification (v0.8)

By default, **all** CLI applications, developer tools, backend daemons,
scripts, and libraries on all operating systems (Linux, macOS, Windows, BSD)
must use and respect the XDG Base Directory specification.

### Base Directory Variables & Fallbacks

| Variable | Fallback Path | Intended Purpose |
| :--- | :--- | :--- |
| `XDG_CONFIG_HOME` | `$HOME/.config` | User-specific configuration files. |
| `XDG_DATA_HOME` | `$HOME/.local/share` | User-specific persistent data files. |
| `XDG_STATE_HOME` | `$HOME/.local/state` | Persistent state (history, logs, last-used). |
| `XDG_CACHE_HOME` | `$HOME/.cache` | Non-essential cached data (safe to delete). |
| `XDG_RUNTIME_DIR` | See Runtime Fallback | Ephemeral runtime sockets, pipes, and PIDs. |
| `XDG_CONFIG_DIRS` | `/etc/xdg` | System-wide configuration search paths. |
| `XDG_DATA_DIRS` | `/usr/local/share/:/usr/share/` | System-wide data search paths. |

### Runtime Directory Fallback

When `XDG_RUNTIME_DIR` is unset, implement a deterministic fallback
restricted to mode `0700` owned by the current user:

- **POSIX**: `${TMPDIR:-/tmp}/runtime-$(id -u)` (ensure `chmod 0700`).
- **Windows (non-native CLI)**: `%TEMP%\runtime-%USERNAME%`.

---

## 2. Native Platform Exceptions

The only exceptions to the universal XDG default are native platform
application types with dedicated operating system conventions:

### A. Native Win32 / Win64 GUI Applications

For native Windows desktop applications targeting Microsoft platform
standards:

- **Configuration / Roaming State**: `%APPDATA%\<Vendor>\<App>` (`FOLDERID_RoamingAppData`).
- **Local Data & State**: `%LOCALAPPDATA%\<Vendor>\<App>` (`FOLDERID_LocalAppData`).
- **Caches**: `%LOCALAPPDATA%\<Vendor>\<App>\Cache`.
- **Temporary Files**: `%TEMP%\<App>` or `%LOCALAPPDATA%\Temp`.

### B. Native macOS Application Bundles (`.app`)

For native macOS GUI applications structured as NeXTSTEP-style `.app`
bundles:

- **Application Data**: `~/Library/Application Support/<BundleID>/`
- **Preferences**: `~/Library/Preferences/<BundleID>.plist`
- **Caches**: `~/Library/Caches/<BundleID>/`
- **Logs**: `~/Library/Logs/<BundleID>/`
- **Dynamic Temp / User Dirs**: Query `getconf(1)` / `confstr(3)` keys:
  - `DARWIN_USER_DIR`
  - `DARWIN_USER_TEMP_DIR`
  - `DARWIN_USER_CACHE_DIR`

### C. Mobile & Embedded OS Applications

- **Android**: Use Android Context storage paths (`context.filesDir`,
  `context.cacheDir`, Scoped Storage).
- **iOS**: Use standard iOS App Sandbox container directories
  (`Documents/`, `Library/Application Support/`, `Library/Caches/`, `tmp/`).
- **WebOS / Tizen / Embedded**: Follow target OS SDK sandboxing standards.

---

## 3. Project-Level Host-Local Workspace Directories

When an individual repository needs host-local (uncommitted) storage for
intermediate state or tooling:

```
<repo-root>/
├── .local/
│   ├── share/                 # Host-local data assets
│   └── state/                 # Host-local state, session journals, logs
├── .cache/                    # Host-local build caches, index scratchpads
└── .gitignore                 # Must include .local/ and .cache/
```

- **Session Temp**: Use `$TMPDIR/<session-id>` (or `/tmp/<session-id>`).
- **Git Hygiene**: Add `.local/` and `.cache/` to `.gitignore` on first use.
