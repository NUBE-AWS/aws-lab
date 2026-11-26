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
