#!/usr/bin/env bash

# Exit the script as soon as something fails.
set -e

LOCATIONS=()
UPSTREAMS=()

LOCATIONS_FILE=$NGINX_INSTALL_PATH/conf.d/locations.conf
UPSTREAMS_FILE=$NGINX_INSTALL_PATH/conf.d/upstreams.conf

# Update placeholder vars to be taken from ENV vars

PLACEHOLDER_SERVER_NAME="${SERVER_NAME:-localhost}"
PLACEHOLDER_SERVER_TYPE="${SERVER_TYPE:-http}"

SITE_CONFIG_PATH="${NGINX_INSTALL_PATH}/conf.d/${PLACEHOLDER_SERVER_TYPE}.conf"

# if [[ "$SERVER_TYPE" == "elb" ]]; then
#   echo "NOTICE: SERVER_TYPE='elb' requires HTTPS listener & SSL cert for SERVER_NAME to be setup on ELB!"
# elif [[ "$SERVER_TYPE" == "https" ]]; then
#   if [[ ]]
#   #statements
# fi

upstream_exists () {
  for i in "${UPSTREAMS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

location_exists () {
  for i in "${LOCATIONS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

function create_upstream() {
cat <<EOF
upstream $1 {
  server $2:$3;
}
EOF
}

function create_location() {
cat <<EOF
location ~ ^$1 {
  rewrite $1(.*) $3\$1 break;
  proxy_set_header Host \$http_host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_redirect off;
  proxy_pass http://$2;
}
EOF
}

if [[ "$SERVER_BACKENDS" == "" ]]; then
  echo "No backends defined!"
else
  echo "" > $UPSTREAMS_FILE
  echo "" > $LOCATIONS_FILE

  IFS=',' read -ra PROVIDED_BACKENDS <<< "$SERVER_BACKENDS"
  IFS=$'\n' SORTED_BACKENDS=($(sort -r <<<"${PROVIDED_BACKENDS[*]}"))

  for backend in "${SORTED_BACKENDS[@]}"; do
    IFS=':' read -ra SETTINGS <<< "$backend"

    if (( ${#SETTINGS[@]} >= 3 )); then
      path="${SETTINGS[0]}"
      cont="${SETTINGS[1]}"
      port="${SETTINGS[2]}"
      dest="${SETTINGS[3]:-$path}"
      upstream="$cont-$port"

      echo "Configuring NGINX route: '$path' => '$cont:$port$dest' (using upstream: '$upstream')"
      
      if upstream_exists $upstream; then
        echo "WARNING! Duplicate upstream: '$upstream' for backend: '$backend' :: Using existing upstream definition..."
      else
        UPSTREAMS+=("$upstream")      
        echo "$(create_upstream $upstream $cont $port)" >> $UPSTREAMS_FILE
      fi

      if location_exists $path; then
        echo "ERROR! Location conflict: '$path' is already registered!"
        exit 1
      else
        LOCATIONS+=("$path")
        echo "$(create_location $path $upstream $dest)" >> $LOCATIONS_FILE
      fi
    fi
  done
fi

# Replace all instances of the placeholders with the values above.
sed -i "s/PLACEHOLDER_SERVER_NAME/${PLACEHOLDER_SERVER_NAME}/g" "${SITE_CONFIG_PATH}"
sed -i "s:PLACEHOLDER_NGINX_INSTALL_PATH:${NGINX_INSTALL_PATH}:g" "${SITE_CONFIG_PATH}"
sed -i "s/PLACEHOLDER_SERVER_TYPE/${PLACEHOLDER_SERVER_TYPE}/g" "${NGINX_INSTALL_PATH}/nginx.conf"
sed -i "s:PLACEHOLDER_NGINX_INSTALL_PATH:${NGINX_INSTALL_PATH}:g" "${NGINX_INSTALL_PATH}/nginx.conf"

# Execute the CMD from the Dockerfile and pass in all of its arguments.
exec "$@"