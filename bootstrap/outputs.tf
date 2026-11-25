output "state_bucket" {
  description = "envs/dev/backend.hcl 의 bucket 에 적을 이름"
  value       = aws_s3_bucket.tfstate.bucket
}

output "account_id" {
  description = "지금 로그인한 계정 — 개인 계정이 맞는지 확인"
  value       = data.aws_caller_identity.current.account_id
}
