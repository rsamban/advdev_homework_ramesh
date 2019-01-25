#!/bin/bash
# Create Homework Projects with GUID prefix.
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 GUID"
    exit 1
fi

GUID=$1

nexus_project=$(oc projects -q | grep ${GUID}-nexus)
if [[ -z ${nexus_project} ]]; then
  echo "Creating Homework Projects for GUID=${GUID} "
  oc new-project ${GUID}-nexus --display-name="${GUID} AdvDev Homework Nexus"
else 
  echo "project ${GUID}-nexus already exists. Skipping creation..."
fi

nexus_dc=$(oc get dc nexus3 --ignore-not-found=true -n ${GUID}-nexus | grep -v NAME | awk '{print $1}')
if [[ -z ${nexus_dc} ]]; then
  echo "Deployment nexus3 not found, creating..."
  oc new-app -n nexus3 sonatype/nexus3:latest -n ${GUID}-nexus
else
  echo "Deployment nexus3 already exists, skipping creation..."
fi
nexus_route=$(oc get route nexus3 -n ${GUID}-nexus | grep nexus3 | awk '{print $1}')
if [[ -z ${nexus_route} ]]; then
  echo "Creating route for nexus"
  oc expose svc nexus3 -n ${GUID}-nexus
fi

oc rollout pause dc nexus3 -n ${GUID}-nexus
oc patch dc nexus3 --patch='{ "spec": { "strategy": { "type": "Recreate" }}}' -n ${GUID}-nexus
oc set resources dc nexus3 --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m -n ${GUID}-nexus
nexus_pvc=$(oc get pvc -n ${GUID}-nexus | grep nexus-pvc)
if [[ -z ${nexus_pvc} ]]; then
  echo "Creating nexus-pvc persistant volume..."
echo "apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nexus-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi" | oc create -f -
else
  echo "Persistant volume nexus-pvc already exists. Skipping creation..."
fi

oc set volume dc/nexus3 --add --overwrite --name=nexus3-volume-1 --mount-path=/nexus-data/ --type persistentVolumeClaim --claim-name=nexus-pvc -n ${GUID}-nexus
oc set probe dc/nexus3 --liveness --failure-threshold 3 --initial-delay-seconds 60 -- echo ok -n ${GUID}-nexus
oc set probe dc/nexus3 --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8081/ -n ${GUID}-nexus

oc rollout resume dc nexus3 -n ${GUID}-nexus

# Make sure that NExus is fully up and running before proceeding!
while : ; do
  echo "Checking if Nexus is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc nexus3 -n ${GUID}-nexus -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Nexus is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

curl -o setup_nexus3.sh -s https://raw.githubusercontent.com/redhat-gpte-devopsautomation/ocp_advanced_development_resources/master/nexus/setup_nexus3.sh
chmod +x setup_nexus3.sh
./setup_nexus3.sh admin admin123 http://$(oc get route nexus3 --template='{{ .spec.host }}')
rm setup_nexus3.sh

nexus_registry_route=$(oc get route nexus-registry -n ${GUID}-nexus | grep nexus-registry | awk '{print $1}')
if [[ -z ${nexus_registry_route} ]]; then
  echo "Creating route for nexus-registry..."
  oc expose dc nexus3 --port=5000 --name=nexus-registry -n ${GUID}-nexus
  oc create route edge nexus-registry --service=nexus-registry --port=5000
fi
