#!/usr/bin/env bash

# Exit the script as soon as something fails.
set -e

SERVERNAMES=()
LOCATIONS=()

SERVERNAMES_FILE=$NGINX_INSTALL_PATH/conf.d/servernames.conf
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

servername_exists () {
  for i in "${SERVERNAMES[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

function create_location() {
cat <<EOF
index index.php index.html;

location / {
  try_files \$uri \$uri/ /index.php?\$args;
}

# prevent nginx from serving protected files
location ~ ^/(protected|framework|themes/\w+/views) {
  deny  all;
}

location ~ ^$1.+\.php\$ {
  fastcgi_index index.php;
  fastcgi_pass $2:$3;
  fastcgi_buffers 16 16k;
  fastcgi_buffer_size 32k;
  fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
  include fastcgi_params;
}
EOF
}

if [[ "$SERVER_SERVERNAMES" ]]; then
  IFS=',' read -ra PROVIDED_SERVERNAMES <<< "$SERVER_SERVERNAMES"
  IFS=$'\n' SORTED_SERVERNAMES=($(sort -r <<<"${PROVIDED_SERVERNAMES[*]}"))

  echo "" > $SERVERNAMES_FILE

  for servername in "${SORTED_SERVERNAMES[@]}"; do
    IFS=':' read -ra SETTINGS <<< "$servername"

    if (( ${#SETTINGS[@]} >= 4 )); then
      host="${SETTINGS[0]}"
      cont="${SETTINGS[1]}"
      port="${SETTINGS[2]}"
      root="${SETTINGS[3]}"

      echo "Configuring NGINX PHP-FPM servername: '$host' => '$cont:$port:$root'"

      if servername_exists $hist; then
        echo "ERROR! ServerName conflict: '$host' is already registered!"
        exit 1
      else
        for conf in $NGINX_INSTALL_PATH/conf.d/*.conf; do
          file=$(basename $conf)

          cp $conf $NGINX_INSTALL_PATH/conf.d/$host-$file
        done

        for conf in $NGINX_INSTALL_PATH/conf.d/$host-*; do
          sed -i "s/common.conf/${host}-common.conf/g" ${conf}
          sed -i "s/locations.conf/${host}-locations.conf/g" ${conf}

          sed -i "s/PLACEHOLDER_SERVER_NAME/${host}/g" "${conf}"
          sed -i "s;PLACEHOLDER_SERVER_ROOT;${root};g" "${conf}"
        done

        SERVERNAMES+=("$host")

        echo "$(create_location '/' $cont $port)" > $NGINX_INSTALL_PATH/conf.d/$host-locations.conf
        echo "include conf.d/${host}-${PLACEHOLDER_SERVER_TYPE}.conf;" >> $SERVERNAMES_FILE
      fi
    fi
  done

  PLACEHOLDER_SERVER_TYPE="servernames"
elif [[ "$SERVER_BACKENDS" == "" ]]; then
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

      echo "Configuring NGINX PHP-FPM route: '$path' => '$cont:$port'"

      if location_exists $path; then
        echo "ERROR! Location conflict: '$path' is already registered!"
        exit 1
      else
        LOCATIONS+=("$path")
        echo "$(create_location $path $cont $port)" >> $LOCATIONS_FILE
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
