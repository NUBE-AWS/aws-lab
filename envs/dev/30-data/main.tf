# 30-data — 작업 뒤 삭제: RDS for PostgreSQL · DB 보안 그룹 · TLS 파라미터 그룹 (설계 6.1, 가이드 12장, #65)
# 1단계: 다른 스택의 출력 읽기 · 2단계: TLS 파라미터 그룹 · 3단계: DB 보안 그룹 · 4단계: DB 인스턴스(출력은 outputs.tf).

data "aws_caller_identity" "current" {}

locals {
  # bootstrap 이 정한 상태 버킷 이름(aws-lab-tfstate-<계정 ID>). 20-cluster 와 같은 방식 — 변수 · Secret 이 필요 없다.
  state_bucket = "aws-lab-tfstate-${data.aws_caller_identity.current.account_id}"
}

# 다른 스택의 출력 읽기 — 출력 이름이 스택 사이의 계약이다.
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/foundation/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/network/terraform.tfstate"
    region = var.region
  }
}

# 20-cluster 가 꺼져 있으면 node_security_group_id 가 없어 plan 이 멈춘다 — 30-data 는 20-cluster 뒤에 켠다(#34 결정 A).
data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "dev/cluster/terraform.tfstate"
    region = var.region
  }
}

# 이 스택이 기대는 출력 4개를 한곳에 모은다. 앞 스택의 출력 이름이 바뀌면 여기만 고친다.
locals {
  rds_kms_key_arn            = data.terraform_remote_state.foundation.outputs.rds_kms_key_arn         # 4단계: 저장 암호화(처음 만들 때만 전달, 바꿀 수 없음)
  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id                     # 3단계: DB 보안 그룹의 VPC
  database_subnet_group_name = data.terraform_remote_state.network.outputs.database_subnet_group_name # 4단계: 인터넷 경로 없는 DB 서브넷
  node_security_group_id     = data.terraform_remote_state.cluster.outputs.node_security_group_id     # 3단계: 5432 를 허용할 출처
}

# --- 2단계: TLS 파라미터 그룹 (설계 6.1 「TLS 강제」) ---

# 주 판(17)에서 실제 판 · 파라미터 그룹 패밀리를 찾는다. 부 판은 코드에 숫자로 적지 않는다(설계 6.1).
# latest = true 가 없으면 17.x 가 여러 개 맞아 「multiple RDS engine versions」 오류가 난다(2026-11-27 시험, v6.74.0).
data "aws_rds_engine_version" "postgres" {
  engine  = "postgres"
  version = var.postgres_major_version
  latest  = true
}

resource "aws_db_parameter_group" "tls" {
  name        = "${var.identifier}-tls"
  family      = data.aws_rds_engine_version.postgres.parameter_group_family
  description = "rds.force_ssl = 1 (design 6.1: enforce TLS)"

  # PostgreSQL 15 이상은 기본값도 1 이지만, 기본값에 기대지 않고 설계의 「TLS 강제」를 코드에 남긴다.
  # 적용 방식: postgres17 의 ApplyType 은 dynamic(재부팅 없이 적용, 2026-11-27 서울 조회) → immediate.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

# --- 3단계: DB 보안 그룹 (설계 6.1 · 5.1) ---

# 안에 ingress · egress 블록을 쓰지 않는다. 규칙은 아래 별도 자원으로 둔다.
# egress 없음: 공급자가 AWS 기본 「모두 나가기」 규칙을 지우고, DB 서브넷엔 바깥 경로도 없다. 응답은 stateful 이라 돌아간다.
# description 을 바꾸면 보안 그룹이 교체되므로 처음부터 확정한다(영어 — #18).
resource "aws_security_group" "db" {
  name        = "${var.identifier}-db"
  description = "RDS: allow 5432 only from the EKS node security group"
  vpc_id      = local.vpc_id
}

# 출처는 IP 대역이 아니라 노드 보안 그룹 — 노드를 매일 새로 만들어 IP 가 바뀌어도 규칙은 그대로다.
# 파드 트래픽도 노드의 네트워크 인터페이스(VPC CNI)로 나가 이 그룹에서 온 것으로 보인다. Karpenter 앱 노드도 같은 그룹을 붙인다.
# 파드 단위 구분은 네트워크 정책(설계 5.1)과 앱별 DB 계정이 맡는다(파드별 보안 그룹은 t 계열 노드에서 못 씀).
resource "aws_vpc_security_group_ingress_rule" "db_from_nodes" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = local.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes (design 6.1 and 5.1)"
}

