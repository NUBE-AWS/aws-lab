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

variable "github_repository" {
  description = "CI 역할을 받을 수 있는 GitHub 저장소(<조직>/<저장소>)"
  type        = string
  default     = "NUBE-AWS/aws-lab"
}
