#!/bin/bash
# META =========================================================================
# Title: ParseWikiTable.sh
# Usage: ParseWikiTable.sh
# Description: Parse HTML table from wikipedia source to csv.
# Author: Colin Shea
# Created: 2015-12-28
# TODO:
#   trim leading whitespace, trailing ','

# DONE
#   use filename from input for default output name


scriptname=$(basename $0)
function usage {
  echo "Usage: $scriptname"
  echo "Parse HTML table from wikipedia to csv."
  echo ""
  echo "  -i, --input       input file (html)"
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

# 
if [[ -z "${OUT_FILE}" ]]; then
  OUT_FILE="${IN_FILE%.*}.csv"
fi

# first grab each wikitable table into separate array
echo "Reading from file: ${IN_FILE}"
mapfile -t content < "${IN_FILE}"
# get line numbers of table open/close tags
echo "Parsing tables"
mapfile -t table_o < \
  <( printf '%s\n' "${content[@]}" | \
     grep -n '<table class="wikitable"' | \
     cut -d: -f1 )
mapfile -t table_c < \
  <( printf '%s\n' "${content[@]}" | \
     grep -n '</table>' | \
      cut -d: -f1 )

i=0
# for each table
for line_o in "${table_o[@]}"; do
  # match opening, closing tags
  while [[ "${table_c[$i]}" -lt "${line_o}" ]]; do : $((i++)); done
  num_lines=$(( ${table_c[$i]} - $line_o - 1 ))
  table="${content[*]:$line_o:$num_lines}"

  # for each table
  # remove html markup
  # remove tags and attributes except tr, td, th
  # replace td and /td with ','
  # replace tr and /tr with '\n'
  printf '%s' "${table[@]}" | \
    sed -e 's, id=,,g;s, href=,,g;s, class=,,g;s, style=,,g;s, title=,,g;s, rowspan=,,g;s, rel=,,g' \
        -e 's,"[^"]*",,g;s,&#160;?,,g' \
        -e 's,</*a>,,g;s,</*b>,,g;s,</*p>,,g;s,</*sup>,,g;s,</*span>,,g;s,</*small>,,g;s,</*abbr>,,g' \
        -e 's,</*th>,,g;s,<br\ />,,g;s,<td>,,g;s,</td>,\,,g;s,<tr>,,g;s,</tr>,\n,g' >> "${OUT_FILE}"

done 


