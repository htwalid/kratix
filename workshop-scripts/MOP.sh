# make sure there are no clusters running
kind delete clusters --all

sudo kind create cluster \
    --name platform \
    --image kindest/node:v1.32.3 \
    --config config/samples/kind-platform-config.yaml

sudo kind create cluster \
    --name worker \
    --image kindest/node:v1.32.3 \
    --config config/samples/kind-worker-config.yaml

export PLATFORM="kind-platform"
export WORKER="kind-worker"

sudo kubectl --context $PLATFORM cluster-info
sudo kubectl --context $WORKER cluster-info

alias skp="sudo kubectl --context $PLATFORM"
alias skw="sudo kubectl --context $WORKER"

skp apply --filename https://github.com/cert-manager/cert-manager/releases/download/v1.15.0/cert-manager.yaml
skp get pods --namespace cert-manager

# from the root of the Kratix repository
skp apply --filename config/samples/minio-install.yaml

skp get deployments --namespace kratix-platform-system

skp get jobs

# configure the mc CLI to use the MinIO instance
mc alias set kind http://localhost:31337 minioadmin minioadmin

# list the buckets
mc ls kind/


skp get services minio --namespace kratix-platform-system

skw apply --filename https://github.com/fluxcd/flux2/releases/download/v2.4.0/install.yaml
sudo docker inspect platform-control-plane | grep '"IPAddress": "172' | awk -F '"' '{print $4}'
skp get services minio --namespace kratix-platform-system

skw apply -f workshop-scripts/flux-source-bucket.yaml

skw get buckets.source.toolkit.fluxcd.io --namespace flux-system
skw apply -f workshop-scripts/flux-kustomization.yaml

skw get deployments --namespace flux-system --watch

#### OPERATING KRATIX ######
############################

skp apply --filename https://github.com/syntasso/kratix/releases/latest/download/kratix.yaml
skp get crds | grep kratix
skp apply --filename workshop-scripts/state-store.yaml
skp apply --filename workshop-scripts/destination.yaml

skw get namespace kratix-worker-system
#### Provide Jenkins-as-a-Service ####

skp apply -f workshop-scripts/jenkins/promise.yaml
skw get deployments --watch

skp get promises.platform.kratix.io
skp apply -f workshop-scripts/jenkins/request.yaml

skp get pods

skw get pods --watch

### Jenkins Password where !! ####
skw get secrets --selector app=jenkins-operator -o go-template='{{range .items}}{{"username: "}}{{.data.user|base64decode}}{{"\n"}}{{"password: "}}{{.data.password|base64decode}}{{"\n"}}{{end}}'

skp delete promise jenkins ## cleanup jenkins promise
skw get pods --watch

#### Provide Crossplane-as-a-Service ####

skp apply -f workshop-scripts/crossplane/promise.yaml
skw get deployments -n crossplane-system --watch


# WRITING PROMISE #
###################

## Design an API for your service ##

### create a directory called app-promise and run the init promise command inside it ###

mkdir app-promise
kratix init promise app --group workshop.kratix.io --version v1 --kind App

### run the update api command to include the API fields you defined (container image and service port) ###

kratix update api --property image:string --property service.port:integer

## Define the dependencies ##

mkdir -p dependencies
curl -o dependencies/dependencies.yaml --silent https://raw.githubusercontent.com/syntasso/kratix-docs/main/docs/workshop/part-ii/_partials/nginx-patched.yaml

### Declare Promise Dependencies in Promise Workflow ###

kratix update dependencies ./dependencies/ --image kratix-workshop/app-promise-pipeline:v0.1.0
tree

.
├── dependencies
│   └── dependencies.yaml
├── example-resource.yaml
├── promise.yaml
├── README.md
└── workflows
    └── promise
        └── configure
            └── dependencies
                └── configure-deps
                    ├── Dockerfile
                    ├── resources
                    │   └── dependencies.yaml
                    └── scripts
                        └── pipeline.sh

### Inspect the Promise Workflow ###

cat promise.yaml | yq '.spec.workflows'

### build the app-promise-pipeline image used in the configure-deps workflow and make it available in the container registry. ###

sudo docker build --tag kratix-workshop/app-promise-pipeline:v0.1.0 workflows/promise/configure/dependencies/configure-deps
sudo kind load docker-image kratix-workshop/app-promise-pipeline:v0.1.0 --name platform

