#!/bin/bash

set +x

#COSIGN_BIN=cosign-1.13.1
COSIGN_BIN=cosign-2.2.1

oc delete secret signing-secrets -n openshift-pipelines --ignore-not-found
sleep 15

oc create -f signing-secrets.yaml
#COSIGN_PASSWORD=xxx $COSIGN_BIN generate-key-pair k8s://openshift-pipelines/signing-secrets
sleep 15

#skopeo generate-sigstore-key --output-prefix test-key --passphrase-file passphrase
#base64 test-key.pub > test-key-b64.pub
#base64 test-key.private > test-key-b64.private
#cat passphrase | base64 > test-key-b64.passphrase

# TODO oc rollout should be the right approach
#oc delete deployment tekton-chains-controller -n openshift-pipelines
#oc rollout restart deployment/tekton-chains-controller -n openshift-pipelines
#oc delete po -n openshift-pipelines -l app=tekton-chains-controller

