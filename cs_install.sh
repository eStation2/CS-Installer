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
        echo "         Pay attention for next time."
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
        echo >> ${CONFIG_FILE}
        echo "USER_ID=${USER_ID:-$MYUSER}" >> ${CONFIG_FILE}
        echo "GROUP_ID=${GROUP_ID:-$MYGROUP}" >> ${CONFIG_FILE}
        success "OK!"
    else
        echo -e "$(info "INFO"): Creating the default '$(info "${CONFIG_FILENAME}")' file from the template... \c"
        cp "${TEMPLATE_FILE}" "${CONFIG_FILE}"
        echo >> ${CONFIG_FILE}
        echo "USER_ID=${USER_ID:-$MYUSER}" >> ${CONFIG_FILE}
        echo "GROUP_ID=${GROUP_ID:-$MYGROUP}" >> ${CONFIG_FILE}
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
        echo "         Don't forget to run with the -i option!."
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

export DATA_VOLUME

# `docker-compose.yml` files definitions:
#
#readonly LIBRARY_COMPOSE="${BASE_DIR}/build-docker/library/docker-compose.yml"
#readonly NOTEBOOK_COMPOSE="${BASE_DIR}/build-docker/jupyternotebook/docker-compose.yml"
readonly CSTATION_COMPOSE="${BASE_DIR}/docker-compose.yml"

readonly IMPACT_COMPOSE="${IMPACT_VOLUME}/Libs/unix/docker-compose.yml"

#   ------  IMPACT env variables definition  -------

# [[ ! -z ${IMPACT_HTTP_PORT} ]] && echo "IMPACT_HTTP_PORT = ${IMPACT_HTTP_PORT}" || export IMPACT_HTTP_PORT=8899
# [[ ! -z ${IMPACT_NGINX_PORT} ]] && echo "IMPACT_NGINX_PORT = ${IMPACT_NGINX_PORT}" || export IMPACT_NGINX_PORT=9999
# [[ ! -z ${SERVER_URL} ]] && echo "SERVER_URL = ${SERVER_URL}" || export SERVER_URL=127.0.0.1

# export ENV_FILE="${DFLT_ENV_FILE}"
# export IMPACT_DATA_VOLUME="${DATA_VOLUME}/impact"
# export REMOTE_DATA_VOLUME="${DATA_VOLUME}/ingest"
# export IMPACT_HTTP_HOST=$SERVER_URL:$IMPACT_HTTP_PORT
# export NGINX_WMS_HOST=$SERVER_URL:$IMPACT_NGINX_PORT
function mount_drives()
{
    echo -n Trying to mount external drives..
    for letter in d e f; do
        wsl.exe -u root -e mkdir -p /mnt/$letter > /dev/null 2>&1
        wsl.exe -u root -e mount -t drvfs ${letter}: /mnt/$letter -o metadata,uid=$UID,gid=1000,umask=22,fmask=111 > /dev/null 2>&1
    done
    echo " Done."
    echo
}

function umount_drives()
{
    for letter in d e f; do
        wsl.exe -u root -e umount /mnt/$letter > /dev/null 2>&1
    done
}


function pull_images()
{
    local IMAGE_PREFIX=
    [[ -n "${JRC_ENV}" ]] && IMAGE_PREFIX="${JRC_IMAGE_REGISTRY}/"

    for image in ${CS_IMAGES[@]}; do
        docker pull "${IMAGE_PREFIX}${image}"
    done
}

# Stopping & Removing the containers:
#
function cs_up()
{

    [ -n "$MOUNT" ] && mount_drives

    check-config

    source "${DFLT_ENV_FILE}"

    if [[ -z "$(docker network ls | awk '{ print $2 }' | grep -e "^jupyterhub$")" ]]; then
        docker network create "jupyterhub"
    fi

    [[ -n "$PULL" ]] && pull_images

    docker-compose -f "${CSTATION_COMPOSE}" up -d
    echo
    echo Climate Station is up.
    echo

    if [[ -n "$INIT" ]]; then
        echo -e "$(info "INFO"): Waiting for the database containers to be ready to install updates... \c"
        sleep 10
        success "Ready"

        docker-compose -f "${CSTATION_COMPOSE}" exec -T postgres bash /install_update_db.sh
    fi
}

function cs_down()
{
        [ -n "$MOUNT" ] && umount_drives

        docker-compose -f "${CSTATION_COMPOSE}" down
        # docker-compose --project-name "${IMPACT_PROJECT_NAME}" --env-file "${DFLT_ENV_FILE}" -f "${IMPACT_COMPOSE}" down
}

#   ------  IMPACT installation -------

# echo "Testing Impact folder "${IMPACT_VOLUME}
# mkdir -p "${IMPACT_VOLUME}"
# echo "Testing Impact folder "${IMPACT_DATA_VOLUME}
# mkdir -p "${IMPACT_DATA_VOLUME}"

# #  test if target Impact directory is empty. If yes, clone the repo
# if test -n "$(find "${IMPACT_VOLUME}" -maxdepth 0 -empty)"
# then
#     echo "Cloning IMPACT repo"
#     git clone --depth 1 https://bitbucket.org/jrcimpact/impact5.git "${IMPACT_VOLUME}"
# else
#   echo "Impact directory is not empty. A manual git pull is reccomended"
#   sleep 5
# fi

# # replace the NGINX PORT on CONF file
# sed -i -- 's/listen [0-9]*[0-9];/listen '$IMPACT_NGINX_PORT';/g' "${IMPACT_VOLUME}/Libs/unix/build-docker/impact/nginx.conf"
# -------------------------------------------------

# Building the containers:
#
# if [[ -z "${NO_BUILD}" ]]
# then
#     if [[ -n "${NO_CACHE}" ]]
#     then
#         docker-compose --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" build "${NO_CACHE}"
#     else
#         docker-compose --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" build
#     fi
#     # TODO: docker-compose-build : add option to pass env file as 3rd param
#     #docker-compose-build "${IMPACT_COMPOSE}" "${NO_CACHE}"
# fi

# if [[ -z "${NO_RUN}" ]]
# then
#     if [[ -n "${FORCE}" ]]
#     then
#         if [[ -n "$(docker-compose -f "${IMPACT_COMPOSE}" ps | awk '{ if (NR > 2) print }')" ]]
#         then
#             docker-compose -f "${IMPACT_COMPOSE}" down
#         fi
#     fi

#     docker-compose --project-name "${IMPACT_PROJECT_NAME}" --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" up -d
# fi

# Parsing command line options:
#
#

usage(){
>&2 cat << EOF
Usage: $0
   [ -h | --help ]
   [ -u | --user input ] specify user id
   [ -g | --group input ] specify group id
   [ -i | --init ] initialize installation
   [ -j | --jrc ] pull images from JRC registry
   [ -m | --mount ] mount / unmount removable drives in WSL
   [ -p | --pull ] pull images from public registry
   <up|down>
EOF
}

LONGOPTS=help,init,user:,group:,jrc,mount,pull
OPTIONS=hiu:g:jmp

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

INIT=
USER_ID=
GROUP_ID=
PULL=
JRC_ENV=
MOUNT=

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--install)
            INIT=t
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
        -m|--mount)
            MOUNT=t
            shift
            ;;
        -p|--pull)
            PULL=t
            shift
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

[[ ${1:-up} = "down" ]] && cs_down || cs_up
