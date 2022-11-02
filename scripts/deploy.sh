#!/bin/bash
#
# Deploys All in Network infrastructure
#

PRECONFIGURE_PARACHAIN=${PRECONFIGURE_PARACHAIN:-0}

#
# Parachain node configuration
#


# Get the most recent changes of the parachain node
git -C ${PARACHAIN_PATH} pull origin master

# Removes the old parachain node
docker compose -f ${PARACHAIN_PATH}/docker-compose.yml down -v

# Deploy locally the parachain node
docker compose -f ${PARACHAIN_PATH}/docker-compose.yml up -d

#
# Wait until the parachain node is ready to receive requests and
# setting up the basic requirements.
#
while [ ${PRECONFIGURE_PARACHAIN} -eq 1 ]
do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" localhost:${PARACHAIN_LOCAL_PORT} || true)

    echo "Attempting to connect to parachain node to run the initial configuration..."

    # "000" is a response code that indicates the parachain node
    # isn't ready to receive requests.
    if [ $STATUS_CODE -ne 000 ]
    then
        PRECONFIGURE_PARACHAIN=0

        # Preconfigure the parachain node
        echo "Running the required configuration for the parachain..."
        docker exec parachain-node cargo run --bin preconfig
    fi

    # Wait until the parachain node has availability
    sleep 5
done

#
# Parachain RPC configuration
#


# Removes the old RPC
docker container stop all-in-rpc && docker container rm all-in-rpc
docker image rm all-in-rpc-prod:latest

# Build the Parachain RPC docker image
docker build -t all-in-rpc-prod ${PARACHAIN_PATH}

# Deploy the Parachain RPC on Internet
docker run -d -e VIRTUAL_HOST=rpc.all-in.app \
    -e VIRTUAL_PORT=${PARACHAIN_LOCAL_PORT} \
    -e LETSENCRYPT_HOST=rpc.all-in.app \
    -e LETSENCRYPT_EMAIL=${DEFAULT_EMAIL} \
    --network=proxy \
    --name all-in-rpc \
    all-in-rpc-prod

#
# WebSocket configuration
#

# Get the most recent changes of the parachain node
git -C ${WEBSOCKET_PATH} pull origin master

# Removes the old WebSocket
docker container stop all-in-api && docker container rm all-in-api
docker image rm all-in-api:latest

# Build the WebSocket docker image
docker build -t all-in-api-prod ${WEBSOCKET_PATH}

# Deploy the WebSocket on Internet
docker run -d --network=proxy --name all-in-api all-in-api-prod

#
# Frontend configuration
#


# Get the most recent changes of the frontend
git -C ${FRONTEND_PATH} pull origin master

# Removes the old Frontend
docker container stop all-in-frontend && docker container rm all-in-frontend
docker image rm all-in-frontend-prod:latest

# Dockerize the Frontend
docker compose -f ${FRONTEND_PATH}/docker-compose.prod.yml build

# Deploy the Frontend on Internet
docker run -d -e VIRTUAL_HOST=all-in.app \
    -e LETSENCRYPT_HOST=all-in.app \
    -e LETSENCRYPT_EMAIL=${DEFAULT_EMAIL} \
    --network=proxy \
    --name all-in-frontend \
    all-in-frontend-prod
