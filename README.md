# aws-lab — 개인 AWS 학습 트랙 (관리형 위주)

팀 온프레미스 클러스터(nube-gitops)와 팀 복구 사이트(k8s-dr)와는 **별개**인 개인 학습용 저장소입니다.
목표는 VPC 설계 · IAM 최소 권한 · 관리형 서비스 선택 · 비용 관리를 직접 구축하며 익히는 것입니다.

## 원칙

- 개인 계정만 씁니다. 실행 전에 `aws sts get-caller-identity`로 계정을 확인합니다.
- 프로필은 코드에 적지 않습니다. 셸에서 `$env:AWS_PROFILE = "<개인 프로필>"`로 고릅니다.
- 켜 두면 요금이 나가는 자원(EKS 컨트롤 플레인, NAT 게이트웨이, ALB, RDS)은 **쓸 때만 만들고 끝나면 `terraform destroy`** 합니다.
- 비밀 값(키 · 비밀번호)은 Git에 두지 않습니다. 필요하면 Secrets Manager를 씁니다.

## 구조

| 디렉터리 | 하는 일 | 상태 저장 |
| :-- | :-- | :-- |
| `bootstrap/` | Terraform 상태를 담을 S3 버킷 하나를 만든다(버전 관리 · 암호화 · 공개 차단). 처음에 한 번만 | 로컬(`bootstrap/terraform.tfstate`, Git 제외) |
| `envs/dev/` | 실제 학습 자원(VPC → EKS → …). 단계마다 여기에 더한다 | S3(`bootstrap`이 만든 버킷, `use_lockfile` 잠금) |

## 단계

| 단계 | 내용 | 켜 두면 드는 비용(대략) |
| :-- | :-- | :-- |
| 0 | 저장소 · 상태 버킷 | S3 몇 센트 |
| 1 | VPC(AZ 2~3, 퍼블릭/프라이빗 서브넷, NAT) | NAT 게이트웨이 시간당 과금 |
| 2 | EKS(관리형 노드 그룹, access entries, 애드온) | 컨트롤 플레인 시간당 약 0.10달러 + 노드 |
| 3 | AWS Load Balancer Controller(ALB) · Route 53 · ACM | ALB 시간당 과금 |
| 4 | RDS PostgreSQL + Secrets Manager + Pod Identity | RDS 인스턴스 |
| 5 | 관측(CloudWatch Container Insights 또는 관리형 Prometheus) | 수집량 |
| 6 | Karpenter · 스팟 · 비용 태그 분석 | — |

비교 축: 같은 앱(예: NetBox)을 이 트랙(RDS)과 온프레미스(CNPG)에 올려 운영 방식의 차이를 기록합니다.

## 처음 한 번 (0단계)

```powershell
$env:AWS_PROFILE = "<개인 프로필>"
aws sts get-caller-identity
cd bootstrap
terraform init
terraform apply
# 예시 파일을 복사하고, 출력된 버킷 이름(state_bucket)을 bucket 에 적는다
# backend.hcl 은 계정 ID가 들어가므로 Git에서 제외한다(.gitignore)
cd ..\envs\dev
Copy-Item backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
```
