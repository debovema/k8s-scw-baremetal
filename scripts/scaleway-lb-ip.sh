#!/bin/bash

set -e

eval "$(jq -r '@sh "SCALEWAY_LB_NAME=\(.lb_name)"')"

SCALEWAY_LB_IP=$(curl -s -H "accept: application/json" -H "X-Auth-Token: $SCALEWAY_TOKEN" -H "Content-Type: application/json" -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs | jq -r -e ".lbs[] | select(.name ==  \"$SCALEWAY_LB_NAME\" and .status == \"ready\") | .ip[0].ip_address")

jq -n --arg scaleway_lb_ip "$SCALEWAY_LB_IP" '{"scaleway_lb_ip":$scaleway_lb_ip}'