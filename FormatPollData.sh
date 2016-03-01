#!/bin/bash
# META =========================================================================
# Title: FormatPollData.sh
# Usage: FormatPollData.sh
# Description: Format poll data from csv and organize by poll id, poll group id.
# Author: Colin Shea
# Created: 2016-01-16

# poll_groups
#   keys - poll group id: md5 hash of poll labels [poll info, poll results]
#   vals - poll ids

# poll_ids
#   keys - numeric index (ordered by appearance in csv)
#   vals - unique poll id

# poll_infos
#   keys - poll id
#   vals - info (end date, start date, source, sample size, margin of error)

# poll_results
#   keys - poll id
#   vals - results for each candidate

# poll_info_labels
#   keys - poll group id
#   vals - labels for poll info

# poll_result_labels
#   keys - poll group id
#   vals - labels for poll results (list of candidates)

# TODO:
# handle missing date (DPN 004)
# date filter
# round decimal percentages to int

# FIXED:
# reformat dates
# remove ',' from numeric values like sample size
# use other uniq id as ref id since ref is not reliable
# handle missing poll ref
# handle multiple [ref_id] per row 
# remove all refs
# consolidate 'Others' category
# zero-pad '%03s' poll ids
# zero-pad '%02u' and remove spaces from results

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

ROOTDIR="/cygdrive/c/users/sheacd/GitHub/Polls/2016 Presidential Election/data/"

if [[ -z "${OUT_FILE}" ]]; then
  temp_name="${IN_FILE##\/}"
  OUT_FILE="${ROOTDIR}/${temp_name%.*}"
fi
#OUT_FILE="${ROOTDIR}/RPN_"

# functions ====================================================================
function format_poll_info {
  poll_info="${poll_info%,}"                  # remove trailing ','
  poll_info="${poll_info//\[[[:digit:]]*\]/}" # remove wiki citations '[ref]'
#  poll_info="${poll_info##[\s]+}"               # remove leading whitespace
  # remove thousand separator
  x="${poll_info%%[0-9],[0-9][0-9][0-9]*}"
  if [[ ${#x} -ne ${#poll_info} ]]; then
    pos1=$(( ${#x} + 1 ))
    pos2=$(( ${#x} + 2 ))
    poll_info="${poll_info:0:$pos1}${poll_info:$pos2}"
  fi
}

function format_poll_result {
  poll_result="${poll_result%, }"      # remove trailing ','
  poll_result="${poll_result//%/}"     # remove '%'
  poll_result="${poll_result//—/0}"    # replace '—' with '0'
  poll_result="${poll_result//&lt;/}"  # remove '&lt;'
  # remove non-numeric chars except comma, semicolon, space
  poll_result="${poll_result//[^0-9,;\ ]/}"
  # consolidate 'Others' category results into one numeric value
  other_results=( ${poll_result##*,} )
  # sum numeric values
  sum=0
  for num in "${other_results[@]}"; do 
    : $(( sum += $num ))
  done
  # replace string value with sum
  poll_result="${poll_result%,*}, ${sum}"
  # zero-pad and remove spaces from results
  printf -v poll_result '%02u,' ${poll_result//,/}
}

function format_poll_date {
  # remove non-date characters
  poll_date="${poll_date//–/ }" # en dash
  poll_date="${poll_date//-/ }" # 
  poll_date="${poll_date//,/}"
  # date element regexes
  month_re='[A-Z][a-z]+'
  year_re='20[012][0-9]'
  day_re='^[0-9]{1,2}$'
  months=()
  years=()
  days=()
  # check each word for match and add to appropriate date element array
  for str in ${poll_date}; do 
    [[ "${str}" =~ ${month_re} ]] && months+=( ${BASH_REMATCH[0]} )
    [[ "${str}" =~ ${year_re} ]] && years+=( ${BASH_REMATCH[0]} )    
    [[ "${str}" =~ ${day_re} ]] && days+=( ${BASH_REMATCH[0]} )
  done
  # convert month names to MM
  month_to_mm "${months[0]}" "month0"
  month_to_mm "${months[-1]}" "month1"
  # compose start and end dates
  printf -v start_date '%04u-%02u-%02u' "${years[0]}" "${month0}" "${days[0]}"
  printf -v end_date '%04u-%02u-%02u' "${years[-1]}" "${month1}" "${days[-1]}"
}

# convert Month names to MM, eg "January" -> "1", "December" -> "12"
function month_to_mm {
  case "$1" in 
    Jan*)  MM=1 ;;
    Feb*)  MM=2 ;;
    Mar*)  MM=3 ;;
    Apr*)  MM=4 ;;
    May)   MM=5 ;;
    Jun*)  MM=6 ;;
    Jul*)  MM=7 ;;
    Aug*)  MM=8 ;;
    Sep*)  MM=9 ;;
    Oct*)  MM=10 ;;
    Nov*)  MM=11 ;;
    Dec*)  MM=12 ;;
    *) echo "Invalid month: $1"; MM=0 ;;
  esac
  printf -v "$2" '%u' ${MM}
}

