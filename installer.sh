#!/usr/bin/env bash
#

set -e

if [[ -z "${OSTYPE}" ]] || [[ ! "${OSTYPE}" =~ ^(linux|darwin|msys$) ]]
then
    echo -e "$(warning "WARNING"): You're running this script on an unsupported OS"
    echo -e "          and this can lead to unexpected behaviour."
    echo -e "         Please, contact the support team if you encounter any issues."
    echo
fi

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

function create-env-file()
{
    cat > ${1} << 'EOF'
# PostgreSQL config:
#
CS_PGPORT=5431

# Volumes mapping:
#
DATA_VOLUME=/data
TMP_VOLUME=/tmp/climatestation

# Climate Station source directory:
# Use it whenever you want to develop and test the code directly within
#  the Jupyter Notebook containers without rebuilding the image every time.
#
SRC_DIR=

# Secret key used by the JWT token generation within the JupyterHub environment.
# It must be a 32-character random string and MUST remain secret.
#
EOF

    cat >> ${1} << EOF
JWT_SECRET="`cat /dev/urandom | tr -dc '[:alpha:]' | fold --width 32 | head -n 1`"
EOF

    cat >> ${1} << 'EOF'

# Proxy settings:
# Use it if you are behind a proxy (e.g. within the JRC network).
#
HTTP_PROXY=
HTTPS_PROXY=
FTP_PROXY=
NO_PROXY=localhost,127.0.0.1,::1,hub,mapserver,postgres

# IMPACT toolbox variables
# HTTP PORT listening for IMPACT requests
IMPACT_HTTP_PORT=8899

# NGINx load balancer for WMS requests
IMPACT_NGINX_PORT=9999

# url of the server: provides access to IMPACT
# change in case of alias or IP
SERVER_URL=127.0.0.1
EOF
}

function create-docker-compose-file()
{
    cat >> ${1} << 'EOF'
version: '3.3'

services:
  web:
    env_file: ./.env
    environment:
       CS_VERSION: "1.1.0"
    build:
      context: ./build-docker/web/
      args:
        USER_ID: ${USER_ID}
        GROUP_ID: ${GROUP_ID}
    container_name: web
    image: "climatestation/web:2.0"
    depends_on:
      - postgres
      - mapserver
      - hub
    networks:
      - default
    ports:
      - 8080:8080
      - 6767:6767
    restart: unless-stopped
    volumes:
      - ./build-docker/web/climatestation.conf:/etc/apache2/sites-available/000-default.conf
      - ./log/web:/var/log/apache2
      - ./src:/var/www/climatestation:rw
      - ${DATA_VOLUME}:/data:rw
      - ${TMP_VOLUME}:/tmp/climatestation:rw

  hub:
    env_file: ./.env
    build:
      context: ./build-docker/jupyterhub/
      args:
        IMAGE_PREFIX: ${IMAGE_PREFIX}
        HTTP_PROXY: ${HTTP_PROXY}
        HTTPS_PROXY: ${HTTPS_PROXY}
        FTP_PROXY: ${FTP_PROXY}
        NO_PROXY: ${NO_PROXY}
    container_name: jupyterhub
    image: "climatestation/jupyterhub:latest"
    depends_on:
      - postgres
    restart: unless-stopped
    networks:
      default:
      jupyterhub:
        aliases:
          - hub
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:rw

  mapserver:
    build:
      context: ./build-docker/mapserver/
      args:
        IMAGE_PREFIX: ${IMAGE_PREFIX}
        HTTP_PROXY: ${HTTP_PROXY}
        HTTPS_PROXY: ${HTTPS_PROXY}
        FTP_PROXY: ${FTP_PROXY}
        NO_PROXY: ${NO_PROXY}
    container_name: mapserver
    image: "climatestation/mapserver:2.0"
    restart: unless-stopped
    volumes:
      - ./log/mapserver:/var/log/apache2

  postgres:
    env_file: ./.env
    build:
      context: ./
      dockerfile: ./build-docker/postgres/Dockerfile
      args:
        IMAGE_PREFIX: ${IMAGE_PREFIX}
        USER_ID: ${USER_ID}
        GROUP_ID: ${GROUP_ID}
        HTTP_PROXY: ${HTTP_PROXY}
        HTTPS_PROXY: ${HTTPS_PROXY}
        FTP_PROXY: ${FTP_PROXY}
        NO_PROXY: ${NO_PROXY}
    container_name: postgres
    environment:
      DB_VERSION: "108"
      PGPASSWORD: "mesadmin"
      POSTGRES_USER: "estation"
      POSTGRES_PASS: "mesadmin"
      POSTGRES_DBNAME: "estationdb"
      POSTGRES_PORT: "5432"
      DEFAULT_ENCODING: "UTF8"
      DEFAULT_COLLATION: "en_US.UTF-8"
      DEFAULT_CTYPE: "en_US.UTF-8"
      # POSTGRES_MULTIPLE_EXTENSIONS: "postgis,adminpack,postgis_topology"
      POSTGRES_MULTIPLE_EXTENSIONS: "postgis,adminpack"
      POSTGRES_TEMPLATE_EXTENSIONS: "true"
      POSTGRES_HOST_AUTH_METHOD: "trust"
      WAL_SIZE: "4GB"
      MIN_WAL_SIZE: "2048MB"
      WAL_SEGSIZE: "1024"
      MAINTAINANCE_WORK_MEM: "128MB"
    image: "climatestation/postgis:2.0"
    ports:
      - ${CS_PGPORT}:5432
    networks:
      - default
      - jupyterhub
    restart: unless-stopped
    volumes:
      - ${DATA_VOLUME}/static_data/db_dump:/data/static_data/db_dump:rw
      - ./src:/var/www/climatestation:rw
      - ./log/postgres:/var/log/climatestation:rw
      - cs-docker-postgresql12-volume:/var/lib/postgresql:rw

      # - /var/run/docker.sock:/var/run/docker.sock:rw
      # - ./postgresql:/var/lib/postgresql:rw

networks:
  default:
  jupyterhub:
    external: true

# create an external docker volume: docker volume create --name cs-docker-postgresql12-volume -d local
volumes:
  cs-docker-postgresql12-volume:
    external: true
EOF
}

