output "db_identifier" {
  description = "RDS 인스턴스 식별자(콘솔 · CLI 에서 찾는 이름)"
  value       = aws_db_instance.postgres.identifier
}

output "db_address" {
  description = "RDS 호스트 이름(VPC 안에서만 풀린다). 25-addons 가 DB 계정 Job · NetBox 에 전달한다"
  value       = aws_db_instance.postgres.address
}

output "db_port" {
  description = "PostgreSQL 포트(5432)"
  value       = aws_db_instance.postgres.port
}

# master_user_secret 은 목록이라 one() 으로 하나를 꺼낸다(관리형 비밀을 끄면 null). 비밀번호 자체는 출력하지 않는다.
output "master_user_secret_arn" {
  description = "RDS 가 Secrets Manager 에 만든 마스터 비밀 ARN(설계 4.4). platform-jobs/db-account 만 읽는다. 30-data 를 다시 만들 때마다 바뀐다"
  value       = one(aws_db_instance.postgres.master_user_secret[*].secret_arn)
}

output "db_security_group_id" {
  description = "DB 보안 그룹 ID(다른 스택이 DB 접근을 열 때)"
  value       = aws_security_group.db.id
}
