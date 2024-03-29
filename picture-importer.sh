#!/bin/bash

# TODO support recursing into directories

src=""
dest=""
dry_run=0
tz=$(date +%:z)

# parse command line arguments
while [[ $# -gt 0 ]]
do
    case $1 in
        -s|--source)
            src="$2"
            shift
            shift
            ;;
        -d|--destination)
            dest="$2"
            shift
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --video-tz-offset)
            tz="$2"
            shift
            shift
            ;;
        *)
            printf '\033[91merror:\033[0m %s is not a valid argument\n' "$1" && exit
    esac
done

# resolve paths
src=$(realpath "$src")
dest=$(realpath "$dest")

# validate command line arguments
[[ -z "$src" ]] && printf '\033[91merror:\033[0m source directory not provided\n' && exit
[[ -z "$dest" ]] && printf '\033[91merror:\033[0m destination directory not provided\n' && exit

[[ ! -d "$src" ]] && printf '\033[91merror:\033[0m %s is not a directory\n' "$src" && exit
[[ ! -d "$dest" ]] && printf '\033[91merror:\033[0m %s is not a directory\n' "$dest" && exit

if [[ -n "$tz" ]]; then
    ! (echo "$tz" | grep -Pq '^[+-]\d{2}:\d{2}$') && printf '\033[91merror:\033[0m %s is not a valid time zone offset\n' "$tz" && exit
fi

# if dry run, declare an associative array to hold our dates
[[ $dry_run -gt 0 ]] && declare -A dates

# declare an array to hold files without timestamps
no_timestamp=()

for path in "$src"/*;
do
    # skip directories. we'll allow for recursing later
    [[ -d "$path" ]] && printf '\033[93mwarning:\033[0m skipping directory %s\n' "$path" && continue

    # get just the file name, without extensions
    filename=$(basename "$path" | cut -d'.' -f 1)

    # extract timestamp
    # look through all files with the same name to find one with exif data
    timestamp_raw=""
    for sibling in "$src"/"$filename"*; do
        timestamp_raw=$(exiv2 -g Exif.Image.DateTime pr "$sibling" 2> /dev/null | tr -s ' ' | cut -d' ' -f 4-5)
        [[ -n "$timestamp_raw" ]] && break
    done

    if [[ -n "$timestamp_raw" ]]; then
        # parse timestamp
        date_raw=$(echo "$timestamp_raw" | cut -d' ' -f 1)

        year=$(echo "$date_raw" | cut -d':' -f 1)
        month=$(echo "$date_raw" | cut -d':' -f 2)
        day=$(echo "$date_raw" | cut -d':' -f 3)

        time=$(echo "$timestamp_raw" | cut -d' ' -f 2)

        hour=$(echo "$time" | cut -d':' -f 1)
        min=$(echo "$time" | cut -d':' -f 2)
        sec=$(echo "$time" | cut -d':' -f 3)

        date="${year}-${month}-${day}"
        timestamp="${year}${month}${day}_${hour}${min}${sec}"
    else
        # try to extract video timestamp
        timestamp_raw=$(ffprobe -v quiet "$path" -show_entries format_tags=creation_time | sed 2!d | cut -d'=' -f 2)
        ts_descriptor="$timestamp_raw"

        # here we assume that the video timestamps will be in UTC
        # if necessary, we can add logic to detect if they have an offset to begin with

        # parse timezone offset
        if [[ -n "$tz" ]]; then
            pm=$(echo "$tz" | cut -c 1)
            hr=$(echo "$tz" | cut -c 2-3)
            mn=$(echo "$tz" | cut -c 5-6)
            ts_descriptor="$timestamp_raw ${pm}${hr} hour ${pm}${mn} min"
        fi

        # get formatted timestamps
        date=$(date --date="$ts_descriptor" -u +%Y-%m-%d)
        timestamp=$(date --date="$ts_descriptor" -u +%Y%m%d_%H%M%S)
    fi

    # ensure timestamp is in the format we expect
    if ! (echo "$timestamp" | grep -Pq '^\d{8}_\d{6}$'); then
        no_timestamp+=("$path")
        continue
    fi

    # if dry run, display the number of files per date as we count them
    if [[ $dry_run -gt 0 ]]; then
        if [[ -z ${dates["$date"]} ]]; then
            (( ${#dates[@]} != 0 )) && printf '\n'
            dates["$date"]=0
        fi
        printf "\r%s: %s file(s)" "$date" $((dates["$date"] + 1))
        dates["$date"]=$((dates["$date"] + 1))
        continue
    fi

    # convert extension to lower case
    extension=$(basename "$path" | cut -d'.' -f 2- | tr '[:upper:]' '[:lower:]')

    # create new file name
    new_filename="${filename}.${extension}"

    # make directory and copy
    mkdir -p "${dest}/$date"
    cp -v --backup=t --no-preserve=mode,ownership "$path" "${dest}/${date}/${new_filename}"
done

# if dry run, print a newline, because we don't after counting the images for the final date
if [[ $dry_run -gt 0 ]]; then
    printf '\n'
fi

# list files with no timestamp
if (( ${#no_timestamp[@]} != 0 )); then
    printf 'files with no timestamp:\n'
    for path in "${no_timestamp[@]}"; do
        printf '%s\n' "$(basename "$path")"
    done
fi
