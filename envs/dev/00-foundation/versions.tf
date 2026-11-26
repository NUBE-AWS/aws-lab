terraform {
  required_version = ">= 1.10" # S3 상태 잠금(use_lockfile)을 쓰려면 1.10 이상

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 공통 값(bucket · region · 잠금)은 ../backend.hcl 에서 받는다.
  #   terraform init -backend-config=../backend.hcl
  # key 는 이 스택의 상태 파일 위치 — 스택마다 다르게 고정한다.
  backend "s3" {
    key = "dev/foundation/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, { Stack = "00-foundation" })
  }
}
