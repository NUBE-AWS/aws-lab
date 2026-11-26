# Terraform 상태 버킷 — envs/* 의 상태 파일을 보관한다.
# 이름에 계정 ID 를 붙여 전 세계에서 겹치지 않게 한다(S3 버킷 이름은 전역).

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "aws-lab-tfstate-${data.aws_caller_identity.current.account_id}"

  # 상태 버킷을 실수로 지우면 만든 자원을 Terraform 이 모르게 된다.
  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리 — 상태 파일을 잘못 덮어써도 이전 판으로 되돌릴 수 있다.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 서버 쪽 암호화(SSE-S3). 상태 파일에는 자원 ID · 때로는 비밀 값이 들어간다.
# CMK(SSE-KMS)는 키 비활성 · 삭제 시 상태를 못 읽는 위험과
# CI 역할의 kms 권한 관리가 늘어 지금은 쓰지 않는다 — 30-data 단계에서 다시 검토.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 공개 접근 전면 차단.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 전송 구간 암호화 강제(Security Hub S3.5) — HTTPS 가 아닌 요청은 모두 거부한다.
# Deny 만 있는 정책이라 공개 차단(block_public_policy)과 충돌하지 않는다.
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  # 공개 차단 설정이 먼저 적용된 뒤에 정책을 붙인다.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# 오래된 상태 판은 90일 뒤 정리(버전이 끝없이 쌓이지 않게).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
