#!/usr/bin/env bash
kubectl delete -f manifests/ingress/poc-ingress.yaml --ignore-not-found
kubectl delete -f manifests/ingress/ingress-nginx-1.8.1.yaml --ignore-not-found
kubectl delete -f manifests/containerd/poc-badimg.yaml --ignore-not-found
kubectl delete -f manifests/externalip/poc-extip.yaml --ignore-not-found
kind delete cluster --name cve-lab || true
echo "🧹 모든 실습 리소스 삭제 완료"
