***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 3 — User Management

**Version 1.0.0 — October 2026**

---

## 1. Overview

This chapter applies to **standalone deployments** that use Climate Station's
local user system:

- A **new normal user** can be created from the web interface (self-registration).
- All other operations — **including password changes** — are done directly in
  the database. There is no change-password screen.

> **The `jrc_online` and Tecnavia deployments do not use the local user system.**
> `jrc_online` authenticates via EU/ECAS login, and the Tecnavia deployment uses
> BBE single-sign-on. On both, user accounts are managed externally by the SSO
> provider, self-registration is disabled, and the database procedures in this
> chapter do not apply.

## 2. User levels

| Level | Role | Access |
|-------|------|--------|
| 2 | Normal user | Analysis / viewing |
| 1 | Administrator | Full access (system settings, acquisition, processing, data management) |

Self-registration always creates a **level 2** user. Admin rights require setting
the level to **1** in the database.

## 3. Self-registration (web interface)

1. On the login screen, choose **Register**.
2. Enter the login id, full name, password, and (optional) email.
3. Submit. The account is created as a **normal (level 2)** user.

There is no password-reset screen; forgotten passwords are changed by an
administrator in the database (Section 4).

## 4. Database procedures

Open a database session:

```bash
docker exec -it postgres psql -U estation -d estationdb
```

Users are stored in `analysis.users` (`userid` is the login name; passwords are
plaintext, **max 32 characters**).

```sql
-- list users
SELECT userid, username, userlevel, email FROM analysis.users ORDER BY userlevel, userid;

-- change / reset a password
UPDATE analysis.users SET password = 'new_password' WHERE userid = 'login_id';

-- create an administrator (userlevel = 1)
INSERT INTO analysis.users (userid, username, password, userlevel, email, prefered_language)
VALUES ('admin2', 'Second Administrator', 'password', 1, 'admin2@example.org', 'eng');

-- promote / demote (1 = admin, 2 = normal)
UPDATE analysis.users SET userlevel = 1 WHERE userid = 'login_id';

-- delete a user
DELETE FROM analysis.users WHERE userid = 'login_id';
```

- Always include the `WHERE` clause and confirm one row changed.
- Password changes apply at next login; level changes apply after the user logs
  out and back in.

## 5. Notes

- Passwords are stored in plaintext (≤ 32 chars) — protect the database and its
  dumps, and never share or log password values.
- Deleting a user does not remove their saved workspaces, graphs, or map
  templates.
