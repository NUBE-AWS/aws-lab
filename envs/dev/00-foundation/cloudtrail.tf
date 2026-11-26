# CloudTrail 추적과 로그 버킷(설계 5.4, #26) — 「누가 무엇을 바꿨나」를 S3 에 1년 보관한다.
# - 관리 이벤트만, 모든 리전. 계정의 첫 추적이 남기는 관리 이벤트 1부는 무료.
#   데이터 이벤트 · Insights · CloudWatch Logs 전달은 유료라 켜지 않는다.
# - 모든 리전인 이유: 유출된 자격 증명은 보통 안 쓰는 리전에서 쓰인다(#26 결정 3).
# - 콘솔 「이벤트 기록」(최근 90일)은 추적 없이도 무료 → 추적은 90일 넘는 보관 · 원본 파일 · 무결성 검증 용도.

locals {
  account_id        = data.aws_caller_identity.current.account_id
  trail_name        = "aws-lab-trail"
  trail_arn         = "arn:aws:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
  cloudtrail_bucket = "aws-lab-cloudtrail-${local.account_id}"
}

# ── 로그 버킷 ────────────────────────────────────────────────

# 버킷 접근 로그(AWS-0089, LOW)는 두지 않는다 — 로그 버킷의 로그는 범위 밖. LOW 라 CI 를 막지 않는다.
resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.cloudtrail_bucket
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL 을 쓰지 않는다 — 객체 소유자는 항상 버킷 주인.
resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3. CMK(SSE-KMS)는 bootstrap(#23)과 같은 이유로 쓰지 않는다 — 키 관리 · 권한이 늘고,
# CloudTrail 이 키를 쓰도록 키 정책도 열어야 한다.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 버전 관리 — 로그 파일을 덮어쓰거나 지워도 이전 판이 남는다(무결성 검증과 함께).
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 1년 뒤 삭제(#26: 90일은 콘솔 이벤트 기록과 겹침). 지난 판은 30일 뒤 삭제.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = 365
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

# CloudTrail 만, 그리고 이 계정의 이 추적만 쓸 수 있다(aws:SourceArn). HTTPS 가 아닌 요청은 거부.
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*",
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

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# ── 추적 ─────────────────────────────────────────────────────

# 예외 두 가지(근거는 #26):
# - AWS-0015 CMK 암호화 없음: 위 버킷과 같은 이유(SSE-S3 사용)
# - AWS-0162 CloudWatch Logs 연동 없음: 수집 요금(GB당 0.25달러 + 수집)이 들어 S3 보관만 한다
#trivy:ignore:AWS-0015
#trivy:ignore:AWS-0162
resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true
  include_global_service_events = true # IAM · STS 같은 전역 서비스 이벤트
  enable_log_file_validation    = true # 로그 파일이 바뀌지 않았는지 검증하는 다이제스트 파일

  # 버킷 정책이 먼저 있어야 CloudTrail 이 생성 때 쓰기 권한을 확인할 수 있다.
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
