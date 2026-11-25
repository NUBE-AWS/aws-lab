terraform {
  required_version = ">= 1.10" # S3 상태 잠금(use_lockfile)을 쓰려면 1.10 이상

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # 상태 버킷을 만드는 디렉터리라 자기 상태는 로컬에 둔다(닭과 달걀).
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}
