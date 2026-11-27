# 20-cluster

EKS 클러스터 · 시스템 노드 그룹 · 애드온 · Karpenter(AWS 쪽). **작업 뒤 삭제하는 스택**이다(설계 3.2 · 3.3).

## 켜기 전에

| 확인 | 이유 |
|---|---|
| 10-network `enable_nat_gateway = true` 로 apply | 꺼져 있으면 `nat_precondition` 에서 멈춘다 |
| IAM 그룹 `aws-lab-admins` 에 자기 사용자가 들어 있음 | 비어 있으면 `cluster_admins_precondition` 에서 멈춘다. 들어 있지 않은 사람은 `kubectl` 을 못 쓴다 |
| 허용 주소: GitHub Secret `TF_VAR_CLUSTER_PUBLIC_ACCESS_CIDRS` 와 로컬 `*.auto.tfvars` 가 같은 값 | 둘이 다르면 로컬 apply 와 CI apply 가 서로 허용 목록을 되돌린다(#36) |

로컬 `terraform.auto.tfvars`(Git 제외):

```hcl
cluster_endpoint_public_access_cidrs = ["<공인 IP>/32"]
```

## 클러스터 관리자 추가 · 제거(#50)

1. 콘솔: IAM → 사용자 그룹 → `aws-lab-admins` → 사용자 추가 · 제거
2. 이 스택을 다시 apply(다음에 클러스터를 새로 만들 때는 자동 반영)

멤버를 코드에 적지 않는 이유: 공개 저장소에 사용자 이름 · ARN 을 남기지 않기 위해서다.

## 끄기 전에: PVC 삭제 ⚠️

EBS CSI 드라이버가 PVC 로 만든 EBS 볼륨은 **Terraform 상태 밖**이다. PVC 를 지우지 않고 클러스터를 destroy 하면 볼륨이 남아 요금이 계속 나간다(gp3 GB당 월 약 0.09달러, 서울).

```bash
kubectl get pvc -A                      # 남은 PVC 확인
kubectl delete pvc -n <네임스페이스> <이름>   # StorageClass reclaimPolicy 가 Delete 면 볼륨도 지워진다
kubectl get pv                          # PV 가 사라졌는지 확인
```

destroy 한 뒤 남은 볼륨 확인(`available` = 어디에도 붙지 않음):

```bash
aws ec2 describe-volumes --region ap-northeast-2 --filters Name=status,Values=available \
  --query 'Volumes[].{id:VolumeId,size:Size,created:CreateTime}' --output table
```

남은 볼륨은 야간 점검(#28)의 「연결 안 된 EBS」로도 23시에 알림이 온다.
