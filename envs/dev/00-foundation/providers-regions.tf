# 서울 밖 다섯 리전의 공급자 별칭 — 관리자 권한 감시 규칙(watch.tf, #44 PR 4)에만 쓴다.
# - us-east-1: IAM 같은 전역 서비스의 API 이벤트가 이 리전에만 온다 + 콘솔 로그인이 기록될 수 있는 리전
# - us-east-2 · us-west-2 · eu-north-1 · ap-southeast-2: 콘솔 로그인이 기록될 수 있는 리전
#   (CloudTrail 콘솔 로그인 이벤트 문서, 2026-11-27 조회 — 가이드 9.7 1단계)
# 공급자는 for_each 로 돌릴 수 없어 리전마다 블록을 둔다. 이 리전들에는 규칙 · 대상만 만들고(무료), 그 밖의 자원은 두지 않는다.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}

provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}

provider "aws" {
  alias  = "eu_north_1"
  region = "eu-north-1"

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}

provider "aws" {
  alias  = "ap_southeast_2"
  region = "ap-southeast-2"

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}
