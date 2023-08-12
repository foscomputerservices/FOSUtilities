#!/bin/bash

SWIFT_VERSION="5.8.1"
CONTAINER="swift:${SWIFT_VERSION}"

## NOTE: If trying to run LLDB, uncomment the following line:
RESTRICTED='--privileged=true'
DEV_ENVIRONMENT="-e GIT_REPOSITORY_URL='git@github.com:foscomputerservices/FOSUtilities.git' -e SWIFT_VERSION=$SWIFT_VERSION"

## Pick an environment
ENVIRONMENT=${DEV_ENVIRONMENT}
# ENVIRONMENT=${STAGING_ENVIRONMENT} # make sure to add --env staging
SERVER_PORT="8080"

docker run -ti --rm -p ${SERVER_PORT}:${SERVER_PORT} ${RESTRICTED} ${ENVIRONMENT} ${CONTAINER} /bin/bash
