#!/bin/bash

set +x

#oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"slsa/v1","artifacts.taskrun.storage":"tekton","artifacts.oci.storage":""}}}'
oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"in-toto","artifacts.taskrun.storage":"tekton","artifacts.oci.storage":""}}}'
#oc patch tektonconfig config --type=merge -p='{"spec":{"chain":{"artifacts.taskrun.format":"in-toto","artifacts.taskrun.storage":"tekton"}}}'

oc delete secret signing-secrets -n openshift-pipelines --ignore-not-found

COSIGN_PASSWORD=xxx cosign generate-key-pair k8s://openshift-pipelines/signing-secrets
#skopeo generate-sigstore-key --output-prefix test-key --passphrase-file passphrase
#base64 test-key.pub > test-key-b64.pub
#base64 test-key.private > test-key-b64.private
#cat passphrase | base64 > test-key-b64.passphrase

echo "Removing Chains controller pod"
kubectl delete pod -n openshift-pipelines -l app=tekton-chains-controller
echo "Waiting until new Chains controller pod becomes ready"
oc wait --for=condition=Ready pod -l app=tekton-chains-controller -n openshift-pipelines --timeout=5m

echo "Secrets in openshift-pipelines"
oc get secrets -n openshift-pipelines | grep signing

#oc login -u user -p user
#podman login -u user -p $(oc whoami -t) --tls-verify=false --authfile ~/.docker/config.json $REGISTRY

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
export TASKRUN_UID=$(tkn tr describe --last -o  jsonpath='{.metadata.uid}')
echo "tkn tr describe --last -o jsonpath=\"{.metadata.annotations.chains\.tekton\.dev/signature-taskrun-$TASKRUN_UID}\" | base64 -d > sig"
tkn tr describe --last -o jsonpath="{.metadata.annotations.chains\.tekton\.dev/signature-taskrun-$TASKRUN_UID}" | base64 -d > sig
echo "cosign verify-blob-attestation --insecure-ignore-tlog --key cosign.pub --signature sig --type slsaprovenance --check-claims=false /dev/null"
cosign verify-blob-attestation --insecure-ignore-tlog --key cosign.pub --signature sig --type slsaprovenance --check-claims=false /dev/null

