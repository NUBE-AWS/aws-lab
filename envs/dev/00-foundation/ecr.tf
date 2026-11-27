# ECR pull-through cache(설계 6.4, #27) — 외부 이미지를 이 계정 ECR 이 대신 받아 보관한다. 온프레미스 zot 캐시에 대응.
#
# - 이미지를 우리가 올리는 것이 아니다. 노드가 캐시 주소
#   <계정>.dkr.ecr.ap-northeast-2.amazonaws.com/<접두어>/<원본 경로> 로 요청하면, ECR 이 원본에서 받아 와 보관한다.
# - 원본은 넷: quay.io · public.ecr.aws · registry.k8s.io(인증 없음)와 ghcr.io(인증 필요).
#   Docker Hub 규칙은 두지 않는다 — Docker 공식 이미지는 ecr-public 규칙으로
#   public.ecr.aws/docker/library/<이미지> 를 받는다(#27 결정 1, 토큰 · 비밀 하나 절약).
# - 접두어 목록은 20-cluster 노드 역할의 권한 범위(repository/<접두어>/*)와 같아야 한다.
#   노드 역할에 없는 접두어의 원본은 처음 받을 때 거부된다 → 출력 cache_prefixes 와 대조.
# - 캐시가 처음 받을 때 자동으로 만드는 저장소는 Terraform 상태 밖이다. 이 스택을 지워도 남는다(README 정리 절차).

variable "cache_prefixes" {
  description = "ECR repository prefix per upstream registry that needs no credentials. 20-cluster node role permissions and chart values must use the same prefixes."
  type        = map(string)
  default = {
    "quay"       = "quay.io"
    "ecr-public" = "public.ecr.aws"
    "k8s"        = "registry.k8s.io"
  }
}

# ghcr.io 규칙은 비밀에 값이 들어간 뒤에 켠다(#27 PR ②).
# 값이 없는 비밀을 가리키는 규칙의 생성이 거부되는지 문서로 확인하지 못해 분리했다.
# 켤 때는 명령줄 -var 가 아니라 이 기본값을 바꾸는 PR 로 한다 — -var 로만 주면 다음 자동 apply 에서 규칙이 지워진다.
variable "enable_ghcr_rule" {
  description = "Create the pull-through cache rule for ghcr.io. Turn on only after a person has put the credentials into the secret."
  type        = bool
  default     = false
}

resource "aws_ecr_pull_through_cache_rule" "public" {
  for_each = var.cache_prefixes

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value
}

# ghcr.io 자격 증명. Terraform 은 빈 비밀(이름 · 설명)만 만들고 값은 사람이 넣는다(설계 10장, 손두영).
# - 값: {"username": "<GitHub 사용자>", "accessToken": "<클래식 PAT, read:packages 만>"} — 문서 · 커밋에 적지 않는다.
# - 값을 Terraform 으로 넣지 않는 이유: 상태 파일에 평문으로 남고, 상태를 읽는 CI plan 역할에도 보인다.
# - 이름 접두어 ecr-pullthroughcache/ 는 ECR 이 요구하는 형식이다.
# - 암호화는 기본 키(aws/secretsmanager)만 된다 — ECR 이 고객 관리 키를 지원하지 않는다. 그래서 kms_key_id 를 적지 않는다.
# - 삭제 대기(recovery_window_in_days)는 기본 30일. 실수로 지우면 그동안 같은 이름으로 다시 만들 수 없다
#   → 매일 지우는 스택이 아니라 00-foundation 에 둔다.
# - 비용: 비밀 하나 월 0.40달러(만드는 순간부터).
#trivy:ignore:AWS-0098
resource "aws_secretsmanager_secret" "ghcr_credentials" {
  name        = "ecr-pullthroughcache/ghcr"
  description = "ghcr.io credentials for ECR pull-through cache. Value is set by a person, not Terraform."
}

resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  count = var.enable_ghcr_rule ? 1 : 0

  ecr_repository_prefix = "ghcr"
  upstream_registry_url = "ghcr.io"
  credential_arn        = aws_secretsmanager_secret.ghcr_credentials.arn
}

# 캐시가 자동으로 만드는 저장소에 붙는 설정(#27 결정 3 · 4).
# - 접두어는 규칙과 같게 적는다. 맞는 템플릿이 없으면 저장소가 오류 없이 기본 설정
#   (태그 변경 가능 · 수명 주기 없음)으로 생긴다 → 첫 pull 뒤 생성된 저장소 설정을 조회해 확인.
# - 템플릿에 저장소 태그 · KMS 암호화를 넣지 않으므로 저장소 생성 역할은 두지 않는다(그 둘을 넣을 때만 필요).
# - 최근 5개 유지(태그 유무 무관): digest 로 고정해 받으면 태그 없는 이미지로 저장될 수 있어,
#   「태그 없는 이미지 N일 뒤 삭제」 규칙은 쓰는 중인 이미지를 지울 수 있다. 지워진 이미지는 다음 pull 때 원본에서 다시 받는다.
resource "aws_ecr_repository_creation_template" "cache" {
  for_each = merge(var.cache_prefixes, { "ghcr" = "ghcr.io" })

  prefix               = each.key
  description          = "Repositories created by the pull-through cache (${each.value})"
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "IMMUTABLE"

  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
