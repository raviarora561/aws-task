#!/bin/bash

IP_ADDRESS="your_ec2_public_ip"

response=$(curl -so /dev/null -w "%{http_code}" http://$IP_ADDRESS)

if [ "$response" -eq 200 ]; then
  echo "Test Passed: Website is up with HTTP 200."
else
  echo "Test Failed: Website is not accessible. HTTP Status Code: $response"
fi
