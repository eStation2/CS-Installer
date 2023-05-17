#!/usr/bin/env bash
#

set -o errexit -o pipefail -o noclobber -o nounset

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


if ! which realpath > /dev/null
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

docker compose version &> /dev/null && DOCKER_COMPOSE="docker compose" || DOCKER_COMPOSE="docker-compose"


function update-config-files()
{
    local CONFIG_FILE=$1
    local TEMPLATE_FILE=$2

    local CONFIG_FILENAME="$(basename "$1")"

    local MYUSER=$(id -u)
    local MYGROUP=$(id -g)

    if [[ -d "${CONFIG_FILE}" ]]; then
        echo -e "$(warning "WARNING"): Found a directory that already exists with"
        echo -e "          the same name as the '$(info "${CONFIG_FILENAME}")' file."
        echo "         You probably ran the 'docker-compose' command manually before"
        echo "          running this script."
        echo -e "         Removing this directory... \c"
        rmdir "${CONFIG_FILE}"
        success "OK!"
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        echo -e "$(warning "WARNING"): The default '$(info "${CONFIG_FILENAME}")' file already exists."
        echo "         Appending the previous configuration in '$(warning "${CONFIG_FILENAME}.old")'"
        echo -e "          and creating a new file from the template... \c"
        echo "=====================" >> "${CONFIG_FILE}.old"
        echo "Update config file to version ${CONFIG_VERSION} of `date` " >> "${CONFIG_FILE}.old"
        echo "---------------------" >> "${CONFIG_FILE}.old"
        cat "${CONFIG_FILE}" >> "${CONFIG_FILE}.old"
        cp "${TEMPLATE_FILE}" "${CONFIG_FILE}"
        echo >> "${CONFIG_FILE}"
        echo "USER_ID=${USER_ID:-$MYUSER}" >> "${CONFIG_FILE}"
        echo "GROUP_ID=${GROUP_ID:-$MYGROUP}" >> "${CONFIG_FILE}"
        success "OK!"
    else
        echo -e "$(info "INFO"): Creating the default '$(info "${CONFIG_FILENAME}")' file from the template... \c"
        cp "${TEMPLATE_FILE}" "${CONFIG_FILE}"
        echo >> "${CONFIG_FILE}"
        echo "USER_ID=${USER_ID:-$MYUSER}" >> "${CONFIG_FILE}"
        echo "GROUP_ID=${GROUP_ID:-$MYGROUP}" >> "${CONFIG_FILE}"
        success "OK!"
    fi
}


# Base directories:
#
readonly BASE_DIR="$(realpath "$(dirname "${0}")")"
readonly BASE_FILE="$(basename "${0}")"

readonly CONFIG_DIR="${BASE_DIR}/.configs"

export IMPACT_VOLUME="${BASE_DIR}/../Impact"
#readonly IMPACT_PROJECT_NAME="$(basename "${IMPACT_VOLUME}")"
readonly IMPACT_PROJECT_NAME="$(basename "${IMPACT_VOLUME}"| tr '[:upper:]' '[:lower:]')"

# Project versions:
readonly CONFIG_VERSION="1.1.1"
# readonly SOURCE_VERSION="1.1.0"

readonly JRC_IMAGE_REGISTRY="d-prd-registry.jrc.it"

# Template files:
#
readonly DFLT_ENV_FILE="${BASE_DIR}/.env"
readonly TMPL_ENV_FILE="${BASE_DIR}/.env.template"

readonly CS_IMAGES=("climatestation/postgis:2.0"
                    "climatestation/web:2.0"
                    "climatestation/jupyterhub:latest"
                    "climatestation/jupyternotebook:latest")

function check-config()
{
    local LATEST_VERSION=
    mkdir -p "${CONFIG_DIR}"

    if [[ -f "${CONFIG_DIR}/version.conf" ]]; then
        LATEST_VERSION="$(cat "${CONFIG_DIR}/version.conf")"
    fi

    if [[ "${CONFIG_VERSION}" != "${LATEST_VERSION}" ]]; then
        if [[ -z "${LATEST_VERSION}" ]]; then
            echo -e "$(info "INFO"): You are running the Climate Station containers"
            echo "       stack on this machine for the first time."
            echo "      This script will now create some environmental files"
            echo "       needed to execute the application properly."
            echo

            touch "${CONFIG_DIR}/init.lock"
        else
            echo -e "$(info "INFO"): Since the last run of the Climate Station containers stack"
            echo "       on this machine, the required configurations have been changed."
            echo "      This script will now replace some environmental files with"
            echo "       the new ones needed to execute the application properly."
            echo

            touch "${CONFIG_DIR}/update.lock"
        fi

        update-config-files "${DFLT_ENV_FILE}" "${TMPL_ENV_FILE}"

        echo "$(warning "WARNING"): Please, be sure to review the contents of these files"
        echo "          and configure them appropriately for your system."
        echo -e "         Don't forget to change also the '$(info "JWT_SECRET")'"
        echo "          value with a 32-character random string."
        echo "         Once you've done so, run this script again"
        echo
        echo "${CONFIG_VERSION}" > "${CONFIG_DIR}/version.conf"
        exit 0
    elif [[ -f "${CONFIG_DIR}/init.lock" ]]; then
        readonly INIT="true"
        rm "${CONFIG_DIR}/init.lock"
    elif [[ -f "${CONFIG_DIR}/update.lock" ]]; then
        readonly UPDATE="true"
        rm "${CONFIG_DIR}/update.lock"
    fi
}

#export DATA_VOLUME

readonly CSTATION_COMPOSE="${BASE_DIR}/docker-compose.yml"

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
    echo -e "$(info "INFO"): Creating a new Docker volume named '$(info "${1}")'... \c"
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
        echo -e "$(info "INFO"): Waiting for the database containers to be ready to install updates... \c"
        sleep 10
        success "Ready"

        ${DOCKER_COMPOSE} -f "${CSTATION_COMPOSE}" exec -T postgres bash /install_update_db.sh
    fi
}

function cs_down()
{
        ${DOCKER_COMPOSE} -f  "${CSTATION_COMPOSE}" down
}


# Parsing command line options:
#
#
usage(){
>&2 cat << EOF
Usage: $0
   [ -h | --help ]
   [ -u | --user uid ] specify user id
   [ -g | --group gid ] specify group id
   [ -i | --init ] initialize installation
   [ -j | --jrc ] pull images from JRC registry
   [ -p | --pull ] pull images from public registry
   [ -f | --fix_perms ] fix fileystem permissions
   <up (default) | down>
EOF
}

LONGOPTS=help,init,user:,group:,jrc,pull,fix_perms,load:,target_system:
OPTIONS=hiu:g:jpfl:t:

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
MOUNT=
FIX=
LOAD=
TARGET=climatestation

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--install)
            # always install updates
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
            echo -e "Unknown option: '$(warning "${1}")'"
            echo -e "Run '$(info "${BASE_FILE} --help")' for more information."
            exit 2
            ;;
    esac
done

if [[ $# -gt 1 ]]; then
  usage
fi

case "$TARGET" in
    climatestation|estation)
        ;;
    *)
        echo "Unknown usage type: $TARGET"
        echo
        usage
        ;;
esac

[[ ${1:-up} = "down" ]] && cs_down || cs_up