function docker-pull()
{
    TAG=${2}
    docker pull ghcr.io/estation2/climatestation/${1}:${TAG}
}

function docker-create-network()
{
    echo -e "$(info "INFO"): Creating a new Docker network named '$(info "${1}")'... \c"
    local ERRORS="$(docker network create "${1}" 2>&1 > /dev/null)"

    if [[ -z "${ERRORS}" ]]
    then
        success "OK!"
    else
        error "ERROR!"

        echo "${ERRORS}"

        exit 7
    fi
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

function docker-compose-pull()
{
    docker-compose -f "${1}" pull --ignore-pull-failures || true
}

function docker-compose-build()
{
    if [[ -z "${2}" ]]
    then
        docker-compose -f "${1}" build
    else
        docker-compose -f "${1}" build "${2}"
    fi
}

# Base directories:
#
readonly BASE_DIR="$(realpath "$(dirname "${0}")")"
readonly BASE_FILE="$(basename "${0}")"

# Help message
#

readonly HELP_MSG="
Downloads and runs the \"$(info "Climate Station")\" containers stack.

Usage:
    ${BASE_FILE} [OPTIONS...]

Options
    -b | --branch [branch]    Defines the tag of the images to be pulled.
"

# Parsing command line options:
#
while [[ ${#} -gt 0 ]]
do
    case "${1}" in
        -b | --branch)
            readonly TAG_IMAGES="${2}"
            shift
            ;;
        -h | -? | --help)
            echo -e "${HELP_MSG}" | more

            exit 0
            ;;
        *)
            echo -e "Unknown option: '$(warning "${1}")'"
            echo -e "Run '$(info "${BASE_FILE} --help")' for more information."

            exit 1
            ;;
    esac

    shift
done

# Template files:
#
readonly ENV_FILE="${BASE_DIR}/.env"
readonly DOCKER_COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

# Creating `.env` file:
#
if [[ ! -f "${ENV_FILE}" ]]
then
    echo -e "$(info "INFO"): Creating a default '.env' file: '$(info "${ENV_FILE}")'"

    create-env-file ${ENV_FILE}

    success "OK!"
fi

# Creating `docker-compose.yml` file:
#
if [[ ! -f "${DOCKER_COMPOSE_FILE}" ]]
then
    echo -e "$(info "INFO"): Creating the 'docker-compose.yml' file: '$(info "${DOCKER_COMPOSE_FILE}")'"

    create-docker-compose-file ${DOCKER_COMPOSE_FILE}

    success "OK!"
fi

# Pulling the images
if [[ -z "${TAG_IMAGES}" ]]
then
    readonly TAG_IMAGES="master"
fi
echo -e "$(info "INFO"): Pulling the images"

docker-pull "library" ${TAG_IMAGES}
docker-pull "web" ${TAG_IMAGES}
docker-pull "jupyterhub" ${TAG_IMAGES}
docker-pull "jupyternotebook" ${TAG_IMAGES}
docker-pull "postgres" ${TAG_IMAGES}
docker-pull "mapserver" ${TAG_IMAGES}


success "OK!"


exit -1

source "${DFLT_ENV_FILE}"

# Checking mutually exclusive options:
#
if [[ -n "${RUN_DEV}" ]] && [[ -n "${RUN_PROD}" ]]
then
    echo -e "$(error "ERROR"): You cannot specify both '--dev' and '--prod' options."
    echo -e "Run '$(info "${0} --help")' for more information."

    exit 3
fi
if [[ -n "${CACHE}" ]] && [[ -n "${NO_CACHE}" ]]
then
    echo -e "$(error "ERROR"): You cannot specify both '--cache' and '--no-cache' options."
    echo -e "Run '$(info "${0} --help")' for more information."

    exit 4
fi
if [[ -n "${USER_ID}" ]] && [[ -n "${NO_USER}" ]]
then
    echo -e "$(error "ERROR"): You cannot specify both '--user' and '--no-user' options."
    echo -e "Run '$(info "${0} --help")' for more information."

    exit 5
fi
if [[ -n "${GROUP_ID}" ]] && [[ -n "${NO_GROUP}" ]]
then
    echo -e "$(error "ERROR"): You cannot specify both '--group' and '--no-group' options."
    echo -e "Run '$(info "${0} --help")' for more information."

    exit 6
fi

# Setting default run mode properties:
#
if [[ -z "${RUN_DEV}" ]] && [[ -z "${RUN_PROD}" ]]
then
    readonly RUN_DEV="true"
fi

if [[ -n "${RUN_DEV}" ]]
then
    if [[ -z "${CACHE}" ]] && [[ -z "${NO_CACHE}" ]]
    then
        readonly CACHE="true"
    fi
    if [[ -z "${USER_ID}" ]] && [[ -z "${NO_USER}" ]]
    then
        readonly USER_ID="$(id -u)"
    fi
    if [[ -z "${GROUP_ID}" ]] && [[ -z "${NO_GROUP}" ]]
    then
        readonly GROUP_ID="$(id -g)"
    fi

elif [[ -n "${RUN_PROD}" ]]
then
    if [[ -z "${CACHE}" ]] && [[ -z "${NO_CACHE}" ]]
    then
        readonly NO_CACHE="true"
    fi
    if [[ -z "${USER_ID}" ]] && [[ -z "${NO_USER}" ]]
    then
        readonly NO_USER="true"
    fi
    if [[ -z "${GROUP_ID}" ]] && [[ -z "${NO_GROUP}" ]]
    then
        readonly NO_GROUP="true"
    fi
fi

# Exporting environmental variables:
#
if [[ -z "${NO_USER}" ]]
then
    if [[ -z "${USER_ID}" ]]
    then
        readonly USER_ID="${DFLT_USER_ID}"
    fi

    export USER_ID
fi
if [[ -z "${NO_GROUP}" ]]
then
    if [[ -z "${GROUP_ID}" ]]
    then
        readonly GROUP_ID="${DFLT_GROUP_ID}"
    fi

    export GROUP_ID
fi

if [[ -n "${JRC_ENV}" ]]
then
    export IMAGE_PREFIX="${JRC_IMAGE_REGISTRY}/"
fi

if [[ -z "${MIRROR}" ]]
then
    readonly UBUNTU_SOURCE_MIRROR_CODE=""
else
    readonly UBUNTU_SOURCE_MIRROR_CODE="${MIRROR}"
fi

export DATA_VOLUME
export HTTP_PROXY
export HTTPS_PROXY
export FTP_PROXY
export NO_PROXY
export UBUNTU_SOURCE_MIRROR_CODE

if [[ -z "${GIT_BRANCH}" ]]
then
    readonly GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

export GIT_BRANCH

# `docker-compose.yml` files definitions:
#
readonly LIBRARY_COMPOSE="${BASE_DIR}/build-docker/library/docker-compose.yml"
readonly NOTEBOOK_COMPOSE="${BASE_DIR}/build-docker/jupyternotebook/docker-compose.yml"
readonly CSTATION_COMPOSE="${BASE_DIR}/docker-compose.yml"

readonly IMPACT_COMPOSE="${IMPACT_VOLUME}/Libs/unix/docker-compose.yml"

#   ------  IMPACT env variables definition  -------

[[ ! -z ${IMPACT_HTTP_PORT} ]] && echo "IMPACT_HTTP_PORT = ${IMPACT_HTTP_PORT}" || export IMPACT_HTTP_PORT=8899
[[ ! -z ${IMPACT_NGINX_PORT} ]] && echo "IMPACT_NGINX_PORT = ${IMPACT_NGINX_PORT}" || export IMPACT_NGINX_PORT=9999
[[ ! -z ${SERVER_URL} ]] && echo "SERVER_URL = ${SERVER_URL}" || export SERVER_URL=127.0.0.1

export ENV_FILE="${DFLT_ENV_FILE}"
export IMPACT_DATA_VOLUME="${DATA_VOLUME}/impact"
export REMOTE_DATA_VOLUME="${DATA_VOLUME}"
export IMPACT_HTTP_HOST=$SERVER_URL:$IMPACT_HTTP_PORT
export NGINX_WMS_HOST=$SERVER_URL:$IMPACT_NGINX_PORT

# Stopping & Removing the containers:
#
if [[ -n "${SHUTDOWN}" ]]
then
    docker-compose -f "${CSTATION_COMPOSE}" down
    docker-compose --project-name "${IMPACT_PROJECT_NAME}" --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" down

    exit 0
fi

# Building the containers:
#
if [[ -z "${NO_BUILD}" ]]
then
    if [[ -n "${NO_CACHE}" ]]
    then
        docker-compose-pull "${LIBRARY_COMPOSE}"
        docker-compose-pull "${CSTATION_COMPOSE}"
    fi

    docker-compose-build "${LIBRARY_COMPOSE}" "${NO_CACHE}"
    docker-compose-build "${NOTEBOOK_COMPOSE}" "${NO_CACHE}"
    docker-compose-build "${CSTATION_COMPOSE}" "${NO_CACHE}"
fi

# Initializing the environment:
#
if [[ -n "${INIT}" ]] || [[ -n "${FORCE_INIT}" ]]
then
    if [[ -z "$(docker volume ls | awk '{ print $2 }' | grep -e "^cs-docker-postgresql12-volume$")" ]]
    then
        docker-create-volume "cs-docker-postgresql12-volume"
    fi
    if [[ -z "$(docker network ls | awk '{ print $2 }' | grep -e "^jupyterhub$")" ]]
    then
        docker-create-network "jupyterhub"
    fi
fi

# Running the containers:
#
if [[ -z "${NO_RUN}" ]]
then
    if [[ -n "${FORCE}" ]]
    then
        if [[ -n "$(docker-compose -f "${CSTATION_COMPOSE}" ps | awk '{ if (NR > 2) print }')" ]]
        then
            docker-compose -f "${CSTATION_COMPOSE}" down
        fi
    fi

    docker-compose -f "${CSTATION_COMPOSE}" up -d

    if [[ -n "${INIT}" ]] || [[ -n "${UPDATE}" ]] || [[ -n "${FORCE_INIT}" ]]
    then
        echo -e "$(info "INFO"): Waiting for the database containers to be ready to install updates... \c"
        sleep 10
        success "OK!"

        if [[ "${OSTYPE}" == msys ]]
        then
            winpty docker-compose -f "${CSTATION_COMPOSE}" exec postgres bash -c "bash /install_update_db.sh"
        else
            docker-compose -f "${CSTATION_COMPOSE}" exec postgres bash -c "bash /install_update_db.sh"
        fi
    fi
fi

#
# TODO: get layers and logos (and docs?) from our JRC FTP and extract them into their respective dir under static_data.
#

#   ------  IMPACT installation -------

echo "Testing Impact folder "${IMPACT_VOLUME}
mkdir -p "${IMPACT_VOLUME}"
echo "Testing Impact folder "${IMPACT_DATA_VOLUME}
mkdir -p "${IMPACT_DATA_VOLUME}"

#  test if target Impact directory is empty. If yes, clone the repo
if test -n "$(find "${IMPACT_VOLUME}" -maxdepth 0 -empty)"
then
    echo "Cloning IMPACT repo"
    git clone --depth 1 https://bitbucket.org/jrcimpact/impact5.git "${IMPACT_VOLUME}"
else
  echo "Impact directory is not empty. A manual git pull is reccomended"
  sleep 5
fi

# replace the NGINX PORT on CONF file
sed -i -- 's/listen [0-9]*[0-9];/listen '$IMPACT_NGINX_PORT';/g' "${IMPACT_VOLUME}/Libs/unix/build-docker/impact/nginx.conf"
# -------------------------------------------------

# Building the containers:
#
if [[ -z "${NO_BUILD}" ]]
then
    if [[ -n "${NO_CACHE}" ]]
    then
        docker-compose-pull "${IMPACT_COMPOSE}"
        docker-compose --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" build "${NO_CACHE}"
    else
        docker-compose --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" build
    fi
    # TODO: docker-compose-build : add option to pass env file as 3rd param
    #docker-compose-build "${IMPACT_COMPOSE}" "${NO_CACHE}"
fi

if [[ -z "${NO_RUN}" ]]
then
    if [[ -n "${FORCE}" ]]
    then
        if [[ -n "$(docker-compose -f "${IMPACT_COMPOSE}" ps | awk '{ if (NR > 2) print }')" ]]
        then
            docker-compose -f "${IMPACT_COMPOSE}" down
        fi
    fi

    docker-compose --project-name "${IMPACT_PROJECT_NAME}" --env-file "${ENV_FILE}" -f "${IMPACT_COMPOSE}" up -d
fi
