#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

kind create cluster --config=./config/config.yaml --name kind
docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"

# https://github.com/kubernetes/ingress-nginx
echo "deploy nginx ingress for kind"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# https://metallb.universe.tf/
# https://github.com/metallb/metallb

# v0.12.1
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# v0.13.4
echo "deploy metallb LoadBalancer"
kubectl apply -f  https://raw.githubusercontent.com/metallb/metallb/v0.13.4/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
# kubectl get pods -n metallb-system --watch

echo "wait for metallb pods"
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout=90s

# get kind network IP
# iface="$(ip route | grep $(docker network inspect --format '{{json (index .IPAM.Config 0).Subnet}}' "kind" | tr -d '"') | cut -d ' ' -f 3)"
# docker network inspect kind -f '{{json (index .IPAM.Config 0).Subnet}}'
# docker network inspect kind | jq -r '.[].IPAM.Config[0].Subnet'
ip_subclass=$(docker network inspect kind -f '{{index .IPAM.Config 0 "Subnet"}}' | awk -F. '{printf "%d.%d\n", $1, $2}')

# v0.12.1
# cat <<EOF | kubectl apply -f=-
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   namespace: metallb-system
#   name: config
# data:
#   config: |
#     address-pools:
#     - name: default
#       protocol: layer2
#       addresses:
#       - ${ip_subclass}.255.200-${ip_subclass}.255.250
# EOF

# v0.13.4
# https://thr3a.hatenablog.com/entry/20220718/1658127951
# https://github.com/metallb/metallb/issues/1473
cat <<EOF | kubectl apply -f=-
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - ${ip_subclass}.255.200-${ip_subclass}.255.250
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF

kubectl apply -f ./k8s/helloweb-deployment.yaml

# https://stackoverflow.com/questions/70108499/kubectl-wait-for-service-on-aws-eks-to-expose-elastic-load-balancer-elb-addres/70108500#70108500
echo "wait for helloweb service to get External-IP from LoadBalancer"
until kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&


# kind delete cluster

cd $LAUNCH_DIR