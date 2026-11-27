output "github_plan_role_arn" {
  description = "저장소 변수 AWS_ROLE_ARN 에 넣을 값(PR plan 워크플로가 수임)"
  value       = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  description = "저장소 Secret AWS_APPLY_ROLE_ARN 에 넣을 값(병합 뒤 apply · 비상 끄기 워크플로가 수임)"
  value       = aws_iam_role.github_apply.arn
}

output "eks_kms_key_arn" {
  description = "EKS Secret 봉투 암호화 키 — 20-cluster 가 terraform_remote_state 로 읽는다(이름을 바꾸지 말 것, #26)"
  value       = aws_kms_key.eks.arn
}

output "alerts_topic_arn" {
  description = "경보 SNS 주제 — CloudWatch 경보 · Budgets 가 여기로 보낸다"
  value       = aws_sns_topic.alerts.arn
}

output "github_nightly_role_arn" {
  description = "저장소 Secret AWS_NIGHTLY_ROLE_ARN 에 넣을 값(야간 점검 워크플로가 수임, #28)"
  value       = aws_iam_role.github_nightly.arn
}

output "cache_prefixes" {
  description = "쓰는 중인 ECR pull-through cache 접두어 — 20-cluster 노드 역할 권한(repository/<접두어>/*) · 차트 values 와 같아야 한다(#27)"
  value       = concat(keys(var.cache_prefixes), var.enable_ghcr_rule ? ["ghcr"] : [])
}

output "cluster_admins_group_name" {
  description = "EKS 클러스터 관리자 그룹 이름 — 20-cluster 가 멤버를 조회해 액세스 항목을 만든다(#50)"
  value       = aws_iam_group.cluster_admins.name
}

output "rds_kms_key_arn" {
  description = "RDS 저장 암호화 키(alias/aws-lab-rds) — 30-data 가 terraform_remote_state 로 읽어 kms_key_id 로 넘긴다(이름을 바꾸지 말 것, #64)"
  value       = aws_kms_key.rds.arn
}

output "name_servers" {
  description = "aws.nube.it.kr 영역의 네임서버 4개 — ns1 의 nube.it.kr 영역에 aws NS 레코드로 넣는다(#44). 이슈 · PR 에 붙이지 않음"
  value       = aws_route53_zone.aws.name_servers
}

output "hosted_zone_id" {
  description = "aws.nube.it.kr 영역 ID — ACM DNS 검증 레코드와 20-cluster external-dns 역할이 읽는다(#44)"
  value       = aws_route53_zone.aws.zone_id
}
