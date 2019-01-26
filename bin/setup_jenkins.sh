#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3

echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
# TBD
dc=$(oc get dc jenkins --ignore-not-found=true -n ${GUID}-jenkins | grep -v NAME | awk '{print $1}')
if [[ -z ${dc} ]];then
  echo "Deployment jenkins not found, creating..."
  oc new-app --name=jenkins --template=jenkins-persistent --param ENABLE_OAUTH=true \
        --param VOLUME_CAPACITY=4Gi \
        --param DISABLE_ADMINISTRATIVE_MONITORS=true \
        -n ${GUID}-jenkins
fi
while (true); do 
  echo "Waiting for jenkins dc to become available..."
  dc=$(oc get dc jenkins -n ${GUID}-jenkins | grep -v NAME | awk '{print $1}')
  if [[ ! -z ${dc} ]]; then
    echo -e "\tsetting resource limits for jenkins dc"
    oc set resources dc jenkins --limits=memory=3Gi,cpu=2 --requests=memory=2Gi,cpu=1 -n ${GUID}-jenkins
    break
  fi
  sleep 5
done

# Create custom agent container image with skopeo
# TBD
create_build=true
builds=$(oc get builds -n ${GUID}-jenkins | grep -v NAME | awk '{print $1}')
for build in ${builds[@]}; do
  if [[ ${build} == jenkins-agent-appdev* ]]; then
    create_build=false
    echo "Build jenkins-agent-appdev already exists, skipping..."
  fi
done
if [[ ${create_build} == "true" ]]; then
  echo "Creating build jenkins-agent-appdev..."
  oc new-build  -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
        USER root\nRUN yum -y install skopeo && yum clean all\n
        USER 1001' --name=jenkins-agent-appdev -n ${GUID}-jenkins
fi

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
# TBD
create_build=true
for build in ${builds[@]}; do
  if [[ ${build} == tasks-piepline* ]]; then
    create_build=false
    echo "Deployment tasks already exists, skipping..."
  fi
done
if [[ ${create_build} == "true" ]]; then
  echo "Creating build-conifg tasks-pipeline..."
echo "apiVersion: v1
items:
- kind: "BuildConfig"
  apiVersion: "v1"
  metadata:
    name: "tasks-pipeline"
  spec:
    source:
      type: "Git"
      git:
        uri: ${REPO}
      contextDir: openshift-tasks
    strategy:
      type: "JenkinsPipeline"
      jenkinsPipelineStrategy:
        jenkinsfilePath: Jenkinsfile_skopeo_pod
        env:
        - name: GUID
          value: ${GUID}
        - name: REPO
          value: ${REPO}
        - name: CLUSTER
          value: ${CLUSTER}

kind: List
metadata: []" | oc create -f - -n 29d1-jenkins

#  oc new-app --template=eap71-basic-s2i \
#    --param APPLICATION_NAME=tasks-pipeline \
#    --param SOURCE_REPOSITORY_URL=${REPO} \
#    --param SOURCE_REPOSITORY_REF=master \
#    --param CONTEXT_DIR=openshift-tasks \
#    --param MAVEN_MIRROR_URL=http://nexus3.gpte-hw-cicd.svc.cluster.local:8081/repository/all-maven-public \
#    -n ${GUID}-jenkins
fi

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done
