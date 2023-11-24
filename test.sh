#!/bin/bash

set +x

#COSIGN_BIN=cosign-1.13.1
COSIGN_BIN=cosign-2.2.1
NAMESPACE=chainstest

oc delete project $NAMESPACE --ignore-not-found
sleep 15

oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"in-toto","artifacts.taskrun.storage":"tekton","artifacts.oci.storage":""}}}'

oc new-project $NAMESPACE
sleep 10

oc create -f task-output-image.yaml
tkn tr logs -f --last

echo "=============="
export TASKRUN_UID=$(tkn tr describe --last -o jsonpath='{.metadata.uid}')
tkn tr describe --last -o jsonpath="{.metadata.annotations.chains\.tekton\.dev/signature-taskrun-$TASKRUN_UID}" | base64 -d > sig

# cosign <2.0.0
#echo "$COSIGN_BIN verify-blob --key k8s://openshift-pipelines/signing-secrets --signature sig sig"
#$COSIGN_BIN verify-blob --key k8s://openshift-pipelines/signing-secrets --signature sig sig
#echo "$COSIGN_BIN verify-blob --key cosign.pub --signature sig sig"
#$COSIGN_BIN verify-blob --key cosign.pub --signature sig sig

# cosign >2.0.0
echo "$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key k8s://openshift-pipelines/signing-secrets --signature sig --type slsaprovenance --check-claims=false /dev/null"
$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key k8s://openshift-pipelines/signing-secrets --signature sig --type slsaprovenance --check-claims=false /dev/null

echo "$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key cosign.pub --signature sig --type slsaprovenance --check-claims=false /dev/null"
$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key cosign.pub --signature sig --type slsaprovenance --check-claims=false /dev/null
