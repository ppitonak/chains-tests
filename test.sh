#!/bin/bash

set +x

oc delete secret signing-secrets -n openshift-pipelines --ignore-not-found
COSIGN_BIN=cosign-1.13.1

COSIGN_PASSWORD=xxx $COSIGN_BIN generate-key-pair k8s://openshift-pipelines/signing-secrets
#skopeo generate-sigstore-key --output-prefix test-key --passphrase-file passphrase
#base64 test-key.pub > test-key-b64.pub
#base64 test-key.private > test-key-b64.private
#cat passphrase | base64 > test-key-b64.passphrase

oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"in-toto","artifacts.taskrun.storage":"tekton","artifacts.oci.storage":""}}}'

NAMESPACE=chainstest
oc new-project $NAMESPACE

oc create -f task-output-image.yaml
sleep 5

tkn tr logs -f --last

echo "=============="
export TASKRUN_UID=$(tkn tr describe --last -o  jsonpath='{.metadata.uid}')
tkn tr describe --last -o jsonpath="{.metadata.annotations.chains\.tekton\.dev/signature-taskrun-$TASKRUN_UID}" | base64 -d > sig
echo "$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key k8s://openshift-pipelines/signing-secrets --signature sig --type slsaprovenance --check-claims=false /dev/null"
$COSIGN_BIN verify-blob-attestation --insecure-ignore-tlog --key k8s://openshift-pipelines/signing-secrets --signature sig --type slsaprovenance --check-claims=false /dev/null

