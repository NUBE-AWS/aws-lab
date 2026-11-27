output "cluster_name" {
  description = "EKS 클러스터 이름(25-addons · kubeconfig)"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API 엔드포인트(25-addons)"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "클러스터 CA(base64, 25-addons)"
  value       = module.eks.cluster_certificate_authority_data
}

output "node_security_group_id" {
  description = "노드 보안 그룹(30-data 의 RDS 5432 허용 출처)"
  value       = module.eks.node_security_group_id
}
