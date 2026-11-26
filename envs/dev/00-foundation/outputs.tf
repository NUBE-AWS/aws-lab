output "github_plan_role_arn" {
  description = "저장소 변수 AWS_ROLE_ARN 에 넣을 값(PR plan 워크플로가 수임)"
  value       = aws_iam_role.github_plan.arn
}
