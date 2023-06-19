#!/bin/bash

# TODO support videos
# TODO support recursing into directories
# TODO support pictures taken in the same second

src=""
dest=""
dry_run=0

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
        *)
            printf '\033[91merror:\033[0m %s is not a valid argument\n' "$1" && exit
    esac
done

# validate command line arguments
[[ -z "$src" ]] && printf '\033[91merror:\033[0m source directory not provided\n' && exit
[[ -z "$dest" ]] && printf '\033[91merror:\033[0m destination directory not provided\n' && exit

[[ ! -d "$src" ]] && printf '\033[91merror:\033[0m %s is not a directory\n' "$src" && exit
[[ ! -d "$dest" ]] && printf '\033[91merror:\033[0m %s is not a directory\n' "$dest" && exit

# if dry run, declare an associative array to hold our dates
[[ $dry_run -gt 0 ]] && declare -A dates

# if dry run, declare an array to hold files without timestamps
[[ $dry_run -gt 0 ]] && no_timestamp=()

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
        timestamp_raw=$(exiv2 -g Exif.Image.DateTime pr "$sibling" | tr -s ' ' | cut -d' ' -f 4-5)
        [[ -n "$timestamp_raw" ]] && break
    done

    if [[ -z "$timestamp_raw" ]]; then
        no_timestamp+=("$path")
        printf '\033[93mwarning:\033[0m no timestamp for file %s\n' "$path"
        continue
    fi

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
    timestamp=$"${year}${month}${day}_${hour}${min}${sec}"

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
    new_filename="${timestamp}.${extension}"

    # make directory and copy
    mkdir -p "${dest}/$date"
    cp -v --no-preserve=mode,ownership "$path" "${dest}/${date}/${new_filename}"
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
