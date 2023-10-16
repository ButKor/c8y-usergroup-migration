#!/bin/bash

declare -A levels=([DBG]=0 [INF]=1 [WRN]=2 [ERR]=3)
script_logging_level="INF"
log() {
  local log_message=$1
  local log_priority=$2
  local log_component="main/$(echo $$)"
  local proc_id=$(echo $$)
  [[ ${levels[$log_priority]} ]] || return 0
  ((${levels[$log_priority]} < ${levels[$script_logging_level]})) && return 0
  printf "%s - %3s - %s - %s - %s\n" "$(date)" "$log_priority" "$log_component" "$C8Y_TENANT" "$log_message"
}

shutdown() {
  local code=$1

  # create audit record to log execution
  c8y auditrecords create --severity information --type migrationScriptRuntime \
    --text "Devices-Usergroup-Migration script finished with Exit Code $code" \
    --activity "Devices-Usergroup-Migration script runtime" -f \
    --source "n.a." \
    >>"/sessions/${C8Y_TENANT}_auditLogs.json" 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    log "Error while trying to create audit record in shutdown routine. Return Code: $code" "WRN"
  else
    log "Logged execution in audit log." "INF"
  fi

  # Update Managed Object with status
  moid=$(c8y inventory list --type devicesRoleMigration -p 1 --select id -o csv 2>/dev/null)
  if [ -n "$moid" ]; then
    moid=$(c8y inventory update --id $moid --data "status=$code" --data type=devicesRoleMigration -f --select id -o csv 2>/dev/null)
  else
    moid=$(c8y inventory create --type devicesRoleMigration --data "status=$code" -f --select id -o csv 2>/dev/null)
  fi
  if [ -n "$moid" ]; then
    log "Updated migration status in managed object $moid" "INF"
  fi

  log "Shutting down with exit code: $1 (C8Y_TENANT: $C8Y_TENANT, C8Y_HOST: $C8Y_HOST)" "INF"
  exit $code
}

log "Migrating Tenant '$C8Y_TENANT' with URL '$C8Y_HOST'" "INF"
log "Current ENV Variables:" "INF"
printenv | grep 'C8Y' | grep -iv 'pass' | grep -iv 'auth'
printenv | grep 'RT_'
log "Current directory: $(pwd)" "INF"
log "Current date: $(date)" "INF"

# Check Input Variables
if [ -z "$RT_NEW_GROUP_NAME" ]; then
  log "Mandatory Environment Variable RT_NEW_GROUP_NAME is not set (this is the name of the new user role). Exiting now.", "ERR"
  shutdown 200
fi
if [ -z "$RT_DELETE_NEWUSERGROUP_IF_EXISTS" ]; then
  log "Mandatory Environment Variable RT_DELETE_NEWUSERGROUP_IF_EXISTS is not set. Exiting now." "ERR"
  shutdown 200
fi
if [ "$RT_DELETE_NEWUSERGROUP_IF_EXISTS" != "true" ] && [ "$RT_DELETE_NEWUSERGROUP_IF_EXISTS" != "TRUE" ] && [ "$RT_DELETE_NEWUSERGROUP_IF_EXISTS" != "false" ] && [ "$RT_DELETE_NEWUSERGROUP_IF_EXISTS" != "FALSE" ]; then
  log "Mandatory Environment Variable RT_DELETE_NEWUSERGROUP_IF_EXISTS is set to $RT_DELETE_NEWUSERGROUP_IF_EXISTS. This is not a supported value (supported: true,TRUE,false,FALSE). Exiting now." "ERR"
  shutdown 200
fi
if [ -z "$C8Y_TENANT" ]; then
  log "Mandatory Environment Variable C8Y_TENANT is not set. Exiting now." "ERR"
  shutdown 200
fi
if [ -z "$C8Y_HOST" ]; then
  log "Mandatory Environment Variable C8Y_HOST is not set. Exiting now." "ERR"
  shutdown 200
