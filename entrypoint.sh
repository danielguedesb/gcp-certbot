#!/bin/bash
set -euo pipefail

function join_by { local IFS="$1"; shift; echo "$*"; }

GCP_PROJECT=$1
GCP_SA=$2
FRONT_END=$3
GCS_BUCKET=$4
TAR_PASSWORD=$5
EMAIL=$6
DOMAIN=$7

echo '*************** Setting up gcloud ***************'
echo $GCP_SA > sa.json
gcloud auth activate-service-account --key-file=sa.json --project=$GCP_PROJECT

FILE_PATH=gs://${GCS_BUCKET}/certificate.tar.gz
EXISTS=$(gsutil -q stat $FILE_PATH || echo 1)

if [[ $EXISTS != 1 ]]; then
  echo "*************** Fetching previous certificate from $GCS_BUCKET ***************"
  gsutil cp $FILE_PATH certificate.tar.gz

  if [[ -z $TAR_PASSWORD ]]; then
    tar -zxf certificate.tar.gz --directory /etc/letsencrypt/
  else
    gpg --pinentry-mode=loopback --passphrase "$TAR_PASSWORD" -d certificate.tar.gz  | tar --directory /etc/letsencrypt/ -zxf -
  fi
else
  echo "Certificate not found on $GCS_BUCKET, will attempt to create a new one"
fi

echo "*************** Creating or renewing certificate for $DOMAIN ***************"
certbot certonly -n --dns-google-credentials sa.json --agree-tos -m $EMAIL \
--non-interactive --dns-google --dns-google-propagation-seconds 90 \
--domain $DOMAIN --domain *.${DOMAIN}

tar -zcf certificate.tar.gz --directory /etc/letsencrypt/ .
if [[ ! -z $TAR_PASSWORD ]]; then
  mv certificate.tar.gz cert.tar.gz
  gpg --batch --yes --pinentry-mode loopback --passphrase "$TAR_PASSWORD" -o certificate.tar.gz -c cert.tar.gz
fi

echo '*************** Uploading created/renewed certificate to storage ***************'
gsutil cp certificate.tar.gz $FILE_PATH

if [[ -z $TAR_PASSWORD ]]; then
  tar -zxf certificate.tar.gz
else
  gpg --pinentry-mode=loopback --passphrase "$TAR_PASSWORD" -d certificate.tar.gz  | tar -zxf -
fi

SERIAL=`openssl x509 -in ./live/${DOMAIN}/cert.pem -serial -noout | awk -F= '{print tolower($2)}'`
NAME=`echo ${DOMAIN}-${SERIAL} | sed 's/\./-/g'`

if gcloud compute ssl-certificates list | grep "$SERIAL"; then
  echo "*************** Certificate with serial $SERIAL has already been added to $GCP_PROJECT ***************"
  CERT=`gcloud compute ssl-certificates list --filter="name~'$SERIAL'" --limit 1 --sort-by ~creationTimestamp --format="value(name)"`
else
  echo "*************** Adding certificate $NAME to $GCP_PROJECT ***************"

  # Create a new ssl-certificate entry
  gcloud compute ssl-certificates create $NAME --certificate=./live/${DOMAIN}/fullchain.pem --private-key=./live/${DOMAIN}/privkey.pem

  # Get the most recent certificate for this domain (should be the one we just created)
  CERT=`gcloud compute ssl-certificates list --filter="name~'^${DOMAIN}.*'" --limit 1 --sort-by ~creationTimestamp --format="value(name)"`
fi

if [[ ! -z "$FRONT_END" ]]; then
  echo "*************** Updating $FRONT_END ***************"

  PROXY=`gcloud compute forwarding-rules list --filter="name~'${FRONT_END}'" --format="value(target.scope())"`

  if [[ -z "$PROXY" ]]; then
    echo "*************** No forwarding-rule found, associated with front-end name $FRONT_END, did you spell it correctly? **************"
    exit 1
  fi

  # Get all certificates currently on the load-balancer
  EXISTING_CERTS=`gcloud compute target-https-proxies describe $PROXY --format="flattened(sslCertificates[].basename())" | awk '{print $2}'`

  # Strip any for this domain
  OTH_CERTS=`echo $EXISTING_CERTS | grep -v "^$DOMAIN" || true`

  # Add the new cert plus all other domains, to make a comma-separated list of all certs to use
  ALL_CERTS=`join_by , $CERT $OTH_CERTS`

  # Set the certificate list on the load-balancer
  gcloud compute target-https-proxies update $PROXY --ssl-certificates=$ALL_CERTS
fi

echo "::set-output name=certificate-name::$NAME"