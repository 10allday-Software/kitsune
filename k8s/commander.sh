#!/bin/bash
set -eo pipefail
GREEN='\033[1;32m'
NC='\033[0m' # No Color
SLACK_CHANNEL=sumodev
DOCKER_HUB="https://hub.docker.com/r/itsre/sumo-kitsune/tags/"


function whatsdeployed {
    xdg-open "https://whatsdeployed.io/s-iiX"
}

function deploy {
    REGION=${2}
    REGION_ENV=${3}
    COMMIT_HASH=${4}
    DEPLOY_SECRETS=${5:-NO}
    K8S_NAMESPACE="sumo-${REGION_ENV}"

    if [ -f "./regions/${REGION}/kubectl" ] ; then
        KUBECTL_BIN="./regions/${REGION}/kubectl"
    else
        KUBECTL_BIN=$(which kubectl)
    fi
    export KUBECTL_BIN

    if [ -f "./regions/${REGION}/kubeconfig" ] ; then
        export KUBECONFIG="./regions/${REGION}/kubeconfig"
    fi

    if [[ "${DEPLOY_SECRETS}" == "secrets" ]]; then
        echo "Applying secrets";
        ${KUBECTL_BIN} -n "${K8S_NAMESPACE}" apply -f "regions/${REGION}/${REGION_ENV}-secrets.yaml"
    else
        echo "Secrets will *NOT* be applied";
    fi

    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" deployments.create-celery --apply --tag "full-${COMMIT_HASH}"
    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" rollouts.status-celery
    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" deployments.create-cron --apply --tag "full-${COMMIT_HASH}"
    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" rollouts.status-cron
    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" deployments.create-web --apply --tag "full-${COMMIT_HASH}"
    invoke  -f "regions/${REGION}/${REGION_ENV}.yaml" rollouts.status-web

    post-deploy "$@"

    if command -v slack-cli > /dev/null; then
        slack-cli -d "${SLACK_CHANNEL}" ":tada: Successfully deployed <${DOCKER_HUB}|full-${COMMIT_HASH}> to <https://${REGION_ENV}-${REGION}.sumo.mozit.cloud/|SUMO-${REGION_ENV} in ${REGION}>"
    fi
    printf "${GREEN}OK${NC}\n"
}

function post-deploy {
    REGION=${2}
    REGION_ENV=${3}
    K8S_NAMESPACE="sumo-${REGION_ENV}"

    if [ -f "./regions/${REGION}/kubectl" ] ; then
        KUBECTL_BIN="./regions/${REGION}/kubectl"
    else
        KUBECTL_BIN=$(which kubectl)
    fi
    export KUBECTL_BIN

    if [ -f "./regions/${REGION}/kubeconfig" ] ; then
        export KUBECONFIG="./regions/${REGION}/kubeconfig"
    fi


    # run post-deployment tasks
    echo "Running post-deployment tasks"
    # Get the name of a running web pod on which we can run the post-deploy script
    SUMO_POD=$(${KUBECTL_BIN} -n "${K8S_NAMESPACE}" get pods | egrep 'sumo-.*-web' | grep Running | head -1 | awk '{ print $1 }')
    ${KUBECTL_BIN} -n "${K8S_NAMESPACE}" exec "${SUMO_POD}" bin/run-post-deploy.sh
}

source venv/bin/activate

$1 $@