# write array to file as key delim value
function serialize_array {
  # create local array from keys of passed array name
  local -a 'keys=( "${!'"$1"'[@]}" )'
  delim="$2"    # key/index delimiter
  outfile="$3"  # output filename
  for key in "${keys[@]}"; do
    ref=${1}[$key]
    printf '%s\n' "${key}"${delim}"${!ref}"
  done | sort > "${outfile}"
}

# main =========================================================================

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
declare -A poll_infos
declare -A poll_results
declare -A poll_info_labels
declare -A poll_result_labels

poll_id_count=0
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
  # save to poll group's label array
  poll_info_labels[${poll_group}]="${poll_info_label}"
  poll_result_labels[${poll_group}]="${poll_result_label}"
  # for each poll between label rows
  for ((j=${poll_label_nums[$i]}; j<$((${poll_label_nums[$(($i+1))]} -1)); j++ )); do
    poll_line="${content[$j]}"
    : $((poll_id_count++))
#    # extract poll id from first citation reference, eg "[89]" (replaced)
    printf -v poll_id '%03u' "$poll_id_count"
    # extract poll info (source, sample size, margin of error, dates admin)
    x="${poll_line%%201[23456],*}"
    pos=$(( ${#x} + 5 ))
    poll_info="${poll_line:0:$pos}"
    # if there was no match for a year in date administered
    if [[ "${poll_info}" == "${poll_line}" ]]; then
      # set info to match previous poll
      poll_info="${poll_infos[${poll_ids[@]: -1}]}"
      # set substring position to 0 because the entire line is a set of results
      pos=0
    else
      format_poll_info
      y="${poll_info%%, [A-Z]*}"
      dpos=$(( ${#y} + 2 ))
      poll_date="${poll_info:$dpos}"
      poll_info="${poll_info:0:${#y}}"
      format_poll_date
#      poll_info=" ${end_date}, ${start_date}, ${poll_info}"
      poll_info="${poll_info}, ${end_date}, ${start_date}"
    fi

    poll_result="${poll_line:$pos}"
    format_poll_result

    # reformat date to YYYYMMDD or YYYYDDD
    # cross-check with 538 poll ratings

    # add each value to corresponding array
    poll_groups[${poll_group}]="${poll_groups[$poll_group]}, ${poll_id}"
    poll_ids[${#poll_ids[@]}]="${poll_id}"
    poll_infos[${poll_id}]="${poll_info}"
    poll_results[${poll_id}]="${poll_result}"
  done
done

# remove leading empty element from poll groups
for group in "${!poll_groups[@]}"; do
  poll_groups[$group]="${poll_groups[$group]#, }"
done


# write (serialize) each array to file =========================================

# data organized by poll group id
serialize_array poll_groups        ';' "${OUT_FILE}_poll_groups.csv"
serialize_array poll_info_labels   ';' "${OUT_FILE}_poll_info_labels.csv"
serialize_array poll_result_labels ';' "${OUT_FILE}_poll_result_labels.csv"

# data organized by poll id
serialize_array poll_ids     ';' "${OUT_FILE}_poll_ids.csv"
serialize_array poll_infos   ';' "${OUT_FILE}_poll_infos.csv"
serialize_array poll_results ';' "${OUT_FILE}_poll_results.csv"

# for key in "${!poll_groups[@]}"; do
#   printf '%s\n' "${key};${poll_groups[$key]}"
# done > "${OUT_FILE}_poll_groups.csv"
# for key in "${!poll_info_labels[@]}"; do
#   printf '%s\n' "${key};${poll_info_labels[$key]}"
# done > "${OUT_FILE}_poll_info_labels.csv"
# for key in "${!poll_result_labels[@]}"; do
#   printf '%s\n' "${key};${poll_result_labels[$key]}"
# done > "${OUT_FILE}_poll_result_labels.csv"

# for key in "${!poll_ids[@]}"; do
#   printf '%s\n' "${key};${poll_ids[$key]}"
# done > "${OUT_FILE}_poll_ids.csv"
# for key in "${!poll_infos[@]}"; do
#   printf '%s\n' "${key};${poll_infos[$key]}"
# done > "${OUT_FILE}_poll_infos.csv"
# for key in "${!poll_results[@]}"; do
#   printf '%s\n' "${key};${poll_results[$key]}"
# done > "${OUT_FILE}_poll_results.csv"

#    # extract poll id from first citation reference, eg "[89]"
#    x1="${poll_line%%[*}"
#    pos1=$(( ${#x1} + 1 ))
#    x2="${poll_line%%]*}"
#    pos2=$(( ${#x2} - $pos1 ))
#    poll_id="${poll_line:$pos1:$pos2}"
#    # if no match is found 
#    #   this poll has 2 rows of results or
#    #   this poll has no poll_id from wiki reference
#    if [[ ${#x1} -eq ${#poll_line} ]]; then
#      # set poll id to the previous one concatenated with 'b'
#      if [[ "${poll_ids[@]: -2:1}b" == "${poll_ids[@]: -1:1}" ]]; then 
#        poll_id="$(( ${poll_ids[@]: -2:1} + 1 ))"
#      else
#        poll_id="${poll_ids[@]: -1:1}"b
#      fi
#    fi
