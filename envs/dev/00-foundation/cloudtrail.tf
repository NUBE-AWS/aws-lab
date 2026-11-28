# CloudTrail 추적과 로그 버킷(설계 5.4, #26) — 「누가 무엇을 바꿨나」를 S3 에 1년 보관한다.
# - 관리 이벤트(모든 리전) + 상태 버킷 하나의 S3 데이터 이벤트(설계 7.4). 계정의 첫 추적이 남기는 관리 이벤트 1부는 무료.
#   데이터 이벤트는 건수 요금이라 상태 버킷 하나로 한정한다. Insights · CloudWatch Logs 전달은 유료라 켜지 않는다.
# - 모든 리전인 이유: 유출된 자격 증명은 보통 안 쓰는 리전에서 쓰인다(#26 결정 3).
# - 콘솔 「이벤트 기록」(최근 90일)은 추적 없이도 무료 → 추적은 90일 넘는 보관 · 원본 파일 · 무결성 검증 용도.

locals {
  account_id        = data.aws_caller_identity.current.account_id
  trail_name        = "aws-lab-trail"
  trail_arn         = "arn:aws:cloudtrail:${var.region}:${local.account_id}:trail/${local.trail_name}"
  cloudtrail_bucket = "aws-lab-cloudtrail-${local.account_id}"
}

# ── 로그 버킷 ────────────────────────────────────────────────

# Trivy 예외 AWS-0089(버킷 접근 로그 꺼짐, LOW, #52 A안):
# - 접근 로그를 켜려면 로그 전용 버킷이 하나 더 필요하고, 그 버킷도 같은 경고를 받는다(로그 버킷의 로그는 범위 밖).
# - 이 버킷의 API 호출(정책 · 설정 변경, 삭제 시도)은 CloudTrail 관리 이벤트로 남는다.
# - 객체 단위 기록이 필요해지면 접근 로그보다 CloudTrail S3 데이터 이벤트가 맞다(요금 있음).
#trivy:ignore:AWS-0089
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

  # 기록 대상(설계 7.4): 관리 이벤트는 지금처럼 읽기 · 쓰기 모두, 여기에 Terraform 상태 버킷의 객체 읽기 · 쓰기를 더한다.
  # - 상태 파일에는 비밀이 들어갈 수 있어(Cognito 클라이언트 비밀 등) 누가 상태를 읽었는지 남긴다.
  #   S3 객체 단위 호출(GetObject · PutObject · DeleteObject)은 관리 이벤트가 아니라 데이터 이벤트라 따로 넣어야 남는다.
  # - 대상은 상태 버킷 하나(local.state_bucket, github-oidc.tf — bootstrap 과 같은 이름 규칙). 건수 요금이라
  #   첫 달 청구서에서 금액을 확인한다. 끝의 「/」는 버킷 안의 모든 객체라는 뜻이다.
  # - 이 블록을 바꾸면 PutEventSelectors 가 불린다. CI apply 역할은 이 호출을 거부하므로(ci-deny.tf
  #   DenyCloudTrailStopOrDelete) 사람이 로컬에서 00-foundation 을 apply 한다(README 「CI로 적용되지 않는 변경」).
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${local.state_bucket}/"]
    }
  }

  # 버킷 정책이 먼저 있어야 CloudTrail 이 생성 때 쓰기 권한을 확인할 수 있다.
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