# --- 4단계: DB 인스턴스 (설계 6.1 · 11장 「데이터」) ---
# ⚠️ 켜 두면 요금: db.t4g.small 시간당 약 0.051달러 + gp3 20GB. 매일 emergency-down 이 30 부터 지운다.
#
# Trivy 예외(설계상 의도):
# - AWS-0177 삭제 보호 꺼짐: 매일 지우는 스택(설계 6.1). 켜면 emergency-down 의 destroy 가 멈춘다
# - AWS-0176 IAM DB 인증 꺼짐: 앱 계정은 비밀번호 + Secrets Manager · External Secrets 로 준다(설계 4.4)
# - AWS-0133 Performance Insights 꺼짐: 경보는 최소로 둔다(설계 8장). 필요한 날 켤 수 있다(7일 보관은 무료)
#trivy:ignore:AWS-0177
#trivy:ignore:AWS-0176
#trivy:ignore:AWS-0133
resource "aws_db_instance" "postgres" {
  identifier = var.identifier

  # 판: 데이터 소스가 고른 「주 판의 최신」(2단계). 판은 Terraform 만 정한다 —
  # AWS 가 유지 관리 시간에 부 판을 올리면 코드의 정확한 판과 어긋나므로 자동 올리기를 끈다(#65 결정 A).
  # 매일 새로 만들어 그날의 최신 판을 받는다.
  engine                     = "postgres"
  engine_version             = data.aws_rds_engine_version.postgres.version_actual
  auto_minor_version_upgrade = false

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  # 저장 암호화: RDS 전용 고객 관리 키(00-foundation, #64). 비우면 AWS 관리 키로 조용히 만들어지고
  # 만든 뒤에는 바꿀 수 없다(바꾸면 인스턴스 교체 = 데이터 소실). 원격 상태 출력이라 키가 없으면 plan 이 멈춘다.
  storage_encrypted = true
  kms_key_id        = local.rds_kms_key_arn

  # 위치 · 접근: 인터넷 경로 없는 DB 서브넷, 공개 접근 끔, 노드에서 오는 5432 만(3단계), TLS 강제(2단계).
  # Multi-AZ 는 평소 끈다(요금 2배) — 장애 조치 비교 시험(설계 9장) 때만 켠다.
  db_subnet_group_name   = local.database_subnet_group_name
  multi_az               = false
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.tls.name
  port                   = 5432

  # 새로 만들 때만 사용자 이름을 준다. 스냅샷에서 복원하면 스냅샷의 사용자를 쓰므로 null 이어야 한다.
  # 비밀번호는 RDS 가 Secrets Manager(rds!db-…)에 만들고 회전한다 — 코드 · 상태에 들어가지 않는다(설계 4.4).
  username                    = var.snapshot_identifier == null ? var.master_username : null
  manage_master_user_password = var.manage_master_user_password
  snapshot_identifier         = var.snapshot_identifier

  # 백업: 공급자 기본값은 0(백업 없음)이라 반드시 적는다. 자동 백업은 인스턴스가 있는 동안의 시점 복원 수단이다.
  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # 삭제: 매일 지우는 스택. skip_final_snapshot 기본값 false 면 destroy 가 최종 스냅샷 이름을 요구하며 실패한다.
  # 자동 백업을 남기지 않는 것도 기본값에 기대지 않고 적는다(남으면 삭제 뒤에도 저장 요금). 남길 데이터는 지우기 전 수동 스냅샷.
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
}
