# About

In Cumulocity, the "devices" role is meant to be used for devices only. There are tenants with this role assigned to regular User. This Service fixes this with executing following steps:

1. Create backup files from all users, device-Users and user roles/permissions
2. Find the `devices` role in the tenant (exit if not found)
3. Update description of devices to make clear it should not be used for human users
4. Find all human/regular users having this role assigned (exit if there are none)
5. Copy `devices` role towards a new role, including its permissions
6. Assign all users from `devices` this new role
7. Unassign `devices` from all regular users (NOT from devices)

# Prerequisites

1. Access to Tenants
2. Docker running
3. User with below permissions:

* ROLE_AUDIT_ADMIN
* ROLE_USER_MANAGEMENT_ADMIN
* ROLE_USER_MANAGEMENT_READ
* ROLE_USER_MANAGEMENT_CREATE
* ROLE_INVENTORY_CREATE
* ROLE_INVENTORY_READ
* ROLE_INVENTORY_ADMIN



# Build the image

Navigate with a shell session towards the current directory and execute: `docker build -t role-migration:latest .`

# Run image

1. Update vars.env. See below description of environment variables to set them properly.
2. Run the image `docker run --env-file vars.env --rm -v $PWD/:/sessions/ role-migration:latest >> migration.logs`. Important notes:
   - The standard output is relevant and useful for debugging Redirect it to a local file via `>>migration.logs`. You'll find all logs in this file then.
   - Make sure to use the `-v` to mount your localhost towards the container. The script will write backup files and runtime information - without binding volume, they are lost.
   - Could be `$PWD` does not work on Windows machine. If not, try `${PWD}` or `$(pwd)`
3. As one of the first steps, the script is creating `{tenantID}_backup_*.json` files. Make sure they are available on your localhost - if not double-check volume mount.

# Environment Variables

The following environment variables need to be set in your vars.env:

