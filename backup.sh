#!/bin/bash

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <direction> <backup> <config_file>"
    exit 1
fi

direction="$1"
backup=("$2" = "true")
config_file="$3"

if [ ! -f "$config_file" ]; then
    echo "Error: Config file '$config_file' does not exist"
    exit 1
fi

if [ "$direction" != "up" ] && [ "$direction" != "down" ]; then
    echo "Error: Invalid direction"
    exit 1
fi

echo "Current directory"
pwd
echo "Direction: $direction"
echo "Backup: $backup"
echo "Config file: $config_file"

get_source_and_destination() {
    local backup_docs=("${!1}")
    local remote_path=$2
    local local_path=$3
    local direction=$4

    local source=()
    local destination=""

    if [ "$direction" = "up" ]; then
        for doc in "${backup_docs[@]}"; do
            source+=("\"$local_path/$doc\"")
        done
        destination="\"$remote_path\""
    else
        if [ "${#backup_docs[@]}" -eq 1 ]; then
            escaped_doc=$(echo "${backup_docs[0]}" | sed 's/ /\\ /g')
            source=("\"$remote_path/$escaped_doc\"")
        else
            local remote_docs=""
            for doc in "${backup_docs[@]}"; do
                escaped_doc=$(echo "$doc" | sed 's/ /\\ /g')
                remote_docs+="$escaped_doc,"
            done
            remote_docs="${remote_docs%,}"
            source=("\"$remote_path/{$remote_docs}\"")
        fi
        destination="\"$local_path\""
    fi

    echo "${source[@]}"
    echo "$destination"
}

backup_files() {
    local port=$1
    local backup_docs=("${!2}")
    local remote_path=$3
    local local_path=$4
    local direction=$5
    local backup=$6

    local rsync_options=""
    if [ "$backup" = true ]; then
        rsync_options="-avz"
    else
        rsync_options="-avzn"
    fi

    local source_and_destination=($(get_source_and_destination backup_docs[@] "$remote_path" "$local_path" "$direction"))
    local source=("${source_and_destination[@]:0:${#source_and_destination[@]}-1}")
    local destination="${source_and_destination[${#source_and_destination[@]}-1]}"

    echo "port: $port"
    echo "backup_docs: ${backup_docs[@]}"
    echo "source: ${source[@]}"
    echo "destination: $destination"
    echo "rsync_options: $rsync_options"

    local rsync_command="rsync $rsync_options -e 'ssh -p $port' ${source[@]} $destination"
    echo "Running command: $rsync_command"
    eval $rsync_command
}

backup_configs=()
while IFS=$'\n' read -r line; do
    backup_configs+=("$line")
done < <(jq -c '.backup_configs[]' "$config_file")

for backup_config in "${backup_configs[@]}"; do
    port=$(echo "$backup_config" | jq -r '.port')
    backup_docs=()
    while IFS=$'\n' read -r line; do
        backup_docs+=("$line")
    done < <(echo "$backup_config" | jq -r '.backup_docs[]')
    remote_path=$(echo "$backup_config" | jq -r '.remote_path')
    local_path=$(echo "$backup_config" | jq -r '.local_path')

    backup_files "$port" backup_docs[@] "$remote_path" "$local_path" $direction $backup
done
