#!/bin/bash

# Check if a secret name and file paths are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <secret-name> <path-to-tls.crt> <path-to-tls.key>"
    echo "--------------------------------"
    echo "Available Secrets/Certs:"
    kubectl get secret -n traefik-v2-system  | awk '{print $1}' | grep cert
    echo "--------------------------------"
    exit 1
fi

SECRET_NAME=$1
CRT_FILE_PATH=$2
KEY_FILE_PATH=$3
NAMESPACE=traefik-v2-system
TODAY=$(date +%Y-%m-%d)

# Backup current secret
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml > "${SECRET_NAME}_backup_${TODAY}.yaml"
echo "Backup created: ${SECRET_NAME}_backup_${TODAY}.yaml"

# Function to print certificate details
print_cert_details() {
    local cert_path=$1
    echo "Certificate details for $cert_path:"
    openssl x509 -in "$cert_path" -noout -subject -dates
}

# Print details of the current certificate
current_cert=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.tls\.crt}" | base64 --decode)
echo "$current_cert" > current_cert.pem
print_cert_details current_cert.pem
rm current_cert.pem

# Print details of the new certificate
print_cert_details "$CRT_FILE_PATH"

# Check if the certificate and key match
openssl x509 -noout -modulus -in "$CRT_FILE_PATH" | openssl md5 > cert_md5
openssl rsa -noout -modulus -in "$KEY_FILE_PATH" | openssl md5 > key_md5
if cmp -s cert_md5 key_md5; then
    echo "Certificate and key match."
else
    echo "Certificate and key do not match!"
    exit 1
fi
rm cert_md5 key_md5

# Base64 encode the new certificate and key
new_cert_base64=$(cat "$CRT_FILE_PATH" | base64 | tr -d '\n')
new_key_base64=$(cat "$KEY_FILE_PATH" | base64 | tr -d '\n')

# Patch the secret
kubectl patch secret "$SECRET_NAME" -n "$NAMESPACE" --type='json' -p="[
  {\"op\": \"replace\", \"path\": \"/data/tls.crt\", \"value\":\"${new_cert_base64}\"},
  {\"op\": \"replace\", \"path\": \"/data/tls.key\", \"value\":\"${new_key_base64}\"}
]"

echo "Secret '$SECRET_NAME' in namespace '$NAMESPACE' updated successfully."

