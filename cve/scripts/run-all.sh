#!/usr/bin/env bash
set -e
## gitRepo(kind)
scripts/setup-kind.sh
## ingress
kubectl apply -f manifests/ingress/ingress-nginx-1.8.1.yaml
sleep 30
kubectl apply -f manifests/ingress/poc-ingress.yaml
## containerd
images/badimg/build.sh
kubectl apply -f manifests/containerd/poc-badimg.yaml
## ExternalIP
kubectl apply -f manifests/externalip/poc-extip.yaml
echo "▶ 네 가지 PoC 모두 적용 완료 — 각 로그 창을 확인하세요."
