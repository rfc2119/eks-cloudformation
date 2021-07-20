#!/bin/bash

set -e

function print_help {
  echo "usage: $0 [options] <key_pair_name>"
  echo "runs the eks.yml cloudformation template file and configures"
  echo "kubectl to talk to the control plane"
  echo "-h, --help  prints this message"
  echo "--num-worker-nodes  how many worker nodes to be deployed across two AZs"
  echo "--stack-name  cloudformation stack name"
  echo "--worker-nodes-instance-type  aws instancy type of the worker nodes"
  echo "--key-pair-name name of the private key pair on your aws account"
  # echo "--update-kubectl-context updates context for installed kubectl"
}

# EDIT THIS:
#------------------------------------------------------------------------------#
NUM_WORKER_NODES=3
WORKER_NODES_INSTANCE_TYPE=t2.micro
STACK_NAME=test-cluster
KEY_PAIR_NAME=
#------------------------------------------------------------------------------#

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            print_help
            exit 1
            ;;
        --num-worker-nodes)
            NUM_WORKER_NODES="$2"
            shift
            shift
            ;;
        --worker-nodes-instance-type)
            WORKER_NODES_INSTANCE_TYPE="$2"
            shift
            shift
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift
            shift
            ;;
        --key-pair-name)
            KEY_PAIR_NAME="$2"
            shift
            shift
            ;;
        # --update-kubectl-context)
        #     UPDATE_CONTEXT=true
        #     shift
        #     ;;
        *)    # unknown option
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Output colours
COL='\033[1;34m'
NOC='\033[0m'

echo -e  "$COL> Deploying CloudFormation stack (may take up to 15 minutes)...$NOC"
aws cloudformation deploy \
  "$@" \
  --template-file eks.yml \
  --capabilities CAPABILITY_IAM \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
      KeyPairName="$KEY_PAIR_NAME" \
      NumWorkerNodes="$NUM_WORKER_NODES" \
      WorkerNodesInstanceType="$WORKER_NODES_INSTANCE_TYPE"

# by default, the resulting configuration file is created
# at the default kubeconfig path (.kube/config) in your home directory
echo -e "\n$COL> Updating kubeconfig file...$NOC"
aws eks update-kubeconfig "$@" --name "$STACK_NAME" 

echo -e "\n$COL> Configuring worker nodes (to join the cluster)...$NOC"
# Get worker nodes role ARN from CloudFormation stack output
arn=$(aws cloudformation describe-stacks \
  "$@" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='WorkerNodesRoleArn'].OutputValue" \
  --output text)
# Enable worker nodes to join the cluster:
# https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html#eks-create-cluster
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: $arn
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF

echo -e "\n$COL> Almost done! Cluster will be ready when all nodes have a 'Ready' status."
echo -e "> Check it with: kubectl get nodes --watch$NOC"