| Variable                           | Description                                                                                                                   |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `C8Y_HOST`                         | The URL towards your tenant (for example: ")                                           |
| `C8Y_TENANT`                       | The Tenant ID (for example: "t1234")                                                                                          |
| `C8Y_USER`                         | Your username without tenant-id prefixed (for example: "korbinian.butz@softwareag.com")                                       |
| `C8Y_PASSWORD`                     | Your super secret password (for example: "my-secret-pass")                                                                    |
| `C8Y_SETTINGS_CI`                  | Disables all prompts, leave this `true`                                                                                       |
| `RT_NEW_GROUP_NAME`                | The name of your new user role (for example: "devices replica")                                                               |
| `RT_DELETE_NEWUSERGROUP_IF_EXISTS` | This variable defines what should happen in case there is already a user role with the desired new group name in  the tenant: |

-   When set to "true"/"TRUE", the script will remove the old one and recreate it based on 'devices' role (useful for testing)
-   When set to "false"/"FALSE", the script will abort migration and not touch this tenant (preferred for production) |

All stated environment variables are mandatory.

# Exit Codes

Script is using exit codes to indicate its success. Exit Code is also printed towards stdout:

| Exit Code | Description                                                                     |
|-----------|---------------------------------------------------------------------------------|
| 0         | Migration was needed and done"                                                  |
| 100       | No devices role in this tenant, nothing to migrate"                             |
| 101       | No users with devices role in tenant, nothing to migrate"                       |
| 102       | New-Role already existing and should not be re-created"                         |
| 200       | Issue with input parameters"                                                    |
| 201       | Connectivity issue to platform"                                                 |
| 202       | Devices role has applications assigned, to be fixed manually before migration." |
| 203       | An error occured while searching for users with devices role"                   |
| 204       | User not having required permissions"                                           |

(Rule: 0 = success, 1XX tenant not in migration scope, 2XX errors to take care of)

# Auditing

Script is creating one audit log entry in the tenant once it starts:

```json
{
  "activity": "Devices-Usergroup-Migration script runtime",
  "creationTime": "2023-10-16T19:02:10.522Z",
  "id": "162877460",
  "self": "https://t1234.eu-latest.cumulocity.com/audit/auditRecords/162877460",
  "severity": "information",
  "text": "Devices-Usergroup-Migration script started",
  "time": "2023-10-16T19:02:08.377Z",
  "type": "migrationScriptRuntime",
  "user": "korbinian.butz@softwareag.com"
}
```

...and another one once it finishes:

```json
{
  "activity": "Devices-Usergroup-Migration script runtime",
  "creationTime": "2023-10-16T19:02:12.878Z",
  "id": "162878454",
  "self": "https://t1234.eu-latest.cumulocity.com/audit/auditRecords/162878454",
  "severity": "information",
  "text": "Devices-Usergroup-Migration script finished with Exit Code 101",
  "time": "2023-10-16T19:02:10.682Z",
  "type": "migrationScriptRuntime",
  "user": "korbinian.butz@softwareag.com"
}
```
# Log Output

A successful log output for a tenant migration looks as below. The last line always indicates the scripts exit code.

```
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Migrating Tenant 't1234' with URL 'https://examples.cumulocity.com'
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Current ENV Variables:
C8Y_SESSION_HOME=/sessions
C8Y_SETTINGS_CI=true
C8Y_USER=my-user
C8Y_TENANT=t1234
C8Y_HOST=https://examples.cumulocity.com
RT_DELETE_NEWUSERGROUP_IF_EXISTS=true
RT_NEW_GROUP_NAME=devices replica
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Current directory: /home/c8yuser
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Current date: Mon Oct 16 19:47:27 UTC 2023
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Check connectivity to tenant ...
Mon Oct 16 19:47:27 UTC 2023 - INF - main/1 - t1234 - Requested current tenant id 't1234'
Mon Oct 16 19:47:28 UTC 2023 - INF - main/1 - t1234 - Creating Audit Record to log script execution ...
Mon Oct 16 19:47:28 UTC 2023 - INF - main/1 - t1234 - Logged execution in audit log
Mon Oct 16 19:47:28 UTC 2023 - INF - main/1 - t1234 - Backup user groups ...
Mon Oct 16 19:47:28 UTC 2023 - INF - main/1 - t1234 - Backed up user group to t1234_backup_usergroups.json
Mon Oct 16 19:47:28 UTC 2023 - INF - main/1 - t1234 - Backup users ...
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Backed up users to t1234_backup_users.json
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Backup device users ...
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Backed up device users to t1234_backup_deviceusers.json
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Search for 'devices' user group, exit if not found...
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Checking if devices role has applications assigned. Exit if not.
Mon Oct 16 19:47:29 UTC 2023 - INF - main/1 - t1234 - Update description of devices role...
Mon Oct 16 19:47:30 UTC 2023 - INF - main/1 - t1234 - Updated description of devices role
Mon Oct 16 19:47:30 UTC 2023 - INF - main/1 - t1234 - Find all non-device users having devices role assigned; Exit in case there is none...
Mon Oct 16 19:47:30 UTC 2023 - INF - main/1 - t1234 - Found 2 Users to migrate:
john.doe@softwareag.com max.mustermann@softwareag.com
Mon Oct 16 19:47:30 UTC 2023 - INF - main/1 - t1234 - Check if there's already a user group defined for name 'devices replica' ...
Mon Oct 16 19:47:30 UTC 2023 - INF - main/1 - t1234 - Create new role ...
Mon Oct 16 19:47:31 UTC 2023 - INF - main/1 - t1234 - Created new role 'devices replica'
Mon Oct 16 19:47:31 UTC 2023 - INF - main/1 - t1234 - Add permissions from devices-role towards new role...
Mon Oct 16 19:47:31 UTC 2023 - INF - main/1 - t1234 - Added permissions from 'devices' towards new role
Mon Oct 16 19:47:31 UTC 2023 - INF - main/1 - t1234 - Give new role to all regular users with 'devices' role...
Mon Oct 16 19:47:32 UTC 2023 - INF - main/1 - t1234 - Assigned new role to all users that are assigned to 'devices'
Mon Oct 16 19:47:32 UTC 2023 - INF - main/1 - t1234 - Remove 'devices' role for same set of users...
Mon Oct 16 19:47:33 UTC 2023 - INF - main/1 - t1234 - Unassigned 'devices' role from respective users
Mon Oct 16 19:47:33 UTC 2023 - INF - main/1 - t1234 - Migration finished for 't1234' with URL 'https://exampls.cumulocity.com'
Mon Oct 16 19:47:33 UTC 2023 - INF - main/1 - t1234 - Logged execution in audit log.
Mon Oct 16 19:47:33 UTC 2023 - INF - main/1 - t1234 - Updated migration status in managed object 99162878444
Mon Oct 16 19:47:33 UTC 2023 - INF - main/1 - t1234 - Shutting down with exit code: 0 (C8Y_TENANT: t1234, C8Y_HOST: https://examples.cumulocity.com)
```