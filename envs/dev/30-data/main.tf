# 30-data — 작업 뒤 삭제: RDS for PostgreSQL · DB 보안 그룹 · TLS 파라미터 그룹 (설계 6.1, 가이드 12장, #65)
# 1단계: 다른 스택의 출력을 읽는다. 자원은 2~4단계에서 더한다.

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