fi
if [ -z "$C8Y_USER" ]; then
  log "Mandatory Environment Variable C8Y_USER is not set. Exiting now." "ERR"
  shutdown 200
fi
if [ -z "$C8Y_PASSWORD" ]; then
  log "Mandatory Environment Variable C8Y_PASSWORD is not set. Exiting now." "ERR"
  shutdown 200
fi

# Check connectivity
log "Check connectivity to tenant ..." "INF"
tenant_id=$(c8y currenttenant get -o csv --select name 2>/dev/null)
code=$?
if [ $code -ne 0 ] || [ -z "$tenant_id" ]; then
  log "An error occured while requesting current tenant: return code=$code; output length=${#tenant_id}. Exiting now." "ERR"
  shutdown 201
fi
log "Requested current tenant id '$tenant_id'" "INF"

# Check permissions
permission_count=$(c8y currentuser get | jq -r '.effectiveRoles[].id' |
  grep -iE 'ROLE_AUDIT_ADMIN|ROLE_USER_MANAGEMENT_ADMIN|ROLE_USER_MANAGEMENT_READ|ROLE_USER_MANAGEMENT_CREATE|ROLE_INVENTORY_CREATE|ROLE_INVENTORY_READ|ROLE_INVENTORY_ADMIN' |
  wc -l | sed 's/ //g' 2>/dev/null)
if [ $permission_count -ne 7 ]; then
  log "User not having the required permissions. Please check README to see required permissions." "ERR"
  shutdown 204
fi

# Log execution in audit log
log "Creating Audit Record to log script execution ..." "INF"
c8y auditrecords create --severity information --source "n.a." --type migrationScriptRuntime \
  --text "Devices-Usergroup-Migration script started" \
  --activity "Devices-Usergroup-Migration script runtime" -f >"/sessions/${tenant_id}_auditLogs.json" 2>&1
code=$?
if [ $code -ne 0 ]; then
  log "Error while trying to create audit record in starting routine. Return Code:$code" "WRN"
else
  log "Logged execution in audit log" "INF"
fi

# Create backups
log "Backup user groups ..." "INF"
f="${tenant_id}_backup_usergroups.json"
c8y usergroups list --includeAll | jq -c >"/sessions/$f" 2>&1
log "Backed up user group to $f" "INF"

log "Backup users ..." "INF"
f="${tenant_id}_backup_users.json"
c8y users list --withSubusersCount --includeAll | jq -c >"/sessions/$f" 2>&1
log "Backed up users to $f" "INF"

log "Backup device users ..." "INF"
f="${tenant_id}_backup_deviceusers.json"
c8y users list --onlyDevices --includeAll | jq -c >"/sessions/$f" 2>&1
log "Backed up device users to $f" "INF"

### MIGRATION ####
log "Search for 'devices' user group, exit if not found..." "INF"
devices_group=$(c8y usergroups get --id devices 2>/dev/null)
code=$?
if [ $code -ne 0 ] || [ -z "$devices_group" ]; then
  log "An error occured while searching for 'devices' role. Seems there is none. Return code=$code; output length=${#devices_group}. Exiting now." "ERR"
  shutdown 100
fi

log "Checking if devices role has applications assigned. Exit if not." "INF"
app_count=$(c8y usergroups get --id devices | jq '.applications | length')
if [ $app_count -gt 0 ]; then
  log "Role 'devices' has applications assigned. This needs to be fixed manually. Exiting now." "ERR"
  shutdown 202
fi

log "Update description of devices role..." "INF"
echo $devices_group | c8y usergroups update --name devices \
  --data "description=This is a system-role meant for devics - do not assign it to regular users" \
  --force >"/sessions/${tenant_id}_updateUserGroup.json" 2>&1
log "Updated description of devices role" "INF"

log "Find all non-device users having devices role assigned; Exit in case there is none..." "INF"
users_in_devices_group=$(c8y userreferences listGroupMembership --id devices --includeAll |
  jq -r .id | grep -iv "device_")
