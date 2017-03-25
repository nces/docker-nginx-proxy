#!/usr/bin/env bash

# Exit the script as soon as something fails.
set -e

LOCATIONS=()

LOCATIONS_FILE=$NGINX_INSTALL_PATH/conf.d/locations.conf

# Update placeholder vars to be taken from ENV vars

PLACEHOLDER_SERVER_NAME="${SERVER_NAME:-_}"
PLACEHOLDER_SERVER_TYPE="${SERVER_TYPE:-http}"
PLACEHOLDER_SERVER_ROOT="${SERVER_ROOT:-/var/www/html}"

location_exists () {
  for i in "${LOCATIONS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

function create_location() {
cat <<EOF
location ~ ^$1 {
  rewrite $1(.*) $4\$1 break;
  fastcgi_index index.php;
  fastcgi_pass $2:$3;
  fastcgi_buffers 16 16k;
  fastcgi_buffer_size 32k;
  fastcgi_param  SCRIPT_NAME  \$document_root\$fastcgi_script_name;
  include fastcgi_params;
}
EOF
}

if [[ "$SERVER_BACKENDS" == "" ]]; then
  echo "No backends defined!"
else
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

      echo "Configuring NGINX PHP-FPM route: '$path' => '$cont:$port$dest'"

      if location_exists $path; then
        echo "ERROR! Location conflict: '$path' is already registered!"
        exit 1
      else
        LOCATIONS+=("$path")
        echo "$(create_location $path $cont $port $dest)" >> $LOCATIONS_FILE
      fi
    fi
  done
fi

sed -i "s/PLACEHOLDER_SERVER_TYPE/${PLACEHOLDER_SERVER_TYPE}/g" "${NGINX_INSTALL_PATH}/nginx.conf"

for conf in $NGINX_INSTALL_PATH/conf.d/*.conf; do
  sed -i "s/PLACEHOLDER_SERVER_NAME/${PLACEHOLDER_SERVER_NAME}/g" "${conf}"
  sed -i "s;PLACEHOLDER_SERVER_ROOT;${PLACEHOLDER_SERVER_ROOT};g" "${conf}"
done 

# Execute the CMD from the Dockerfile and pass in all of its arguments.
exec "$@"
