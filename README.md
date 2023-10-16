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

- `C8Y_HOST`: The URL towards your tenant (for example: "https://eos.eu-latest.cumulocity.com")
- `C8Y_TENANT`: The Tenant ID (for example: "t570403874")
- `C8Y_USER`: Your username without tenant-id prefixed (for example: "korbinian.butz@softwareag.com")
- `C8Y_PASSWORD`: Your super secret password (for example: "my-secret-pass")
- `C8Y_SETTINGS_CI`: Disables all prompts, leave this `true`
- `RT_NEW_GROUP_NAME`: The name of your new user role (for example: "devices replica")
- `RT_DELETE_NEWUSERGROUP_IF_EXISTS`: This variable defines what should happen in case there is already a user role with the desired new group name in the tenant:
  - When set to "true"/"TRUE", the script will remove the old one and recreate it based on 'devices' role (useful for testing)
  - When set to "false"/"FALSE", the script will abort migration and not touch this tenant (preferred for production)

All stated environment variables are mandatory.

# Exit Codes

Script is using exit codes to indicate its success. Exit Code is also printed towards stdout:

- 0: "Migration was needed and done" X
- 100: "No devices role in this tenant, nothing to migrate" X
- 101: "No users in tenant, nothing to migrate" X
- 102: "New-Role already existing and should not be re-created" X
- 200: "Issue with input parameters" X
- 201: "Connectivity issue to platform" X
- 202: "Devices role has applications assigned, to be fixed manually before migration." X
- 203: "An error occured while searching for users with devices role" X
- 204: "User not having required permissions" 

(Rule: 0 = success, 1XX tenant not in migration scope, 2XX errors to take care of)

# Auditing

Script is creating one audit log entry in the tenant once it starts:

```json
{
  "activity": "Devices-Usergroup-Migration script runtime",
  "creationTime": "2023-10-16T19:02:10.522Z",
  "id": "162877460",
  "self": "https://t570403874.eu-latest.cumulocity.com/audit/auditRecords/162877460",
  "severity": "information",
  "text": "Devices-Usergroup-Migration script started.",
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
  "self": "https://t570403874.eu-latest.cumulocity.com/audit/auditRecords/162878454",
  "severity": "information",
  "text": "Devices-Usergroup-Migration script finished with Exit Code 101",
  "time": "2023-10-16T19:02:10.682Z",
  "type": "migrationScriptRuntime",
  "user": "korbinian.butz@softwareag.com"
}
```
