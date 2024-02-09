resource "aws_iam_policy" "eks_ecr" {
    name = "eks-ecr"
    description = "provides image pull and push access to nodes from ecr"
    policy = data.aws_iam_policy_document.eks_ecr.json
    tags = {
        Environment = "Development"
        Terraform = "True"
        componemt = "EKS"
    }
}

#################################################################################################
############################## CREATE ROLE AND POLICY FOR EKS  ##################################
#################################################################################################


# The role that Amazon EKS will use to create AWS resources for Kubernetes clusters
resource "aws_iam_role" "wrds-eks-cluster" {
  name = "wrds-eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

#Define aws eks cluster policy and attach it to the above role
resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.wrds-eks-cluster.name
}


#################################################################################################
########################## CREATE ROLE AND POLICY FOR NODE GROUP  ###############################
#################################################################################################

#Create this role so that amzonson ec2 used as the eks nodes can assume this role
resource "aws_iam_role" "wrds-node-group" {
  name = "wrds-node-group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

#THREE POLICIES WOULD BE ATTACHED TO THIS

#ATTACH AMAZON EKS WORKER NODE POLICY

resource "aws_iam_role_policy_attachment" "nodes_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.wrds-node-group.name
}
#ATTACH AMAZON EKS SNI POLICY

resource "aws_iam_role_policy_attachment" "nodes_amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.wrds-node-group.name
}

#ATTACH AMAZON EC2 CONTAINER REGISTRY POLICY

resource "aws_iam_role_policy_attachment" "nodes_amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.wrds-node-group.name
}