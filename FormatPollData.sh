#!/bin/bash
# META =========================================================================
# Title: FormatPollData.sh
# Usage: FormatPollData.sh
# Description: Format poll data from csv to arrays.
# Author: Colin Shea
# Created: 2016-01-16

# TODO:
# handle missing date
#  [126] Hot Air/Townhall/Survey Monkey
# poll_group: list of poll_ids belonging to the same set of labels

# FIXED:
# handle multiple [ref_id] per row 


scriptname=$(basename $0)
function usage {
  echo "Usage: $scriptname"
  echo "Format poll data from csv to arrays."
  echo ""
  echo "  -i, --input       input file (csv)"
  echo "  -o, --output      output file (csv)"
  echo "  -h, --help        display help"
}

# set input values from command line arguments 
while [[ $# > 0 ]]; do
  arg="$1"
  case "$arg" in
    -i|--input)   IN_FILE="$2"; shift ;;  # input file
    -o|--output) OUT_FILE="$2"; shift ;;  # output file
    -h|--help)           usage;  exit ;;  # print help
    *) echo "Unknown option: $1" ;;   # unknown option
  esac
  shift
done

# first grab each wikitable table into separate array
echo "Reading from file: ${IN_FILE}"
mapfile -t content < "${IN_FILE}"

echo "Parsing polls"
mapfile -t poll_label_nums < \
  <( printf '%s\n' "${content[@]}" | \
    grep -n "^ Poll source Sample size" | \
    cut -d: -f1 )
# add num of last line in file to act as end condition
poll_label_nums[${#poll_label_nums[@]}]=$(( ${#content[@]} + 1 ))

declare -a poll_ids
declare -A poll_groups
# associative because poll_id can include non-numeric characters
declare -A poll_info_arr
declare -A poll_result_arr
declare -A poll_info_label_arr
declare -A poll_result_label_arr

# for each set of labels (namely, list of candidates in poll)
for ((i=0; i<$(( ${#poll_label_nums[@]} - 1 )); i++)); do
  # hash labels for this group of polls
  poll_labels="${content[$(( ${poll_label_nums[$i]} - 1))]}"
  poll_md5=( $(printf '%s' "${poll_labels}" | md5sum) )
  poll_group="${poll_md5[0]}"
  # split labels into poll info (source, stats, date) and results (candidates)
  # "dates administered " is the boundary to split labels on
  x="${poll_labels%%administered *}"
  pos=$(( ${#x} + 13 ))
  poll_info_label="${poll_labels:0:$pos}"
  poll_result_label="${poll_labels:$pos}"
  # for each poll between label rows
  for ((j=${poll_label_nums[$i]}; j<$((${poll_label_nums[$(($i+1))]} -1)); j++ )); do
    poll_line="${content[$j]}"
    # extract poll id from first citation reference, eg "[89]"
    x1="${poll_line%%[*}"
    pos1=$(( ${#x1} + 1 ))
    x2="${poll_line%%]*}"
    pos2=$(( ${#x2} - $pos1 ))
    poll_id="${poll_line:$pos1:$pos2}"
    # if no match is found (because this poll has 2 rows of results)
    if [[ ${#x1} -eq ${#poll_line} ]]; then
      # set poll id to the previous one concatenated with 'b'
      poll_id="${poll_ids[@]: -1}"b
    fi
    # extract poll info (source, sample size, margin of error, dates admin)
    x="${poll_line%%201[23456],*}"
    pos=$(( ${#x} + 5 ))
    poll_info="${poll_line:0:$pos}"
    # if there was no match for a year in date administered
    if [[ "${poll_info}" == "${poll_line}" ]]; then
      # set info to match previous poll
      poll_info="${poll_info_arr[${poll_ids[@]: -1}]}"
      # set substring position to 0 because the entire line is a set of results
      pos=0
    fi
    poll_result="${poll_line:$pos}"
    # add each value to corresponding array
    poll_groups[${poll_group}]="${poll_groups[$poll_group]}, ${poll_id}"
    poll_ids[${#poll_ids[@]}]="${poll_id}"
    poll_info_arr[${poll_id}]="${poll_info}"
    poll_result_arr[${poll_id}]="${poll_result}"
    poll_info_label_arr[${poll_id}]="${poll_info_label}"
    poll_result_label_arr[${poll_id}]="${poll_result_label}"
  done
done

# remove leading empty element
for group in "${!poll_groups[@]}"; do
  poll_groups[$group]="${poll_groups[$group]#, }"
done

for group in "${!poll_groups[@]}"; do
  first_id="${poll_groups[$group]%%,*}"
  printf '%s\n' "${poll_result_label_arr[$first_id]}"
  for id in $(printf '%s\n' ${poll_groups[$group]//,/} ); do
#    printf '%s\n' "${id}"
  #  printf '%s\n' "${poll_info_arr[$id]}"
  #  printf '%s\n' "${poll_result_label_arr[$id]}"
    printf '%s\n' "${poll_result_arr[$id]//%/}"
  done
done
# replace date labels with YYYYMMDD or YYYYDDD

