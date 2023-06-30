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
readonly CONFIG_VERSION="1.1.2"

readonly JRC_IMAGE_REGISTRY="d-prd-registry.jrc.it/d6-estation"

# Template files:
#
readonly DFLT_ENV_FILE="${BASE_DIR}/.env"
readonly TMPL_ENV_FILE="${BASE_DIR}/.env.template"

readonly CS_IMAGES=("climatestation/postgis:2.0"
                    "climatestation/web:2.0"
                    "climatestation/jupyterhub:latest"
                    "climatestation/jupyternotebook:latest")

readonly CSTATION_COMPOSE="${BASE_DIR}/docker-compose.yml"

readonly IMPACT_IMAGE="mydronedocker/impact5:latest"
readonly IMPACT_NAME="impact5"

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

    local MYUSER=$(id -u)
    local MYGROUP=$(id -g)

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

    cat  >> "${CONFIG_FILE}" <<EOF

USER_ID=${USER_ID:-$MYUSER}
GROUP_ID=${GROUP_ID:-$MYGROUP}

EOF
}
#TARGET_SYSTEM=$TARGET
#TYPE_OF_INSTALLATION=$TYPE_OF_INSTALLATION

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

function pull_images()
{
    local IMAGE_PREFIX=
    [[ -n "${JRC_ENV}" ]] && IMAGE_PREFIX="${JRC_IMAGE_REGISTRY}/"

    for image in ${CS_IMAGES[@]}; do
        docker pull "${IMAGE_PREFIX}${image}"
    done

    docker pull "${IMAGE_PREFIX}${IMPACT_IMAGE}"
}

function load_images()
{
    echo "Trying to load images from directory $LOAD.."

    files=$(shopt -s nullglob dotglob; echo "$LOAD"/*.{tar,dump})

    if (( ${#files} )); then
        for file in $files; do
            docker load -q -i "$file"
        done
        echo "Done."
    else
        echo "Error: could not find any file!"
    fi
    echo
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
    echo -e "$(info "INFO"): Creating a new Docker volume named '$(info "${1}")'… \c"
    local ERRORS="$(docker volume create "${1}" 2>&1 > /dev/null)"

    if [[ -z "${ERRORS}" ]]
    then
        success "OK!"
    else
        error "ERROR!"

        echo "${ERRORS}"

        exit 8
    fi
}

function cs_up()
{

    [[ -n "$LOAD" ]] && load_images

    [[ -n "$PULL" ]] && pull_images

    check-config

    source "${DFLT_ENV_FILE}"

    export TARGET_SYSTEM=$TARGET
    export TYPE_OF_INSTALLATION=$TYPE_OF_INSTALLATION

    if [[ -z "$(docker volume ls | awk '{ print $2 }' | grep -e "^cs-docker-postgresql12-volume$")" ]]
    then
        docker-create-volume "cs-docker-postgresql12-volume"
    fi

    if [[ -z "$(docker network ls | awk '{ print $2 }' | grep -e "^jupyterhub$")" ]]; then
        docker network create "jupyterhub"
    fi

    [[ -n "$FIX" ]] && fix_perms

    ${DOCKER_COMPOSE} -f "${CSTATION_COMPOSE}" up -d
    echo
    echo Climate Station is up.
    echo

    if [[ -n "$INIT" ]]; then
        echo -e "$(info "INFO"): Waiting for the database containers to be ready to install updates… \c"
        sleep 10
        success "Ready"

        ${DOCKER_COMPOSE} -f "${CSTATION_COMPOSE}" exec -T postgres bash /install_update_db.sh
    fi

    IMPACT_DATA_VOLUME=$DATA_VOLUME/impact
    REMOTE_DATA_VOLUME=$DATA_VOLUME/ingest

    [ ! -d ${IMPACT_DATA_VOLUME} ] || mkdir -p ${IMPACT_DATA_VOLUME}
    [ ! -d ${IMPACT_DATA_VOLUME}/db ] || mkdir -p ${IMPACT_DATA_VOLUME}/db

    if [  $( docker ps -a | grep ${IMPACT_NAME} | wc -l ) -gt 0 ]; then
          docker stop ${IMPACT_NAME}
          docker rm ${IMPACT_NAME}
    fi
    docker run -d --env-file ${DFLT_ENV_FILE} -v ${IMPACT_DATA_VOLUME}:/data -v ${REMOTE_DATA_VOLUME}:/remote_data -p $IMPACT_NGINX_PORT:8899 --name ${IMPACT_NAME} ${IMPACT_IMAGE}


}

function cs_down()
{
    ${DOCKER_COMPOSE} -f  "${CSTATION_COMPOSE}" down

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

[[ ${1:-up} = "down" ]] && cs_down || cs_up