## Define the Workflow ##

### bootstrap the skeleton of your Workflow ###

kratix add container resource/configure/mypipeline --image kratix-workshop/app-pipeline-image:v1.0.0

### rename the pipeline.sh to resource-configure to better reflect its purpose ###

mv workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image/scripts/{pipeline.sh,resource-configure}

### build the Resource Configure Workflow's pipeline image and make it available in the container registry ###

sudo docker build --tag kratix-workshop/app-pipeline-image:v1.0.0 workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image
sudo kind load docker-image kratix-workshop/app-pipeline-image:v1.0.0 --name platform


# Install the Promise #

### install the Promise in the platform ###

skp apply -f promise.yaml

### check the NGINX Ingress Controller installed in the worker cluster Destination correctly ###

skw get deployments -n ingress-nginx --watch

# Using the App Promise #

### check the available promises ###

skp get promises

### deploy your app by providing an image and a service.port ###

touch example-resource.yaml
skp apply -f example-resource.yaml 

### verify the workflow ###

skp get pods

# Test driving your workflows #
###############################

## Prepare your environment ##

mkdir -p test/{input,output,metadata}
touch test/input/object.yaml

mkdir -p scripts

cat << 'EOF' > scripts/build-pipeline
#!/usr/bin/env bash

set -eu -o pipefail

testdir=$(cd "$(dirname "$0")"/../test; pwd)

docker build --tag kratix-workshop/app-pipeline-image:v1.0.0 workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image
kind load docker-image kratix-workshop/app-pipeline-image:v1.0.0 --name platform
EOF

cat <<'EOF' > scripts/test-pipeline
#!/usr/bin/env bash

scriptsdir=$(cd "$(dirname "$0")"; pwd)
testdir=$(cd "$(dirname "$0")"/../test; pwd)
inputDir="$testdir/input"
outputDir="$testdir/output"
metadataDir="$testdir/metadata"

