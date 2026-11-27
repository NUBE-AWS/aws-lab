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

variable "identifier" {
  description = "RDS 인스턴스 식별자. 콘솔 · 로그에 보이는 이름이며 파라미터 그룹 · 보안 그룹 이름의 앞부분으로도 쓴다"
  type        = string
  default     = "aws-lab-dev-pg"
}

variable "instance_class" {
  description = "인스턴스 크기(설계 6.1). db.t4g.small 은 PostgreSQL 17 까지만 받는다"
  type        = string
  default     = "db.t4g.small"
}

variable "allocated_storage" {
  description = "저장 공간 GiB(설계 6.1: gp3 20GB). 자동 증설은 켜지 않는다"
  type        = number
  default     = 20
}

variable "postgres_major_version" {
  description = "PostgreSQL 주 판(설계 6.1). 부 판은 코드에 적지 않고 데이터 소스로 「이 주 판의 최신」을 읽는다(2단계)"
  type        = string
  default     = "17"
}

variable "master_username" {
  description = "마스터 사용자 이름. 새로 만들 때만 쓴다(스냅샷에서 복원하면 스냅샷의 사용자를 그대로 쓰므로 4단계에서 null 로 바꾼다)"
  type        = string
  default     = "postgres"
}

variable "manage_master_user_password" {
  description = "마스터 비밀번호를 RDS 가 Secrets Manager(rds!db-…)에 만들고 회전하게 할지(설계 4.4). 비밀번호가 코드 · 상태에 들어가지 않는다. 복원이 거부될 때의 예비 경로를 위해 변수로 둔다(가이드 12.4)"
  type        = bool
  default     = true
}

variable "snapshot_identifier" {
  description = "복원할 수동 스냅샷 식별자(설계 6.1). 비워 두면(null) 빈 데이터베이스로 새로 만든다"
  type        = string
  default     = null
}
