#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TIMESTAMP=$(date +%s)

### $LOG is just a CSV, $HUMAN_LOG is more descriptive 
LOG="$SCRIPT_DIR/log.txt"
HUMAN_LOG="$SCRIPT_DIR/humanlog.txt"

### Read inputs from JSON
JSON_IN="$SCRIPT_DIR/in.json"

PORKBUN_API_KEY=$(jq -r '.public_key' $JSON_IN)
PORKBUN_SECRET_API_KEY=$(jq -r '.private_key' $JSON_IN)
DOMAIN=$(jq -r '.domain' $JSON_IN)
DOMAIN_TYPE=$(jq -r '.domain_type' $JSON_IN)
TTL=$(jq -r '.ttl' $JSON_IN)

# Check if logs exist, create with headers if necessary
if [ ! -f $LOG ]; then
    echo "Time,IP,Update_necessary,Successful_change" >> $LOG
fi
if [ ! -f $HUMAN_LOG ]; then
    echo "--------------------------------------------------" >> $HUMAN_LOG
fi

touch $LOG
echo "Script run at: $TIMESTAMP" >> $HUMAN_LOG

### Read last state from $LOG
LAST_STATE=$(tail -n 1 $LOG)
LAST_IP=$(echo $LAST_STATE | cut -f 2 -d ',')
LAST_UPDATE_NEEDED=$(echo $LAST_STATE | cut -f 3 -d ',')
LAST_UPDATE_SUCCESS=$(echo $LAST_STATE | cut -f 4 -d ',')

CURRENT_IP=$(curl -s https://api.ipify.org);

# Abort if unable to get public IP
if [ -z "$CURRENT_IP" ]; then
    echo "$TIMESTAMP,$LAST_IP,0,0" >> $LOG
	echo "Unable to get IP. Exiting." >> $HUMAN_LOG
    echo "--------------------------------------------------" >> $HUMAN_LOG
	exit 1
else
    echo "Current IP: $CURRENT_IP" >> $HUMAN_LOG
fi


update_needed=0
update_success=0

### Decide if porkbun API is necessary
if [ "$LAST_IP" = "IP" ]; then
    echo "No previous entry in log.txt, will attempt to update porkbun." >> $HUMAN_LOG
    update_needed=1
elif [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "Current and last IP do not match, need update." >> $HUMAN_LOG
    update_needed=1
else 
    if [ "$LAST_UPDATE_NEEDED" = "1" ]; then
        if [ "$LAST_UPDATE_SUCCESS" = "1" ]; then
            update_needed=0
        else
            echo "Update pending, previous update not successful." >> $HUMAN_LOG
            update_needed=1
        fi
    else
        echo "No change in public IP: no update necessary."  >> $HUMAN_LOG
    fi

fi

### Enact API call(s)
GET="https://api.porkbun.com/api/json/v3/dns/retrieveByNameType/$DOMAIN/$DOMAIN_TYPE"
SET="https://api.porkbun.com/api/json/v3/dns/editByNameType/$DOMAIN/$DOMAIN_TYPE"

if [ $update_needed = '1' ]; then
    echo "Getting DNS IP address from porkbun:" >> $HUMAN_LOG
    
    GET_RESPONSE=$(curl -X POST "$GET" \
        -H "X-API-Key: $PORKBUN_API_KEY" \
        -H "X-Secret-API-Key: $PORKBUN_SECRET_API_KEY")

    if [[ "$GET_RESPONSE" != *'"status":"SUCCESS"'* ]]; then
        echo "Error: Unable to get DNS record." >> $HUMAN_LOG
        dns_ip=""
    else
        echo $GET_RESPONSE | jq '.' >> $HUMAN_LOG
        dns_ip=$(echo $GET_RESPONSE | jq -r '.records[0].content')
    fi

    if [ "$dns_ip" = "$CURRENT_IP" ]; then 
        echo "IP matches that fetched from Porkbun, no need for update."  >> $HUMAN_LOG
        update_needed=0
    else
        update_needed=1
        echo "Attempting to set IP on porkbun." >> $HUMAN_LOG
        SET_RESPONSE=$(curl -X POST "$GET" \
            -H 'Content-Type: application/json' \
            -d '{
                "apikey": "'"$PORKBUN_API_KEY"'", 
                "secretapikey": "'"$PORKBUN_SECRET_API_KEY"'", 
                "content": "'"$CURRENT_IP"'","ttl":"'"$TTL"'","prio":0}')
        echo $SET_RESPONSE | jq '.' >> $HUMAN_LOG

        if [[ "$SET_RESPONSE" == *'"status":"SUCCESS"'* ]]; then
            echo "Successfully updated IP!" >> $HUMAN_LOG
            update_success=1
        else
            echo "IP update failed." >> $HUMAN_LOG
            update_success=0
        fi
    fi 
fi 

### Write to logs
echo "$TIMESTAMP,$CURRENT_IP,$update_needed,$update_success" >> $LOG
echo "Entry in $LOG" >> $HUMAN_LOG
echo "$TIMESTAMP,$CURRENT_IP,$update_needed,$update_success" >> $HUMAN_LOG
echo "--------------------------------------------------" >> $HUMAN_LOG

exit 0
