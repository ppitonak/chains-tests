#!/bin/bash

set +x

cat <<EOF | oc apply -f -
apiVersion: operator.tekton.dev/v1alpha1
kind: TektonChain
metadata:
  name: chain
spec:
  targetNamespace: openshift-pipelines
EOF

oc delete secret signing-secrets -n openshift-pipelines --ignore-not-found

COSIGN_PASSWORD=xxx cosign generate-key-pair k8s://openshift-pipelines/signing-secrets

#TODO update Chains CR, not configmap

oc patch configmap chains-config -n openshift-pipelines -p='{"data":{"artifacts.taskrun.format": "in-toto", "artifacts.taskrun.storage": "oci","transparency.enabled": "true"}}'

oc login -u user -p user
podman login -u user -p $(oc whoami -t) --tls-verify=false --authfile ~/.docker/config.json $REGISTRY

NAMESPACE=chainstest-$RANDOM
oc new-project $NAMESPACE

REGISTRY=quay.io
REPO=ppitonak/chainstest:$(date +"%m%d%H%M%S")

oc delete secret quay --ignore-not-found
oc create secret generic quay --from-file=.dockerconfigjson=quay_ppitonak_robot.json --type=kubernetes.io/dockerconfigjson
oc secrets link pipeline quay --for=pull,mount

oc apply -f kaniko.yaml

echo "Image: $REGISTRY/$REPO"

tkn task start --param IMAGE=$REGISTRY/$REPO --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=quay kaniko-chains --showlog

sleep 5

echo "=============="
echo "cosign verify --key cosign.pub $REGISTRY/$REPO"
cosign verify --key cosign.pub $REGISTRY/$REPO

echo "=============="
echo "cosign verify-attestation --key cosign.pub $REGISTRY/$REPO"
cosign verify-attestation --key cosign.pub --type slsaprovenance $REGISTRY/$REPO

IMAGE_DIGEST=$(tkn tr describe --last -o jsonpath="{.status.taskResults[?(@.name=='IMAGE_DIGEST')].value}" | cut -d':' -f2)
UUID=$(rekor-cli search --sha $IMAGE_DIGEST)

echo "=============="
echo "rekor-cli get --uuid $UUID --format json | jq .Attestation"
rekor-cli get --uuid $UUID --format json | jq .Attestation

