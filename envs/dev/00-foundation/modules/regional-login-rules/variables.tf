variable "rules" {
  description = "규칙 이름(key) → 이벤트 패턴(객체). 규칙 이름은 aws-lab-<key>"
  type        = map(any)
}

variable "target_bus_arn" {
  description = "넘길 대상 이벤트 버스 ARN(서울 기본 버스)"
  type        = string
}

variable "forward_role_arn" {
  description = "다른 리전 버스로 보낼 때 쓰는 실행 역할 ARN"
  type        = string
}
