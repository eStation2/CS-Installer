***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 10 — Installation Type, Role, and Mode

**Version 1.0.0 — October 2026**

---

## 1. Overview

A Climate Station deployment is characterised by three related settings that
determine how it behaves and what each user sees:

- **Installation type** (`type_installation`) — the overall deployment kind.
- **Role** (`role`) — only for the two-machine (`double`) setup: which half of the
  pair this machine is.
- **Mode** (`mode`) — only for the `double` setup: the current operating state,
  shown in the interface as **Current mode**.

These are visible in the web interface under **System Settings** and in the
`GET /systemsettings` response (as `type_installation`, `role`, and
`current_mode`).

## 2. Installation type (`type_installation`)

Set at install time (via the `TYPE_OF_INSTALLATION` value) and written to the
system settings.

| Value | Meaning |
|-------|---------|
| `full` | Default standalone install — all modules, local login. |
| `Server` | Server deployment — no data/DB sync, no SPIRITS conversion, no FTP push. |
| `SinglePC` | Single machine — no data/DB sync. |
| `double` | Two-machine (CLIMSA) setup: a **processing** PC and an **analysis** PC kept in sync. Adds `role` and `mode` (below). |
| `jrc_online` | JRC hosted online service — EU/ECAS login, restricted menus. |

The installation type controls, among other things, which background sync runs,
which login screen appears, and which menu items are visible to each user level.

> **Tecnavia deployments use `double`** (with BBE single-sign-on). See Section 5.

## 3. Role (`role`) — `double` only

On a `double` deployment the two machines split the work:

| Role | Responsibility |
|------|----------------|
| `processing` | Runs acquisition, ingestion, and processing; shows those modules. |
| `analysis` | Runs the analysis/visualisation side; shows the analysis modules. |

The role determines which database schemas synchronise between the two machines
and which menu items are shown. On non-`double` installations, role is not used.

## 4. Mode (`mode` / "Current mode") — `double` only

On a `double` deployment the **mode** governs whether the two machines actively
synchronise:

| Mode | Meaning |
|------|---------|
| `nominal` | Normal operation — synchronisation runs between the two machines. |
| `recovery` | One machine is recovering — synchronisation is suspended to avoid conflicts. |
| `maintenance` | Maintenance — synchronisation is stopped. |

The interface shows this as **Current mode**. In `nominal` mode the machines sync
(unless the paired machine reports `recovery`/unreachable); in `recovery` or
`maintenance` the sync is held off.

## 5. Tecnavia (BBE) deployment

The Tecnavia deployment is a `double` installation using **BBE single-sign-on**:

- `type_installation` = `double`
- `role` and `mode` apply as described above.
- User accounts are managed by the SSO provider, not the local user table
  (see Chapter 3).
- Start/stop uses the Tecnavia path and user/group flags (see Chapter 9, Section
  5.1).

## 6. Viewing and changing these settings

### View

- In the web interface: **System Settings** shows the installation type, role, and
  Current mode.
- Via API (read-only): `GET /systemsettings` returns `type_installation`, `role`,
  and `current_mode`.

### Change

Role and mode can be changed from the System Settings interface. The equivalent
API calls are:

```
GET /systemsettings/changerole?role=<processing|analysis>
GET /systemsettings/changemode?mode=<nominal|recovery|maintenance>
```

> ⚠️ Changing **role** or **mode** affects synchronisation on a `double`
> deployment and should be coordinated across **both** machines. Do not change
> these casually on a production pair — set the correct values with the paired
> machine's state in mind.
>
> **Installation type** (`type_installation`) is set at install time and should
> not be changed on a running deployment without a planned reconfiguration.

## 7. Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Expected menus missing | Menu visibility depends on `type_installation` + user level (+ role on `double`) | Confirm the installation type and the user's level |
| No synchronisation between the two machines | Not in `nominal` mode, or the paired machine is in `recovery`/unreachable | Set both machines to `nominal`; check the paired machine's state |
| "Current mode" shows an unexpected value | Mode left in `recovery`/`maintenance` | Set back to `nominal` once recovery/maintenance is complete |
| Role settings have no effect | Not a `double` installation | Role/mode apply only to `double` |

## 8. Notes

- `role` and `mode` are only meaningful on `double` installations; on
  `full`/`Server`/`SinglePC`/`jrc_online` they are unused.
- These settings influence background behaviour (sync) and the interface
  (menus, login) — they are deployment-level settings, not per-user.