$scriptsdir/build-pipeline
rm -rf $outputDir/*

command=${1:-"resource-configure"}

docker run \
    --rm \
    --volume ~/.kube:/root/.kube \
    --network=host \
    --volume ${outputDir}:/kratix/output \
    --volume ${inputDir}:/kratix/input \
    --volume ${metadataDir}:/kratix/metadata \
    --env MINIO_USER=minioadmin \
    --env MINIO_PASSWORD=minioadmin \
    --env MINIO_ENDPOINT=localhost:31337 \
    kratix-workshop/app-pipeline-image:v1.0.0 sh -c "$command"
EOF

chmod +x scripts/*

tree

.
├── dependencies
│   └── dependencies.yaml
├── example-resource.yaml
├── promise.yaml
├── README.md
├── scripts
│   ├── build-pipeline
│   └── test-pipeline
├── test
│   ├── input
│   │   └── object.yaml
│   ├── metadata
│   └── output
└── workflows
    ├── promise
    │   └── configure
    │       └── dependencies
    │           └── configure-deps
    │               ├── Dockerfile
    │               ├── resources
    │               │   └── dependencies.yaml
    │               └── scripts
    │                   └── pipeline.sh
    └── resource
        └── configure
            └── mypipeline
                └── kratix-workshop-app-pipeline-image
                    ├── Dockerfile
                    ├── resources
                    └── scripts
                        └── resource-configure

19 directories, 12 files

## Run the tests ##

sudo ./scripts/test-pipeline resource-configure

# Accessing Secrets and storing state #
#######################################

## Secret ##

### create a new Secret in your Platform cluster ##

skp apply -f app-promise-minio-creds.yaml

### add the create-bucket script to your Resource Worfklow Pipeline image. Create a create-bucket script in the workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image/scripts/ directory ##

touch ./workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image/scripts/create-bucket
touch ./workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image/resources/terraform.tf

### Update your Dockerfile to include curl and the Terraform CLI ##

### create the create-bucket script ##

### ensure kubectl is pointing to the platform cluster before running the test script ##

kubectl config get current-context
kubectl config set-context $PLATFORM

### run the test script ##

sudo ./scripts/test-pipeline create-bucket

## State ##

### Update both promise and create-bucket scripts to store the state of the bucket creation in the MinIO instance ###

### delete the bucket and run the test script again ###

mc rb kind/my-app.default
mc ls kind/

### run the build script ###

sudo ./scripts/build-pipeline

### run the test script again ###
sudo  ./scripts/test-pipeline create-bucket

### check the state of the bucket creation in the MinIO instance ###

skw get configmap my-app-state --output=jsonpath={.data.tfstate}

### Awesome! You pipeline stage is now idempotent, so go ahead and apply the promise with the new stage into your Platform ###

skp apply --filename promise.yaml

### check the state of the bucket creation in the MinIO instance ###    

mc ls kind/

### Trigger a manual reconciliation ###

skp label apps.workshop.kratix.io todo kratix.io/manual-reconciliation=true

### Check the ConfigMap for the todo app ###

skw get configmap my-app-state --output=jsonpath={.data.tfstate}


### check the logs and verify how it reused the state from the ConfigMap

pod_name=$(skp get pods --sort-by=.metadata.creationTimestamp -o jsonpath="{.items[-1:].metadata.name}")
skp logs $pod_name --container create-bucket

# Surfacing information via Status #
####################################

## Conveying information back to the application developers ##

## Status##

## Add the following lines to the end of your resource-configure script ##

# Set the resource status
cat <<EOF > /kratix/metadata/status.yaml
message: "${name}.local.gd:31338"
EOF

sudo ./scripts/test-pipeline resource-configure

...
└── test
    ├── input
    │   └── object.yaml
    ├── metadata
    │   └── status.yaml
    └── output
        ├── deployment.yaml
        ├── ingress.yaml
        └── service.yaml

## force reconcile the promise ##
skp label apps.workshop.kratix.io todo kratix.io/manual-reconciliation=true

## check the status of the app ##

skp describe apps.workshop.kratix.io todo
skp get apps.workshop.kratix.io

## ensure that the information in Status is not overwritten if it already exists. ##

## Update your resource-configure script so it sets a new field createdAt ##

createdAt="$(date)"

# Set the resource status
cat <<EOF > /kratix/metadata/status.yaml
createdAt: ${createdAt}
message: "${name}.local.gd:31338"
EOF

## run test script ## 

sudo ./scripts/test-pipeline resource-configure


# Making a Compound Promise #
#############################

## Writing a Compound Promise ##

### Updating the API ###

kratix update api --property dbDriver:string
cat promise.yaml | yq '.spec.api'

### Configuring a Compound Promise ###

### Defining Promises as Required Promises ###

### Run & install the PostgreSQL Promise ###

skp apply -f pgsql-promise-release.yaml
skp get promises

### Updating the Pipelines ###

curl -o workflows/resource/configure/mypipeline/kratix-workshop-app-pipeline-image/scripts/database-configure --silent https://gist.githubusercontent.com/syntassodev/7cfae7b53bc54615cf351760a8377ba2/raw/34b37a7af95bd24293cc7ea3a3456cd4d58361a0/gistfile1.txt

sudo ./scripts/test-pipeline "resource-configure && database-configure"

### Open the test/input/object.yaml and update its spec to include the dbDriver ###

sudo ./scripts/test-pipeline "resource-configure && database-configure"

### warning !!! ensure you have registered the platform cluster as a destination and labelled it appropriately. ###

skp get destinations --show-labels

### If you don't see the platform cluster, or it's not labelled as platform, you can follow these steps to register it as a destination. ###

sudo ../../scripts/register-destination --name platform-cluster --context $PLATFORM --state-store default --strict-match-labels --with-label environment=platform

## Requesting a Database with your App ##

###  Open the example-resource.yaml and update it to include the dbDriver property set to postgresql ###

### Apply the updated App-as-a-Service Resource Request ###

skp apply -f example-resource.yaml

skp get pods --selector kratix.io/promise-name=postgresql

## Crossplane as a Service ##

skw create secret generic aws-creds -n crossplane-system --from-file=creds=./aws-credentials.txt
skw get secrets -A
k apply -f provider-config.yaml 
skw apply -f provider-config.yaml 
skw -n crossplane-system get deployments
skw get deployments
skw get pods -A
skw get crossplane
skw apply -f provider-aws.yaml
skw get crossplane
skw get compositeresourcedefinitions
skw get compositeresourcedefinitions -A


