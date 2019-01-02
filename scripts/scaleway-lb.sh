#!/bin/sh

alias curl_scw='curl -s -H "accept: application/json" -H "X-Auth-Token: $SCALEWAY_TOKEN" -H "Content-Type: application/json" '

curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs | jq -r -e ".lbs[] | select(.name ==  \"$SCALEWAY_LB_NAME\") | .id" > /dev/null 2>&1

if [ $? -eq 0 ]; then # found at least one LB with this name, delete them
  if [ "$DELETE_EXISTING" -ne "true" ]; then
    curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs | jq -r -e ".lbs[] | select(.name ==  \"$SCALEWAY_LB_NAME\") | .id" | while read lb;
      do
        curl_scw -X DELETE "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$lb" -d "{\"release_ip\": false}"
      done
    sleep 5
  
    # create the Load Balancer
    curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs" -d "{\"description\":\"Scaleway LB\",\"name\":\"$SCALEWAY_LB_NAME\",\"organization_id\":\"$SCALEWAY_ORGANIZATION\"}" > /dev/null
  fi
else
  # create the Load Balancer
  curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs" -d "{\"description\":\"Scaleway LB\",\"name\":\"$SCALEWAY_LB_NAME\",\"organization_id\":\"$SCALEWAY_ORGANIZATION\"}" > /dev/null
fi

LB_ID=$(curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs | jq -r -e ".lbs[] | select(.name ==  \"$SCALEWAY_LB_NAME\") | .id")

# wait for the LB to have ready status
n=0
until [ $n -ge 12 ]
do
  curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs | jq -r -e ".lbs[] | select(.name ==  \"$SCALEWAY_LB_NAME\" and .status == \"ready\")" > /dev/null 2>&1 && break
  n=`expr $n + 1`
  sleep 5
done

# delete all backends and frontends
curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/frontends | jq -r -e '.frontends[] | .id' | while read frontend;
  do
    curl_scw -X DELETE "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/frontends/$frontend" -d "{}"
  done

curl_scw -X GET https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/backends | jq -r -e '.backends[] | .id' | while read backend;
  do
    curl_scw -X DELETE "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/backends/$backend" -d "{}"
  done

echo "LB_ID=$LB_ID"

# create Kubernete API server backend
KUBE_API_SERVER_BACKEND_ID=$(curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/backends" -d "{\"forward_port\":$KUBE_API_SERVER_FORWARD_PORT,\"forward_port_algorithm\":\"roundrobin\",\"forward_protocol\":\"tcp\",\"health_check\":{\"check_delay\":2000,\"check_max_retries\":3,\"check_timeout\":1000,\"port\":$KUBE_API_SERVER_PORT,\"tcp_config\":{}},\"name\":\"Kubernetes API server backend\",\"send_proxy_v2\":false,\"server_ip\":[$MASTER_NODES_IPS]}" | jq -r -e '.id')

if [ $? -ne 0 ]; then
  echo "Unable to create Kubernetes API server backend"
  exit 1
fi

# create HTTP backend
HTTP_BACKEND_ID=$(curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/backends" -d "{\"forward_port\":30080,\"forward_port_algorithm\":\"roundrobin\",\"forward_protocol\":\"tcp\",\"health_check\":{\"check_delay\":2000,\"check_max_retries\":3,\"check_timeout\":1000,\"port\":30080,\"tcp_config\":{}},\"name\":\"HTTP backend\",\"send_proxy_v2\":false,\"server_ip\":[$MASTER_NODES_IPS]}" | jq -r -e '.id')

if [ $? -ne 0 ]; then
  echo "Unable to create HTTP backend"
  exit 1
fi

# create HTTP backend
HTTPS_BACKEND_ID=$(curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/backends" -d "{\"forward_port\":30443,\"forward_port_algorithm\":\"roundrobin\",\"forward_protocol\":\"tcp\",\"health_check\":{\"check_delay\":2000,\"check_max_retries\":3,\"check_timeout\":1000,\"port\":30443,\"tcp_config\":{}},\"name\":\"HTTPS backend\",\"send_proxy_v2\":false,\"server_ip\":[$MASTER_NODES_IPS]}" | jq -r -e '.id')

if [ $? -ne 0 ]; then
  echo "Unable to create HTTPS backend"
  exit 1
fi

echo "KUBE_API_SERVER_BACKEND_ID=$KUBE_API_SERVER_BACKEND_ID"

# create Kubernetes API server frontend 
curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/frontends" -d "{\"backend_id\":\"$KUBE_API_SERVER_BACKEND_ID\",\"inbound_port\":$KUBE_API_SERVER_PORT,\"inbound_protocol\":\"tcp\",\"name\":\"Kubernetes API server frontend\",\"timeout_client\":5000}" > /dev/null
# create HTTP frontend 
curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/frontends" -d "{\"backend_id\":\"$HTTP_BACKEND_ID\",\"inbound_port\":80,\"inbound_protocol\":\"tcp\",\"name\":\"HTTP frontend\",\"timeout_client\":5000}" > /dev/null
# create HTTPS frontend 
curl_scw -X POST "https://api-world.scaleway.com/lbaas/v1beta1/lbs/$LB_ID/frontends" -d "{\"backend_id\":\"$HTTPS_BACKEND_ID\",\"inbound_port\":443,\"inbound_protocol\":\"tcp\",\"name\":\"HTTPS frontend\",\"timeout_client\":5000}" > /dev/null
