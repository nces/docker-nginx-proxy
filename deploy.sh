#!/bin/bash

set -e

REPO=cmr1/nginx-proxy
BRANCH_TARGETS=("php-fpm" "open-cors")

should_deploy_branch() {
  for i in "${BRANCH_TARGETS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

push() {
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
elif should_deploy_branch $TRAVIS_BRANCH; then
  push $TRAVIS_BRANCH
fi