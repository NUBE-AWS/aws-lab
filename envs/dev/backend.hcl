# bootstrap 의 출력 state_bucket 값을 bucket 에 적는다. 비밀 값이 아니므로 커밋한다.
bucket       = "aws-lab-tfstate-<계정 ID>"
key          = "envs/dev/terraform.tfstate"
region       = "ap-northeast-2"
encrypt      = true
use_lockfile = true # S3 객체로 잠금(Terraform 1.10+) — DynamoDB 테이블이 필요 없다
