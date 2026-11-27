output "rule_arns" {
  description = "이 리전의 로그인 규칙 ARN 목록(전달 역할 신뢰 조건에 쓴다)"
  value       = [for r in aws_cloudwatch_event_rule.login : r.arn]
}
