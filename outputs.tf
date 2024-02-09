output "region" {
  description = "AWS region"
  value       = var.region
}


output "vpc_id" {
  value = jsondecode(data.aws_secretsmanager_secret_version.vpc.secret_string)["vpc_id"]
  sensitive = true
 }

 output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.wrds-eks.id
}