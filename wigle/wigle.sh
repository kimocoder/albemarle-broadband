#!/usr/bin/env bash

###
# WiGLE API Harvester
#
# WiGLE <https://wigle.net/> provides a robust API, but no bulk data. This script will
# page through all of the results (at 100 records per page) and export them into a
# series of files. It’s resumable, storing state every time the program terminates).
#
# To use it, set up an account on WiGLE, and modify API_KEY to equal the value of your
# cURL-encoded API name and token, in the API_NAME:API_TOKEN format. Then specify the
# quadrangle that you want to retrieve data for (the only shape supported by the WiGLE
# API) as QUADRANGLE, maintaining the URL-encoded format. Then simply run this with
# ./wigle-sh.
#
# WiGLE provides a low cap of daily queries, so for building a map that numbers in the
# thousands of datapoints, contact them to explain your work and ask that they raise
# your account’s cap. It is an all-volunteer project -- be nice.
###

# Define our API key.
API_KEY=SPECIFY_API_KEY_HERE

# Define the quadrangle being retrieved.
QUADRANGLE="latrange1=37.72&latrange2=38.28&longrange1=-78.84&longrange2=-78.21"

# Every time this exits, record the state
function finish {
    echo "TOTAL_RECORDS=$TOTAL_RECORDS
PER_PAGE=$PER_PAGE
TOTAL_PAGES=$TOTAL_PAGES
START=$START
CURRENT_PAGE=$i" > .state
}
trap finish EXIT

# If a state file has been saved, get the state from that
if [ -f .state ]; then
    source .state
fi

# If we're lacking the basic variable about where to start, start at the beginning
if [ -z "$START" ]; then
    # Request the first 100 records, to get the scope of what we're doing here
    URL="https://api.wigle.net/api/v2/network/search?onlymine=false&$QUADRANGLE&lastupdt=20150101&freenet=false&paynet=false&resultsPerPage=100"
    curl -s -X GET "$URL" -H "accept: application/json" \
        -u "$API_KEY" --basic > wigle-0.json
    
    # Check for errors returned from the API
    SUCCESS=$(jq ".success" wigle-"$i".json)
    if [ "$SUCCESS" == "false" ]; then
        ERROR_MESSAGE=$(jq ".message" wigle-"$i".json)
        echo "The API returned the following error: $ERROR_MESSAGE"
        exit 1
    fi

    # Figure out how to do the paging
    TOTAL_RECORDS=$(jq ".totalResults" wigle-0.json)
    PER_PAGE=100
    ((TOTAL_PAGES="$TOTAL_RECORDS"/"$PER_PAGE"))
    # Round up
    TOTAL_PAGES=$(echo "$TOTAL_PAGES" | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
    START=$(jq ".search_after" wigle-0.json)
    CURRENT_PAGE=0
fi

# Figure out what page to start on
if [[ -n "$CURRENT_PAGE" ]]; then
    START_PAGE="$CURRENT_PAGE"
else
    START_PAGE=1
fi

# Iterate through all of the records
for (( i="$START_PAGE"; i<="$TOTAL_PAGES"; i++ )); do

    # Retrieve this page of records
    URL="https://api.wigle.net/api/v2/network/search?onlymine=false&$QUADRANGLE&lastupdt=20150101&freenet=false&paynet=false&resultsPerPage=100&searchAfter=$START"
    curl -s -X GET "$URL" -H "accept: application/json" -u "$API_KEY" --basic > wigle-"$i".json
    echo "$i" of "$TOTAL_PAGES"
    
    # Check for errors returned from the API
    SUCCESS=$(jq ".success" wigle-"$i".json)
    if [ "$SUCCESS" == "false" ]; then
        ERROR_MESSAGE=$(jq ".message" wigle-"$i".json)
        echo "The API returned the following error: $ERROR_MESSAGE"
        exit 1
    fi
    
    # Check for 404 errors
    HTTP_CODE=$(jq ".code" wigle-"$i".json)
    if [ "$HTTP_CODE" != "null" ]; then
        ERROR_MESSAGE=$(jq ".message" wigle-"$i".json)
        echo "The API returned an HTTP $HTTP_CODE with the following error: $ERROR_MESSAGE"
        exit 1
    fi

    # Assign a new value to start at for the next query
    START=$(jq ".search_after" wigle-"$i".json)
    if [[ -z "$START" ]]; then
        echo "All results retrieved"
        exit 0
    fi

done
