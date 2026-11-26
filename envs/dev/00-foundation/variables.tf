variable "region" {
  description = "자원을 만들 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "tags" {
  description = "모든 자원에 붙일 공통 태그(비용을 프로젝트·스택별로 보기 위함)"
  type        = map(string)
  default = {
    Project     = "aws-lab"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# 이 저장소는 GitHub OIDC immutable subject claim 을 쓴다(2026-07-15 이후 만든 저장소 기본값).
# 토큰 sub 가 repo:<조직>@<조직 ID>/<저장소>@<저장소 ID>:<문맥> 형식이라 ID 까지 넣어야 한다.
# 확인: gh api repos/NUBE-AWS/aws-lab/actions/oidc/customization/sub → sub_claim_prefix
# 조직 · 저장소 ID 는 공개 정보다.
variable "github_sub_prefix" {
  description = "CI 역할을 받을 수 있는 저장소의 OIDC sub 접두어(sub_claim_prefix 값)"
  type        = string
  default     = "repo:NUBE-AWS@361035027/aws-lab@1471481146"
}
