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
| `bootstrap/` | `bootstrap/terraform.tfstate` | 상태 버킷 | 삭제하지 않음 |
| `envs/dev/00-foundation/` | `dev/foundation/terraform.tfstate` | Route 53 영역 · ACM · ECR · Cognito · KMS · Budgets · GitHub OIDC 역할 | 유지(거의 무료) |
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

## CI로 적용되지 않는 변경 (#40)

CI 역할에는 명시적 거부가 붙어 있습니다(`00-foundation/ci-deny.tf`). 아래를 바꾸는 PR은 병합 뒤 자동 apply가 **`AccessDenied`로 실패**하므로, 병합한 뒤 **사람이 로컬에서 `00-foundation`을 apply**합니다.

| 바꾸는 것 | 파일 |
|---|---|
| plan · apply 역할(신뢰 정책 · 인라인 정책 · 정책 연결 · 삭제), OIDC 공급자 | `github-oidc.tf` |
| 거부 문장 자체 | `ci-deny.tf` |
| CloudTrail 추적 설정 · 중지 · 삭제 | `cloudtrail.tf` |
| GuardDuty 탐지기 · 기능 켜고 끄기 | `guardduty.tf` |

- PR 본문에 「사람 apply 필요」를 적어 두고, 병합한 사람이 바로 로컬에서 apply합니다.
- 자동 apply가 실패해도 그 스택의 나머지 변경은 사람이 apply할 때 함께 적용됩니다.
- PR plan(plan 역할)은 SSM 파라미터 값 · Secrets Manager 값을 읽지 못합니다. 비밀 값을 읽는 Terraform 자원(`aws_secretsmanager_secret_version` 데이터 등)을 더하면 PR plan이 실패합니다.

## 경보 메일 구독 (각자 한 번)

`00-foundation`이 만든 SNS 주제 `aws-lab-alerts`로 CloudWatch 경보 · Budgets 알림이 옵니다. 메일 주소는 공개 저장소에 둘 수 없어 구독은 Terraform 밖에서 각자 만듭니다(#26).

1. 콘솔 → SNS → 주제 → `aws-lab-alerts` → **구독 생성**
2. 프로토콜 `이메일`, 엔드포인트에 본인 메일 → 생성
3. 받은 메일의 **Confirm subscription** 링크를 누름(누르기 전에는 「확인 대기 중」이라 메일이 오지 않음)

## 야간 점검 이슈가 오면

매일 23시(KST) `nightly-check` 워크플로가 서울 리전에 과금 자원(EKS · NAT · 실행 중 EC2 · RDS · 로드 밸런서 · 연결 안 된 EBS · 탄력적 IP)이 남았는지 보고, 남아 있으면 `[야간 점검]` 이슈를 만들거나 열린 이슈에 댓글을 답니다(#28). 자동으로 지우지는 않습니다.

- 지우는 것을 잊었다면: 설계 8.3 순서(클러스터 자원 정리 → `25` → `30` → `20` → `10`)로 정리
- 일부러 켜 둔 것이면: 이유를 댓글로 남기고 이슈를 닫음
- 손으로 돌려 보기: Actions → `nightly-check` → **Run workflow**

## ECR 캐시 저장소 정리 (#27)

외부 이미지는 ECR pull-through cache로 받습니다. 캐시가 이미지를 처음 받을 때 만드는 저장소(`quay/…` · `ecr-public/…` · `k8s/…` · `ghcr/…`)는 **Terraform 상태 밖**이라 `00-foundation`을 지워도 남습니다. 저장 요금(GB당 월 0.10달러)이 들므로, 정리할 때는 사람이 지웁니다.

```powershell
# 캐시가 만든 저장소 목록
aws ecr describe-repositories --query "repositories[?starts_with(repositoryName, 'quay/') || starts_with(repositoryName, 'ecr-public/') || starts_with(repositoryName, 'k8s/') || starts_with(repositoryName, 'ghcr/')].repositoryName" --output text
# 하나 지우기(이미지까지)
aws ecr delete-repository --repository-name <이름> --force
```

평소에는 지울 필요가 없습니다. 수명 주기(최근 5개 유지)가 저장소마다 오래된 이미지를 지웁니다.
