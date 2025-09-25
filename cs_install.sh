#!/usr/bin/env bash
#
set -u

# Base definitions
#
if ! which realpath &> /dev/null
then
    function realpath()
    {
        if [[ "${1}" == /* ]]
        then
            echo "${1}"
        else
            echo "${PWD}/${1#./}"
        fi
    }
fi

readonly BASE_DIR="$(realpath "$(dirname "${0}")")"
readonly BASE_FILE="$(basename "${0}")"

readonly CONFIG_DIR="${BASE_DIR}/.configs"

# Project versions:
readonly CONFIG_VERSION="1.1.3"

readonly JRC_IMAGE_REGISTRY="d-prd-registry.jrc.it/d6-estation"

# Template files:
#
readonly DFLT_ENV_FILE="${BASE_DIR}/.env"
readonly TMPL_ENV_FILE="${BASE_DIR}/.env.template"

readonly CS_IMAGES=("climatestation/postgis:latest"
                    "climatestation/cstation:latest"
                    )

readonly CSTATION_COMPOSE="${BASE_DIR}/docker-compose.yml"
readonly CSTATION_COMPOSE_POSTGIS12="${BASE_DIR}/docker-compose_postgis12.yml"

readonly IMPACT_IMAGE="mydronedocker/impact5:latest"
readonly IMPACT_NAME="impact5"


function db_migration_pending()
{
    # Checks if we're still running a version 12 postgis database
    # returns 0 (success/true) if the migration is still to be performed
    #         1 (failure/false) otherwise

    # Check for the "fresh install" scenario.
    if [[ -z "$(docker images -q climatestation/postgis:2.0)" ]]; then
        return 1 # The migration is not needed, postgis 12 does not exist
    fi
 
    # Ensure DATA_VOLUME is defined in your script's environment
    local full_path="$DATA_VOLUME/static_data/settings"
    local full_path_file="$full_path/system_settings.ini"

    # if the settings directory doesn't exist or isn't readable, this is a fresh install
    if [[ ! -r "$full_path" ]]; then
        # Fresh install. The /data and static_data directories have not been created
        return 1 # Return false -> no db migration pending
    fi

    if [[ ! -r "$full_path_file" ]]; then
        return 1 # Return false -> no db migration pending.
    fi

    # At this point, return 1 ONLY IF the file contains a line matching:
    #   DB12_TO_DB17_MIGRATION_DONE = true
    #
    # Return 0 in ALL other cases, including:
    #   - The key does not exist.
    #   - The key's value is "false" or anything other than "true".
    #
    # Use quiet grep (-q) to check for an exact pattern match.
    # The pattern looks for:
    #   ^DB12_TO...        # Key at the start of the line
    #   [[:space:]]*=...   # Optional whitespace around the =
    #   ...true[[:space:]]*$ # The value "true" with optional trailing space at the end of the line
    #
    if grep -q -E "^db12_to_db17_migration_done[[:space:]]*=[[:space:]]*true[[:space:]]*$" "$full_path_file"; then
        return 1  # Setting is explicitly true, so no migration pending
    else
        return 0  # It's false, commented out or missing: migration pending
    fi
}

function set_db_migration_status() {
    local settings_file="$1"
    local value="$2"
    local settings_path="$DATA_VOLUME/static_data/settings"
    local full_path="${settings_path}/${settings_file}"
    local key="db12_to_db17_migration_done"
    local exit_code=0

    # Pre-flight check: ensure the target file exists and is writable
    if [[ ! -w "$full_path" ]]; then
        echo "Error: Settings file does not exist or is not writable at '${full_path}'" >&2
        return 1
    fi

    echo "Attempting to set '${key}' to '${value}' in '${full_path}'..."

    awk -v key="$key" -v val="$value" '
        BEGIN {
            found=0        # whether key was found
            in_section=0   # whether we are inside [SYSTEM_SETTINGS]
        }
        /^\[SYSTEM_SETTINGS\]/ {
            in_section=1
            print
            next
        }
        /^\[.*\]/ {
            # leaving SYSTEM_SETTINGS section
            if (in_section && !found) {
                print key " = " val
                found=1
            }
            in_section=0
            print
            next
        }
        {
            if (in_section && $0 ~ "^"key"[[:space:]]*=") {
                print key " = " val
                found=1
            } else {
                print
            }
        }
        END {
            # if SYSTEM_SETTINGS existed and key still not added, append it at the end of that section
            if (in_section && !found) {
                print key " = " val
                found=1
            }
            # if SYSTEM_SETTINGS section never existed at all, add it
            if (!found) {
                print "[SYSTEM_SETTINGS]"
                print key " = " val
            }
        }
    ' "$full_path" > "${full_path}.tmp" && mv "${full_path}.tmp" "$full_path"
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "Error: Failed to update settings file '${full_path}'." >&2
        return $exit_code
    else
        echo "Successfully set '${key} = ${value}'."
        return 0
    fi
}

function dump_db_postgresql12()
{
    # --- Configuration ---
    local container_name="postgres"
    local pg_user="estation"
    local db_name="estationdb"
    # Path inside the container
    local dump_file_path="/data/static_data/db_dump/estationdb_backup_v12.dump"
    local compose_file=$CSTATION_COMPOSE_POSTGIS12

    # --- Pre-flight Checks ---
 
    # 1. Check if the container is running
    if ! docker ps --filter "name=^${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$"; then
        info "Docker container '${container_name}' is not running. Starting climatestaion."
        $DOCKER_COMPOSE -f "${compose_file}" up -d
    fi
    info "Making sure container ${container_name} is running."
 
    # 2. Fix the DB structure of postgresql 12, there are trigger functions to move from public to climsoft schema.
    #    Otherwise the pg_restore will go in error.
    # Note: The `-i` flag in `docker exec` is essential for this to work.
    # Logs will be created on the HOST machine, not in the container.
    info "--- Starting Database Update (Pipe Method) ---"
 
    if [ ! -f "./fix_db_structure.sh" ]; then
        error "Error: Local SQL file not found at './fix_db_structure.sh'"
        return 1
    fi
 
    # The '-i' flag keeps STDIN open, allowing us to pipe the file content.
    # The exit code of 'docker exec' will be the exit code of 'psql'.
    docker exec -i "$container_name" sh < ./fix_db_structure.sh
 
    if [ $? -ne 0 ]; then
        error "Error: psql command failed. Check './log/postgres/fix_db_structure.err' on the host."
        return 1
    else
        success "Success. Check './log/postgres/fix_db_structure.log' on the host for details."
    fi
 
    # 2. Remove the old dump file to ensure we're not seeing a stale backup.
    # We add `|| true` so the command doesn't fail if the file doesn't exist.
    info "Attempting to remove old dump file at '${container_name}:${dump_file_path}'..."
    docker exec "$container_name" rm -f "$dump_file_path" || true
 
    # --- Main Operation ---
    info "Starting pg_dump for database ${db_name}..."
 
    # Execute the dump and capture its exit code immediately.
    docker exec --user postgres "$container_name" pg_dump \
        -U "$pg_user" \
        -h localhost \
        -p 5432 \
        -d "$db_name" \
        -F c \
        -b \
        -v \
        -f "$dump_file_path" \
        --schema=products \
        --schema=analysis \
        --schema=climsoft \
        --exclude-schema=bucardo

    local exit_code=$?
 
    # --- Post-flight Checks ---
 
    # 3. Primary Check: Was the pg_dump command successful?
    if [ $exit_code -ne 0 ]; then
        error "Error: pg_dump command failed with exit code ${exit_code}."
        return $exit_code
    fi
 
    # 4. Sanity Check: Does the file exist now and is it non-empty?
    # `test -s` checks if a file exists AND has a size greater than zero.
    if docker exec "$container_name" test -s "$dump_file_path"; then
        success "Postgis 12 database dump file created and is not empty at '${container_name}:${dump_file_path}'"
        $DOCKER_COMPOSE -f "${compose_file}" down
        return 0
    else
        error "Error: Dump file was not created or is empty, despite pg_dump reporting success."
        return 1
    fi
}

function restore_db_postgresql12()
{
    # --- Configuration ---
    local compose_file="${CSTATION_COMPOSE}"
    local service_name="postgres" # The name of the service in your docker-compose file
    local pg_user="estation"
    local db_name="estationdb"
    local dump_file_path="/data/static_data/db_dump/estationdb_backup_v12.dump"
    local log_file_path="/data/static_data/db_dump/pg_restore_v12.log"
    local exit_code=0

    # Bring up the new database
    #
    ${DOCKER_COMPOSE} -f "${compose_file}" up -d \
        && success "Bringing up the database" \
        || { error "Error: could not start Database"; return 1; }

    # Check if the dump file exists inside the container before we start.
    #
    if ! $DOCKER_COMPOSE -f "${compose_file}" exec "${service_name}" test -f "${dump_file_path}"; then
        error "Error: Dump file not found inside container at '${service_name}:${dump_file_path}'"
        return 1
    fi

    # --- Main Operation ---
    info "Starting pg_restore for database '${db_name}'..."

    # Execute the restore, redirecting output, and capture its exit code.
    # The exit code of 'docker compose exec' will be the exit code of pg_restore.
    #
    docker compose -f "${compose_file}" exec -T --user postgres "${service_name}" \
        bash -c "pg_restore -U ${pg_user} -h localhost -d ${db_name} -F c -v --clean --if-exists ${dump_file_path} &> ${log_file_path}"

    exit_code=$?

    # --- Post-flight Check ---
    if [ $exit_code -ne 0 ]; then
        error "Error: pg_restore command failed with exit code ${exit_code}."
        error "Check logs inside the container at: ${service_name}:${log_file_path}"
        return $exit_code
    else
        success "pg_restore command completed successfully."
        return 0
    fi
}

function success()
{
    echo -e "\e[32m${1}\e[0m"
}

function info()
{
    echo -e "\e[36m${1}\e[0m"
}

function warning()
{
    echo -e "\e[33m${1}\e[0m"
}

function error()
{
    echo -e "\e[31m${1}\e[0m"
}

function merge-files()
{
    local NEW_TEMPLATE="$1"
    local OLD_CONF="$2"

    local TEMPFILE=$(mktemp -q)
    [[ -w $TEMPFILE ]] || { error "Cannot create temp file"; exit 1; }

    while IFS= read -r line;  do
        defin=$(echo "$line" | grep -o '^[[:alnum:]_]\+=')

        if [[ "$defin" ]]; then

            # Check the definition exist in the old one
            old_def=$(grep "^${defin}" "$OLD_CONF")

            if [[ "$old_def" ]]; then
                echo "$old_def" >> $TEMPFILE

            else # New definition - Copy the line
                echo "$line" >> $TEMPFILE
            fi
        else  # Not a definition - Copy the line
            echo "$line" >> $TEMPFILE
        fi
    done < "$NEW_TEMPLATE"

    mv $TEMPFILE $OLD_CONF
}

function update-config-files()
{
    local CONFIG_FILE="$1"
    local TEMPLATE_FILE="$2"
    local OLD_VERSION="${3:-old}"

    local CONFIG_FILENAME="$(basename "$CONFIG_FILE")"

    if [[ -d "${CONFIG_FILE}" ]]; then
        echo -e "$(warning "WARNING"): Found a directory that already exists with"
        echo -e "          the same name as the '$(info "${CONFIG_FILENAME}")' file."
        echo "         You probably ran the 'docker-compose' command manually before"
        echo "          running this script."
        echo -e "         Renaming this directory… \c"
        mv "${CONFIG_FILE}" "${CONFIG_FILE}.dir.old" && success "OK!" || { error "ERROR"; exit; }
        echo
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        echo -e "$(info "INFO"): Copying existing $(info "${CONFIG_FILENAME}") to $(info "${CONFIG_FILE}.${OLD_VERSION}")… \c"
        cp -a "$CONFIG_FILE" "${CONFIG_FILE}.${OLD_VERSION}" && success "OK!" || { error "ERROR"; exit; }
        echo
        merge-files "$TEMPLATE_FILE" "$CONFIG_FILE" || exit

    else
        echo -e "$(info "INFO"): Creating the default '$(info "${CONFIG_FILENAME}")' file from the template… \c"
        cp "${TEMPLATE_FILE}" "${CONFIG_FILE}" && success "OK!" || { error "ERROR"; exit; }
        echo

    fi
}


function check-config()
{
    local LATEST_VERSION=
    mkdir -p "${CONFIG_DIR}"

    if [[ -f "${CONFIG_DIR}/version.conf" ]]; then
        LATEST_VERSION="$(cat "${CONFIG_DIR}/version.conf")"
    fi

    if [[ "${CONFIG_VERSION}" = "${LATEST_VERSION}" ]]; then
        echo -e "$(info "INFO"): No changes to configuration files."
        return
    fi

    if [[ -z "${LATEST_VERSION}" ]]; then
        echo -e "$(info "INFO"): You are running the Climate Station containers"
        echo "       stack on this machine for the first time."
        echo "      This script will now create some environmental files"
        echo "       needed to execute the application properly."
        echo
    else
        echo -e "$(info "INFO"): Since the last run of the Climate Station containers stack"
        echo "       on this machine, the required configurations have been changed."
        echo "      This script will now replace some environmental files with"
        echo "       the new ones needed to execute the application properly."
        echo
    fi

    update-config-files "${DFLT_ENV_FILE}" "${TMPL_ENV_FILE}" "$LATEST_VERSION" || { error "Error updating configuration"; exit; }

    echo "$(warning "WARNING"): Please, be sure to review the contents of these files"
    echo "          and configure them appropriately for your system."
    echo -e "         Don't forget to change also the '$(info "JWT_SECRET")'"
    echo "          value with a 32-character random string."
    echo "         Once you've done so, run this script again"
    echo

    echo "${CONFIG_VERSION}" > "${CONFIG_DIR}/version.conf" || { error "Error updating version number"; exit; }
    exit 0
}

function mount_drive()
{
    echo -n Trying to mount external drive..
    wsl.exe -u root -e mkdir -p /mnt/$MOUNT > /dev/null 2>&1
    wsl.exe -u root -e mount -t drvfs ${MOUNT}: /mnt/$MOUNT -o metadata,uid=$UID,gid=1000,umask=22,fmask=111 > /dev/null 2>&1
    echo " Done."
    echo
}

function clone-repo-files()
{
    local SOURCE="https://jeodpp.jrc.ec.europa.eu/ftp/private/zyWYcab3a/mv8byUkTRKjsA3JG/Shared/Packages"
    local COMMAND
    local IMAGE="alpine:latest"
    local LOG="/mnt/data/log/lftp_clone_repo.log"

    read -r -d '' COMMAND <<-EOM
    apk update
    apk add lftp
    lftp -c "mirror -v --no-perms --no-umask --log $LOG $SOURCE/docs/ /mnt/data/docs ;
    mirror -v --no-perms --no-umask --log $LOG $SOURCE/logos/ /mnt/data/logos ;
    mirror -v --no-perms --no-umask --log $LOG $SOURCE/layers/ /mnt/data/layers"
EOM

    docker run --rm --env-file $DFLT_ENV_FILE \
      -v "$DATA_VOLUME/static_data:/mnt/data" \
      $IMAGE sh -c "$COMMAND" \
    && success "Remote data copied"
}

function save_image_info()
{
    local IMAGE="$1"
    local TIME="$2"
    local BASE="$TMP_VOLUME/cs-install_install_reports"
    local REPORT=Install_report_${TIME}.txt
    local FORMAT

    mkdir -p $BASE

    read -d '' FORMAT <<'EOF'
{{print "Id: " .Id}}
{{print "Tag: " (index .RepoTags 0)}}
Labels:
{{range $name, $value := .Config.Labels}}{{println "  " $name "=" $value }}{{end}}
EOF

    docker inspect --format="$FORMAT" $IMAGE >>$BASE/$REPORT
}

function pull_images()
{
    local IMAGES=${CS_IMAGES[@]}
    local IMAGE_PREFIX=
    local pulled=0

    [[ "$JRC_ENV" ]] && IMAGE_PREFIX="$JRC_IMAGE_REGISTRY/"

    IMAGES+=( "$IMPACT_IMAGE" )

    for image in ${IMAGES[@]}; do
        info "Pulling ${IMAGE_PREFIX}${image}"
        docker pull "${IMAGE_PREFIX}${image}" \
            || { error "Could not pull ${IMAGE_PREFIX}${image}"; pulled=1; }
    done

    info "Cloning data from climatestation repo"
    clone-repo-files
    success "Done."
    return $pulled
}

function load_images()
{
    local IMAGES=${CS_IMAGES[@]}
    local NOW=$(date -Iseconds)

    IMAGES+=( "$IMPACT_IMAGE" )

    info "Trying to load images from directory $LOAD.."

    files=$(shopt -s nullglob dotglob; echo "$LOAD"/*.{tar,dump})

    if (( ${#files} )); then
        for file in $files; do
            docker load -q -i "$file"
        done
        success "Done."
        return 0
    else
        error "Error: could not find any file!"
        return 1
    fi

    # for image in ${IMAGES[@]}; do
    #     save_image_info ${image} $NOW
    # done
}

function fix_perms()
{
    local wsl=$(which wsl.exe)
    local command="sudo"

    [[ -n "$wsl" ]] && command="wsl.exe -u root -e"

    echo -n "Fixing filesystem permissions.."
    $command \
        chmod -fR u=rwX,g=rwX,o=rwX \
        "${DATA_VOLUME}/static_data/log" \
        "${DATA_VOLUME}/c3sf4p_jobresults" \
        "${TMP_VOLUME}"
    echo " Done."
    echo
}

function docker-create-volume()
{
    local volume_name="$1"

    echo -e "$(info "INFO"): Ensuring a docker volume named '$(info $volume_name)' exists"
    local ERRORS="$(docker volume create $volume_name 2>&1)"
    if [[ $? -ne 0 ]]
    then
        error "ERROR!"
        echo "${ERRORS}"
        exit 8
    fi
}

function setup_variables()
{
    source "${DFLT_ENV_FILE}"
    [[ "$DATA_VOLUME" ]] || { error "Error: no DATA_VOLUME defined"; exit 1; }

    export TARGET_SYSTEM=$TARGET
    export TYPE_OF_INSTALLATION
    [[ "$USER_ID" ]] || USER_ID="$(id -u)"
    [[ "$GROUP_ID" ]] || GROUP_ID="$(id -g)"
    export USER_ID GROUP_ID
}

function migrate_db()
{
    info "Starting DB backup."

    dump_db_postgresql12

    if [ $? -eq 0 ]; then
        success "DB dump created in $DATA_VOLUME/static_data/db_dump/estationdb_backup_v12.dump"
    else
        error "ERROR: Backup operation failed. DB dump NOT created!"
        return 1
    fi

    # First, ensure the "in-progress" status is set.
    # If we can't even write to the settings file, we must stop.
    if ! set_db_migration_status "system_settings.ini" "false"; then
        error "FATAL: Could not set migration status to 'false'. Check file permissions. Aborting."
        return 1
    fi

    # Now, call the restore function and CHECK ITS EXIT CODE.
    if restore_db_postgresql12; then
        success "Database restore completed successfully."

        # If restore was successful, mark the migration as done.
        info "Updating migration status to 'true'."
        if set_db_migration_status "system_settings.ini" "true"; then
            success "Migration procedure marked finished."
        else
            # This is a critical failure state. The DB is restored but the flag isn't set.
            error "FATAL: Database was restored, but the migration completion flag could not be set."
            error "Manual intervention is required. Please set DB12_TO_DB17_MIGRATION_DONE = true in system_settings.ini"
            return 1
        fi
    else
        # The restore function failed.
        error "FATAL: The database restore failed. The system is in an inconsistent state."
        error "The migration flag is set to 'false'. Please check logs and re-run after fixing the issue."
        return 1
    fi
}

function cs_up()
{
    local updated=

    check-config

    setup_variables

    [[ -n "$LOAD" ]] && load_images && updated=t

    [[ -n "$PULL" ]] && pull_images && updated=t

    docker-create-volume "cs-docker-postgresql17-volume"

    local network=$(docker network ls -q -f "name=jupyterhub")
    [[ "$network" ]] || docker network create "jupyterhub"

    if [[ ( "$updated" || "$FORCE_MIGRATION" ) && db_migration_pending ]] ; then
        info "Migration has not yet been completed. Starting the backup / restore procedure."
        migrate_db
    fi

    [[ -n "$FIX" ]] && fix_perms

    local COMPOSE_FILE=$CSTATION_COMPOSE

    if db_migration_pending ; then
        COMPOSE_FILE=$CSTATION_COMPOSE_POSTGIS12
    fi

    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" up -d  \
        && success "Climate Station is up" || error "Error: problems in starting Climatestation"

    if [[ -n "$INIT" ]]; then
        echo -e "$(info "INFO"): Waiting for the database containers to be ready to install updates… \c"
        sleep 10
        success "Ready"

        ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" exec -T postgres bash /install_update_db.sh
    fi

    IMPACT_DATA_VOLUME=$DATA_VOLUME/impact
    REMOTE_DATA_VOLUME=$DATA_VOLUME/ingest

    [ ! -d ${IMPACT_DATA_VOLUME} ] || mkdir -p ${IMPACT_DATA_VOLUME}
    [ ! -d ${IMPACT_DATA_VOLUME}/db ] || mkdir -p ${IMPACT_DATA_VOLUME}/db

    if [  $( docker ps -a | grep ${IMPACT_NAME} | wc -l ) -gt 0 ]; then
          docker stop ${IMPACT_NAME}
          docker rm ${IMPACT_NAME}
    fi

    docker run -d \
        --env-file ${DFLT_ENV_FILE} \
        --env IMPACT_NGINX_PORT=${IMPACT_PORT} \
        --env USER_ID=${USER_ID} \
        --env GROUP_ID=${GROUP_ID} \
        -v ${IMPACT_DATA_VOLUME}:/data \
        -v ${REMOTE_DATA_VOLUME}:/remote_data \
        -p ${IMPACT_PORT}:8899 \
        --name ${IMPACT_NAME} \
        --restart unless-stopped \
        ${IMPACT_IMAGE}
}

function cs_down()
{
    setup_variables

    local COMPOSE_FILE=$CSTATION_COMPOSE

    if db_migration_pending ; then
        COMPOSE_FILE=$CSTATION_COMPOSE_POSTGIS12
    fi

    ${DOCKER_COMPOSE} -f  "${COMPOSE_FILE}" down

    if [  $( docker ps -a | grep ${IMPACT_NAME} | wc -l ) -gt 0 ]; then
          docker stop ${IMPACT_NAME} && docker rm ${IMPACT_NAME}
    fi
}


function usage()
{
    >&2 cat << EOF
Usage: $0
   [ -h | --help ]
   [ -u | --user uid ] specify user id
   [ -g | --group gid ] specify group id
   [ -i | --init ] initialize installation
   [ -j | --jrc ] pull images from JRC registry
   [ -p | --pull ] pull images from public registry
   [ -f | --fix_perms ] fix fileystem permissions
   [ -t | --target_system ] <climatestation (default) | estation>
   <up (default) | down>
EOF
}


### code starts here
###

docker compose version &> /dev/null && DOCKER_COMPOSE="docker compose" || DOCKER_COMPOSE="docker-compose"

readonly LONGOPTS=help,init,user:,group:,jrc,pull,fix_perms,load:,target_system:
readonly OPTIONS=hiu:g:jpfl:t:

# Parsing command line options:
#
#
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

INIT=t
USER_ID=
GROUP_ID=
PULL=
JRC_ENV=
FIX=
LOAD=
TARGET=climatestation
TYPE_OF_INSTALLATION=full
FORCE_MIGRATION=

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--install)
            # always installing updates
            shift
            ;;
        -u|--user)
            USER_ID="$2"
            shift 2
            ;;
        -g|--group)
            GROUP_ID="$2"
            shift 2
            ;;
        -j|--jrc)
            PULL=t
            JRC_ENV=t
            shift
            ;;
        -p|--pull)
            PULL=t
            shift
            ;;
        -f|--fix_perms)
            FIX=t
            shift
            ;;
        -l|--load)
            LOAD="$2"
            shift 2
            ;;
        -t|--target_system)
            TARGET="$2"
            shift 2
            ;;
        --force-migration)
            FORCE_MIGRATION=t
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo -e "Unknown option: '$(warning "$1")'"
            echo -e "Run '$(info "${BASE_FILE} --help")' for more information."
            exit 2
            ;;
    esac
done

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

case "$TARGET" in
    climatestation|estation)
        # ok
        ;;
    *)
        echo "Unknown target system: $TARGET"
        echo
        usage
        exit 1
        ;;
esac

case "${1:-up}" in
    up)
        cs_up
        ;;
    down)
        cs_down
        ;;
    *)
        echo "Unknown command: $1"
        echo
        usage
        exit 1
        ;;
esac

