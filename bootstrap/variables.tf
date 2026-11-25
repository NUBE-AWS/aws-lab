variable "region" {
  description = "자원을 만들 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "tags" {
  description = "모든 자원에 붙일 공통 태그(비용을 프로젝트별로 보기 위함)"
  type        = map(string)
  default = {
    Project   = "aws-lab"
    ManagedBy = "terraform"
  }
}
