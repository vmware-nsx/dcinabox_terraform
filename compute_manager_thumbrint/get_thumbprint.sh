#!/bin/bash
set -e

# Read the input JSON from stdin
input=$(cat)

# Extract the server and port from the input JSON
server=$(echo "$input" | jq -r '.server')
port=$(echo "$input" | jq -r '.port')

# Use OpenSSL to get the server certificate
certificate=$(echo | openssl s_client -connect "$server:$port" -servername "$server" 2>/dev/null | openssl x509)

# Extract the SHA256 thumbprint of the certificate
thumbprint=$(echo "$certificate" | openssl x509 -noout -fingerprint -sha256 | sed 's/^.*=//')

# Output the result as JSON
jq -n --arg thumbprint "$thumbprint" '{"thumbprint":$thumbprint}'
