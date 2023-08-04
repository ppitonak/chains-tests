#!/bin/bash

set +x

oc delete secret signing-secrets -n openshift-pipelines --ignore-not-found
COSIGN_BIN=cosign-2.0.1

COSIGN_PASSWORD="" $COSIGN_BIN generate-key-pair k8s://openshift-pipelines/signing-secrets
echo "=============="
#skopeo generate-sigstore-key --output-prefix test-key --passphrase-file passphrase
#base64 test-key.pub > test-key-b64.pub
#base64 test-key.private > test-key-b64.private
#cat passphrase | base64 > test-key-b64.passphrase

oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"slsa/v1","artifacts.taskrun.storage":"oci","transparency.enabled":"true"}}}'

#echo "=============="
#echo "Logging in as non-admin user"
#oc login -u user -p user > /dev/null

NAMESPACE=chainstest
oc new-project $NAMESPACE
sleep 10

REGISTRY=quay.io
REPO=ppitonak/chainstest
TAG=$(date +"%m%d%H%M%S")

oc delete secret quay --ignore-not-found
oc create secret generic quay --from-file=.dockerconfigjson=quay_ppitonak_robot.json --type=kubernetes.io/dockerconfigjson
oc secrets link pipeline quay --for=pull,mount

oc apply -f kaniko.yaml

echo "Image: $REGISTRY/$REPO:$TAG"

tkn task start --param IMAGE=$REGISTRY/$REPO:$TAG --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=quay kaniko-chains --showlog

sleep 5

IMAGE_DIGEST=$(tkn tr describe --last -o json | jq -r  '.status.results[] | select(.name | test("IMAGE_DIGEST")).value' | cut -d":" -f2)
echo "Waiting 90 seconds for images to appear in image registry"
sleep 90
echo "=============="

echo "$COSIGN_BIN verify --key cosign.pub $REGISTRY/$REPO@sha256:$IMAGE_DIGEST"
$COSIGN_BIN verify --key cosign.pub $REGISTRY/$REPO@sha256:$IMAGE_DIGEST
echo "=============="

echo "$COSIGN_BIN verify-attestation --key cosign.pub --type slsaprovenance $REGISTRY/$REPO@sha256:$IMAGE_DIGEST"
$COSIGN_BIN verify-attestation --key cosign.pub --type slsaprovenance $REGISTRY/$REPO@sha256:$IMAGE_DIGEST
echo "=============="

echo "rekor-cli search --format json --sha $IMAGE_DIGEST | jq -r '.UUIDs[0]'"
REKOR_UUID=$(rekor-cli search --format json --sha $IMAGE_DIGEST | jq -r '.UUIDs[0])'
echo "=============="

echo "rekor-cli get --uuid $REKOR_UUID --format json | jq -r .Attestation | jq"
rekor-cli get --uuid $REKOR_UUID --format json | jq -r .Attestation | jq

