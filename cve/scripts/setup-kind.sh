#!/usr/bin/env bash
kind create cluster --name cve-lab \
  --config manifests/gitrepo/kind-v1.30.2.yaml \
  --image kindest/node:v1.30.2
kubectl apply -f manifests/gitrepo/poc-gitrepo.yaml
echo "▶ gitRepo PoC 배포 완료"
