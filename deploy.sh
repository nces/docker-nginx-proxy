#!/bin/bash

REPO=cmr1/nginx-proxy

function push() {
  # Get the tag from argument to this function
  TAG="${1:-latest}"

  echo "Deploying tagged release '$TAG'"

  # Authenticate with DockerHub
  docker login -u="$DOCKER_HUB_USERNAME" -p="$DOCKER_HUB_PASSWORD" 

  # Tag the Docker image
  docker tag $REPO:latest $REPO:$TAG
  
  # Push the tagged image
  docker push $REPO:$TAG
}

if [ ! -z "$TRAVIS_TAG" ]; then
  push $TRAVIS_TAG
elif [ "$TRAVIS_BRANCH" == "master" ]; then
  push latest
fi