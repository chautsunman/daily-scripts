#!/bin/bash

usage() {
    echo "Usage: $0 <backup> <config_file> [--tag <tag_filter>] [--name <name_filter>]"
    exit 1
}

if [ "$#" -lt 2 ]; then
    usage
fi

backup=("$1" = "true")
config_file="$2"
shift 2

tag_filter=""
name_filter=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --tag)
            if [[ -z "$2" || "$2" == --* ]]; then
                usage
            fi
            tag_filter="$2"
            shift 2
            ;;
        --name)
            if [[ -z "$2" || "$2" == --* ]]; then
                usage
            fi
            name_filter="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [ ! -f "$config_file" ]; then
    echo "Error: Config file '$config_file' does not exist"
    exit 1
fi

echo "Current directory"
pwd
echo "Backup: $backup"
echo "Config file: $config_file"
echo "Tag filter: $tag_filter"
echo "Name filter: $name_filter"

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
    local delete_option=$7

    local rsync_options=""
    if [ "$backup" = true ]; then
        rsync_options="-avz"
    else
        rsync_options="-avzn"
    fi

    if [ "$delete_option" = "true" ]; then
        rsync_options="$rsync_options --delete"
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
    backup_config_tag=$(echo "$backup_config" | jq -r '.tag')
    backup_config_name=$(echo "$backup_config" | jq -r '.name')
    if [[ -n "$tag_filter" && "$backup_config_tag" != "$tag_filter" ]]; then
        continue
    fi
    if [[ -n "$name_filter" && "$backup_config_name" != "$name_filter" ]]; then
        continue
    fi

    direction=$(echo "$backup_config" | jq -r '.direction')
    port=$(echo "$backup_config" | jq -r '.port')
    backup_docs=()
    while IFS=$'\n' read -r line; do
        backup_docs+=("$line")
    done < <(echo "$backup_config" | jq -r '.backup_docs[]')
    remote_path=$(echo "$backup_config" | jq -r '.remote_path')
    local_path=$(echo "$backup_config" | jq -r '.local_path')
    delete_option=$(echo "$backup_config" | jq -r '.delete // false')

    backup_files "$port" backup_docs[@] "$remote_path" "$local_path" "$direction" $backup "$delete_option"
done
