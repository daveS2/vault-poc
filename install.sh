#bin/bash

#SOURCE: https://codelabs.developers.google.com/codelabs/vault-on-gke/

export GOOGLE_CLOUD_PROJECT=census-catd-dave
export LOCATION=europe-west2
export SERVICE_ACCOUNT="vault-server@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com"

gsutil mb -l ${LOCATION} "gs://${GOOGLE_CLOUD_PROJECT}-vault-storage" 

gcloud services enable \
    cloudapis.googleapis.com \
    cloudkms.googleapis.com \
    cloudresourcemanager.googleapis.com \
    cloudshell.googleapis.com \
    container.googleapis.com \
    containerregistry.googleapis.com \
    iam.googleapis.com

gcloud kms keyrings create vault \
    --location ${LOCATION}


 gcloud kms keys create vault-init \
    --location ${LOCATION} \
    --keyring vault \
    --purpose encryption

gcloud iam service-accounts create vault-server \
    --display-name "vault service account"

gsutil iam ch \
    "serviceAccount:${SERVICE_ACCOUNT}:objectAdmin" \
    "serviceAccount:${SERVICE_ACCOUNT}:legacyBucketReader" \
    "gs://${GOOGLE_CLOUD_PROJECT}-vault-storage"

gcloud kms keys add-iam-policy-binding vault-init \
    --location ${LOCATION} \
    --keyring vault \
    --member "serviceAccount:${SERVICE_ACCOUNT}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter

 gcloud services enable container.googleapis.com

 gcloud container clusters create vault \
    --cluster-version 1.14 \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-ip-alias \
    --machine-type n1-standard-2 \
    --node-version 1.14 \
    --num-nodes 1 \
    --region ${LOCATION}\
    --scopes cloud-platform \
    --service-account "${SERVICE_ACCOUNT}"

gcloud compute addresses create vault --region "${LOCATION}"


######## cert stuff ######

export LB_IP="$(gcloud compute addresses describe vault --region ${LOCATION} --format 'value(address)')"
export DIR="./tls"

cat > "${DIR}/openssl.cnf" << EOF
[req]
default_bits = 2048
encrypt_key  = no
default_md   = sha256
prompt       = no
utf8         = yes

distinguished_name = req_distinguished_name
req_extensions     = v3_req

[req_distinguished_name]
C  = UK
ST = HAMPSHIRE
L  = The Cloud
O  = Dave
CN = vault

[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names

[alt_names]
IP.1  = ${LB_IP}
DNS.1 = vault.default.svc.cluster.local
EOF

openssl genrsa -out "${DIR}/vault.key" 2048

openssl req \
    -new -key "${DIR}/vault.key" \
    -out "${DIR}/vault.csr" \
    -config "${DIR}/openssl.cnf"

openssl req \
    -new \
    -newkey rsa:2048 \
    -days 120 \
    -nodes \
    -x509 \
    -subj "/C=UK/ST=HAMPSHIRE/L=The Cloud/O=Vault CA" \
    -keyout "${DIR}/ca.key" \
    -out "${DIR}/ca.crt"

openssl x509 \
    -req \
    -days 120 \
    -in "${DIR}/vault.csr" \
    -CA "${DIR}/ca.crt" \
    -CAkey "${DIR}/ca.key" \
    -CAcreateserial \
    -extensions v3_req \
    -extfile "${DIR}/openssl.cnf" \
    -out "${DIR}/vault.crt"

cat "${DIR}/vault.crt" "${DIR}/ca.crt" > "${DIR}/vault-combined.crt"

##### end of confusing cert stuff #####

kubectl create configmap vault \
    --from-literal "load_balancer_address=${LB_IP}" \
    --from-literal "gcs_bucket_name=${GOOGLE_CLOUD_PROJECT}-vault-storage" \
    --from-literal "kms_project=${GOOGLE_CLOUD_PROJECT}" \
    --from-literal "kms_region=${LOCATION}" \
    --from-literal "kms_key_ring=vault" \
    --from-literal "kms_crypto_key=vault-init" \
    --from-literal="kms_key_id=projects/${GOOGLE_CLOUD_PROJECT}/locations/${LOCATION}/keyRings/vault/cryptoKeys/vault-init"

kubectl create secret generic vault-tls \
    --from-file "${DIR}/ca.crt" \
    --from-file "vault.crt=${DIR}/vault-combined.crt" \
    --from-file "vault.key=${DIR}/vault.key"

export VAULT_ADDR="https://${LB_IP}:443"

export VAULT_CACERT="${DIR}/ca.crt"

export VAULT_TOKEN="$(gsutil cat "gs://${GOOGLE_CLOUD_PROJECT}-vault-storage/root-token.enc" | \
  base64 --decode | \
  gcloud kms decrypt \
    --location ${LOCATION} \
    --keyring vault \
    --key vault-init \
    --ciphertext-file - \
    --plaintext-file -)"