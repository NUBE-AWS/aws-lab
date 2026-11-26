# aws-lab — 개인 AWS 학습 트랙 (관리형 위주)

팀 온프레미스 클러스터(nube-gitops)와 팀 복구 사이트(k8s-dr)와는 **별개**인 개인 학습용 저장소입니다.
목표는 VPC 설계 · IAM 최소 권한 · 관리형 서비스 선택 · 비용 관리를 직접 구축하며 익히는 것입니다.

## 원칙

- 개인 계정만 씁니다. 실행 전에 `aws sts get-caller-identity`로 계정을 확인합니다.
- 프로필은 코드에 적지 않습니다. 셸에서 `$env:AWS_PROFILE = "<개인 프로필>"`로 고릅니다.
- 켜 두면 요금이 나가는 자원(EKS 컨트롤 플레인, NAT 게이트웨이, ALB, RDS)은 **쓸 때만 만들고 끝나면 `terraform destroy`** 합니다.
- 비밀 값(키 · 비밀번호)은 Git에 두지 않습니다. 필요하면 Secrets Manager를 씁니다.

## 구조

상태 버킷 하나에 **스택마다 상태 파일을 따로** 둡니다. 스택은 따로 `init` · `plan` · `apply` 하므로, 한 스택의 실수가 다른 스택의 상태를 건드리지 않고, 두 사람이 서로 다른 스택을 동시에 작업할 수 있습니다(같은 스택은 `use_lockfile` 잠금으로 한 사람만).

| 디렉터리 | 상태 위치(key) | 담는 것 | 삭제 주기 |
| :-- | :-- | :-- | :-- |
| `bootstrap/` | 로컬(`bootstrap/terraform.tfstate`, Git 제외) | 상태 버킷 | 삭제하지 않음 |
| `envs/dev/00-foundation/` | `dev/foundation/terraform.tfstate` | IAM 역할 · Route 53 영역 · ACM · ECR · Cognito · KMS · Budgets · GitHub OIDC 역할 | 유지(거의 무료) |
| `envs/dev/10-network/` | `dev/network/terraform.tfstate` | VPC · 서브넷 · NAT · 엔드포인트 | 작업 뒤 삭제 |
| `envs/dev/20-cluster/` | `dev/cluster/terraform.tfstate` | EKS · 노드 그룹 · 애드온 · 액세스 항목 · Pod Identity 역할 | 작업 뒤 삭제 |
| `envs/dev/30-data/` | `dev/data/terraform.tfstate` | RDS · DB 보안 그룹 | 작업 뒤 삭제 |

- 적용은 번호순(00 → 10 → 20 → 30), 삭제는 역순입니다. 스택 사이의 값은 `terraform_remote_state`로 읽습니다.
- 공통 백엔드 값은 `envs/dev/backend.hcl` 하나에 두고(Git 제외 — 버킷 이름에 계정 ID가 들어감), 상태 위치(key)는 스택마다 `versions.tf`에 고정합니다.
- 이 계정에서는 AWS Organizations · IAM Identity Center(조직 인스턴스) · Control Tower를 켜지 않습니다. 켜는 순간 무료 플랜 크레딧이 끝납니다.

비교 축: 같은 앱(NetBox)을 이 트랙(RDS)과 온프레미스(CNPG)에 올려 운영 방식의 차이를 기록합니다. 설계 근거는 nube_it `content/docs/k8s-aws/`입니다.

## 처음 한 번 (0단계)

```powershell
$env:AWS_PROFILE = "<개인 프로필>"
aws sts get-caller-identity          # 작업 계정이 맞는지 확인

# 1) 상태 버킷 — 계정에 한 번만
cd bootstrap
terraform init
terraform apply                      # 출력 state_bucket 값을 기억

# 2) 공통 백엔드 값 — 사람마다 한 번
cd ..\envs\dev
Copy-Item backend.hcl.example backend.hcl
# backend.hcl 의 bucket 을 state_bucket 값으로 바꾼다
```

## 스택 작업

```powershell
cd envs\dev\10-network               # 작업할 스택
terraform init -backend-config=../backend.hcl
terraform plan
terraform apply
```
