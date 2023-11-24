#!/bin/bash

set +x

NAMESPACE=chainstest
COSIGN_BIN=cosign-2.2.1

oc delete project $NAMESPACE --ignore-not-found
sleep 15

oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"slsa/v1","artifacts.taskrun.storage":"oci","artifacts.oci.storage":"oci","transparency.enabled":"true"}}}'

#echo "=============="
#echo "Logging in as non-admin user"
#oc login -u user -p user > /dev/null

oc new-project $NAMESPACE
sleep 10

REGISTRY=quay.io
REPO=ppitonak/chainstest
TAG=$(date +"%m%d%H%M%S")

oc create secret generic quay --from-file=.dockerconfigjson=quay_ppitonak_robot.json --from-file=config.json=quay_ppitonak_robot.json --type=kubernetes.io/dockerconfigjson
oc secrets link pipeline quay --for=pull,mount

oc apply -f kaniko.yaml

echo "Image: $REGISTRY/$REPO:$TAG"

tkn task start --param IMAGE=$REGISTRY/$REPO:$TAG --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=quay kaniko-chains --showlog

IMAGE_DIGEST=$(tkn tr describe --last -o json | jq -r  '.status.results[] | select(.name | test("IMAGE_DIGEST")).value' | cut -d":" -f2)
echo "Waiting 30 seconds for images to appear in image registry"
sleep 30
echo "=============="

echo "$COSIGN_BIN verify --key cosign.pub $REGISTRY/$REPO@sha256:$IMAGE_DIGEST"
$COSIGN_BIN verify --key cosign.pub $REGISTRY/$REPO@sha256:$IMAGE_DIGEST
echo "=============="

echo "$COSIGN_BIN verify-attestation --key cosign.pub --type slsaprovenance $REGISTRY/$REPO@sha256:$IMAGE_DIGEST"
$COSIGN_BIN verify-attestation --key cosign.pub --type slsaprovenance $REGISTRY/$REPO@sha256:$IMAGE_DIGEST
echo "=============="

echo "rekor-cli search --format json --sha $IMAGE_DIGEST"
OUT=$(rekor-cli search --format json --sha $IMAGE_DIGEST)
echo $OUT
REKOR_UUID=$(echo $OUT | jq -r '.UUIDs[0]')
echo "=============="

echo "rekor-cli get --uuid $REKOR_UUID --format json | jq -r .Attestation | jq"
rekor-cli get --uuid $REKOR_UUID --format json | jq -r .Attestation | jq