code=$?
# grep exiting with code 1 in case term wasn't found
if [ $code -ne 0 ] || [ -z "$users_in_devices_group" ]; then
  if [ $code -eq 1 ]; then
    log "There's no user using the 'devices' role. Exiting now." "INF"
    shutdown 101
  else
    log "An error occured while searching for users with devices role: return code=$code; output length=${#users_in_devices_group}. Exiting now." "ERR"
    shutdown 203
  fi
fi
log "Found $(printf "%s\n" "${users_in_devices_group[@]}" | wc -l | sed 's/ //g') Users to migrate:" "INF"
echo $(printf "%s\n" "${users_in_devices_group[@]}")

log "Check if there's already a user group defined for name '$RT_NEW_GROUP_NAME' ..." "INF"
ug=$(c8y usergroups get --id "$RT_NEW_GROUP_NAME" --silentStatusCodes 404)
code=$?
if [ $code -eq 0 ] && [ -n "$ug" ]; then
  log "There is already a user group existing named '$RT_NEW_GROUP_NAME'" "INF"
  if [ $RT_DELETE_NEWUSERGROUP_IF_EXISTS == "true" ] || [ $RT_DELETE_NEWUSERGROUP_IF_EXISTS == "TRUE" ]; then
    log "Runtime is configured to delete new user group if it already exists. Deleting now." "INF"
    echo $ug | c8y usergroups delete -f >"/sessions/${tenant_id}_deleteExistingUsergroup.json" 2>&1
    log "Deleted user group" "INF"
  else
    log "Runtime not configured to delete new user group if it already exists. Exiting now." "WRN"
    shutdown 102
  fi
fi

log "Create new role ..." "INF"
new_user_group=$(echo $devices_group | jq 'del(.id,.self,.roles) | .description = ""' -c |
  c8y usergroups create --template input.value --name "$RT_NEW_GROUP_NAME" --force)
log "Created new role '$(echo $new_user_group | jq -r .name)'" "INF"

log "Add permissions from devices-role towards new role..." "INF"
devices_user_roles=$(echo $devices_group |
  c8y userroles getRoleReferenceCollectionFromGroup --includeAll --filter "role.id notlike ROLE_DEVICE" --select role.id -o csv)
code=$?
if [ $code -eq 0 ] && [ -n "$devices_user_roles" ]; then
  printf "%s\n" "${devices_user_roles[@]}" |
    c8y userroles addRoleToGroup --group $(echo $new_user_group | jq -r .id) --force >"/sessions/${tenant_id}_addRoleToGroup.json" 2>&1
  log "Added permissions from 'devices' towards new role" "INF"
else
  log "Role 'devices' has no permissions set. Did not copy any permissions to the new role." "WRN"
fi

log "Give new role to all regular users with 'devices' role..." "INF"
if [ -n "$users_in_devices_group" ]; then
  printf "%s\n" "${users_in_devices_group[@]}" |
    c8y userreferences addUserToGroup --group $(echo $new_user_group | jq -r .id) --force >"/sessions/${tenant_id}_addUserToGroup.json" 2>&1
  log "Assigned new role to all users that are assigned to 'devices'" "INF"
else
  log "There are no users in devices group. Did not assign the new role to any user." "INF"
fi

log "Remove 'devices' role for same set of users..." "INF"
if [ -n "$users_in_devices_group" ]; then
  printf "%s\n" "${users_in_devices_group[@]}" |
    c8y userreferences deleteUserFromGroup --group devices --force >"/sessions/${tenant_id}_deleteUserFromGroup.json" 2>&1
  log "Unassigned 'devices' role from respective users" "INF"
else
  log "There are no users in devices group. Did not remove it for any user." "INF"
fi

log "Migration finished for '$C8Y_TENANT' with URL '$C8Y_HOST'" "INF"
shutdown 0
