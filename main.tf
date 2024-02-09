provider "aws" {
  region  = var.region
  profile = "cicd_user"
}

terraform {
  backend "s3" {
    bucket  = "wrdscodebuildrepoeks"
    key     = "codebuild/terraform.tfstate"
    region  = "us-east-1"
    profile = "cicd_user"
  }
}

data "aws_availability_zones" "available" {}

locals {
  vpc_id = jsondecode(data.aws_secretsmanager_secret_version.vpc.secret_string)["vpc_id"]
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

data "aws_vpc" "selected" {
  id = local.vpc_id
}

#################################################################################################
########### EXTRACTING DATADOG API-KEY AND GOLDEN IMAGE ID FROM SECRET MANAGER  #################
#################################################################################################

data "aws_secretsmanager_secret" "vpc" {
  name = "wrds_vpc"
}

# #PULLING THE AMI FROM AWS ACCOUNT
data "aws_secretsmanager_secret_version" "vpc" {
  # Fill in the name you gave to your secret
  secret_id = data.aws_secretsmanager_secret.vpc.id
}

resource "aws_vpc_ipv4_cidr_block_association" "sec" {
  vpc_id       = local.vpc_id
  cidr_block   = "10.0.0.0/16"
}


#################################################################################################
########################## PRIVATE SUBNETS FOR THE WRDS VPC #####################################
#################################################################################################

#APP SUBNETS 
resource "aws_subnet" "wrds-App-Private-1" {
    vpc_id                                   = data.aws_vpc.selected.id
    cidr_block                               = "10.0.1.0/24"
    map_public_ip_on_launch                  = false
    availability_zone                        = "us-east-1a"

    tags                                     = {
      "Name"                                 = "wrds-App-Priv-1"
      "Kubernetes.io/cluster/eks"            = "shared" #so that eks cluster can discover it and use to create private elb in this subnet
      "kubernetes.io/role/internal-elb"      = 1 #eks uses this to create service type load balancers
    }
}

resource "aws_subnet" "wrds-App-Private-2" {
    vpc_id                                   = data.aws_vpc.selected.id
    cidr_block                               = "10.0.2.0/24"
    map_public_ip_on_launch                  = false
    availability_zone                        = "us-east-1b"

    tags                                     = {
      "Name"                                 = "wrds-App-Priv-1"
      "Kubernetes.io/cluster/eks"            = "shared" #so that eks cluster can discover it and use to create private elb in this subnet
      "kubernetes.io/role/internal-elb"      = 1 #eks uses this to create service type load balancers
    }
}


resource "aws_subnet" "wrds-App-public-1" {
    vpc_id                          = data.aws_vpc.selected.id
    cidr_block                      = "10.0.4.0/24"
    map_public_ip_on_launch         = true
    availability_zone               = "us-east-1a"

    tags                            = {
      "Name"                        = "wrds-App-Pub-1"
      "Kubernetes.io/cluster/eks"   = "shared" #so that eks cluster can discover it and use to create public elb in this subnet
      "kubernetes.io/role/elb"      = 1 #eks uses this to create service type load balancers
    }
}

resource "aws_subnet" "wrds-App-public-2" {
    vpc_id                          = data.aws_vpc.selected.id
    cidr_block                      = "10.0.5.0/24"
    map_public_ip_on_launch         = true #required for eks. Instances launched into the subnet be 
    availability_zone               = "us-east-1b"

    tags                            = {
      "Name"                        = "wrds-App-Pub-2"
      "Kubernetes.io/cluster/eks"   = "shared" #so that eks cluster can discover it and use to create public elb in this subnet
      "kubernetes.io/role/elb"      = 1 #eks uses this to create service type load balancers
    }
}


#################################################################################################
###################################### INTERNET GATEWAY #########################################
#################################################################################################



resource "aws_internet_gateway" "wrds-Internet-GW" {
    vpc_id                  = data.aws_vpc.selected.id
    
    tags                    = {
      "Name"                = "wrds-IGW"
    }
}

#################################################################################################
###################################### CREATE EIP ###############################################
#################################################################################################

resource "aws_eip" "wrds-nat-eip-1" {

    depends_on = [aws_internet_gateway.wrds-Internet-GW]
    
}

resource "aws_eip" "wrds-nat-eip-2" {

    depends_on = [aws_internet_gateway.wrds-Internet-GW]
    
}
#################################################################################################
###################################### CREATE NAT GATEWAY #########################################
#################################################################################################

resource "aws_nat_gateway" "wrds-nat-gw-1" {
    allocation_id           = "${aws_eip.wrds-nat-eip-1.id}"
    subnet_id               = "${aws_subnet.wrds-App-public-1.id}"

    tags                    = {
      "Name"                = "wrds-nat-1"
    }
    depends_on              = [
      aws_internet_gateway.wrds-Internet-GW
    ]
}


resource "aws_nat_gateway" "wrds-nat-gw-2" {
    allocation_id           = "${aws_eip.wrds-nat-eip-2.id}"
    subnet_id               = "${aws_subnet.wrds-App-public-2.id}"

    tags                    = {
      "Name"                = "wrds-nat-2"
    }
    depends_on              = [
      aws_internet_gateway.wrds-Internet-GW
    ]
}


################################################################################################
##### ESTABLISH A ROUTE TABLE FOR THE PUBLIC SUBNETS WITH A ROUTE TO THE INTERNET GATEWAY ######
################################################################################################


resource "aws_route_table" "wrds-pub-RT"{
    vpc_id                  = data.aws_vpc.selected.id
    route {
      cidr_block            = "0.0.0.0/0"
      gateway_id            = "${aws_internet_gateway.wrds-Internet-GW.id}"
    }
    tags                    = {
      "Name"                = "wrds-pub-RT"
    }
}


resource "aws_route_table" "wrds-private-RT-1"{
    vpc_id                  = data.aws_vpc.selected.id
    route {
      cidr_block            = "0.0.0.0/0"
      nat_gateway_id        = "${aws_nat_gateway.wrds-nat-gw-1.id}"
    }
    tags                    = {
      "Name"                = "wrds-Priv-RT-1"
    }
}

resource "aws_route_table" "wrds-private-RT-2"{
    vpc_id                  = data.aws_vpc.selected.id
    route {
      cidr_block            = "0.0.0.0/0"
      nat_gateway_id        = "${aws_nat_gateway.wrds-nat-gw-2.id}"
    }
    tags                    = {
      "Name"                = "wrds-Priv-RT-2"
    }
}


#################################################################################################
########################### ASSOCIATE THE SUBNETS TO THE ROUTE TABLES ###########################
#################################################################################################

#PRIVATE SUBNET ASSOCIATION AZ A
resource "aws_route_table_association" "wrds-Private-1" {
    subnet_id               = "${aws_subnet.wrds-App-Private-1.id}"
    route_table_id          = "${aws_route_table.wrds-private-RT-1.id}"
}

resource "aws_route_table_association" "wrds-Private-2" {
    subnet_id               = "${aws_subnet.wrds-App-Private-2.id}"
    route_table_id          = "${aws_route_table.wrds-private-RT-2.id}"
}


#PUBLIC SUBNET ASSOCIATION AZ A
resource "aws_route_table_association" "wrds-Pub-1" {
    subnet_id               = "${aws_subnet.wrds-App-public-1.id}"
    route_table_id          = "${aws_route_table.wrds-pub-RT.id}"
}

resource "aws_route_table_association" "wrds-pub-2" {
    subnet_id               = "${aws_subnet.wrds-App-public-2.id}"
    route_table_id          = "${aws_route_table.wrds-pub-RT.id}"
}

#################################################################################################
#################################### CREATE EKS CLUSTER  ########################################
#################################################################################################

resource "aws_eks_cluster" "wrds-eks" {
  name     = "wrds-eks"
  version  = "1.27"
  role_arn = aws_iam_role.wrds-eks-cluster.arn

  vpc_config {
    #Indicates whether or not the Amazon EKS private API server endpoint is enabled
    endpoint_private_access = false

    #Indicates whether or not the Amazon EKS public API server endpoint is enabled
    endpoint_public_access = true


    subnet_ids = [
      aws_subnet.wrds-App-Private-1.id,
      aws_subnet.wrds-App-Private-2.id,
      aws_subnet.wrds-App-public-1.id,
      aws_subnet.wrds-App-public-2.id
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.amazon_eks_cluster_policy]
}


#################################################################################################
#################################### CREATE NODEGROUP  ######################################
#################################################################################################

resource "aws_eks_node_group" "wrds_nodes" {
  cluster_name    = aws_eks_cluster.wrds-eks.name
  node_group_name = "wrds-nodes"
  node_role_arn   = aws_iam_role.wrds-node-group.arn

  # Single subnet to avoid data transfer charges while testing.
  subnet_ids = [
    aws_subnet.wrds-App-Private-1.id,
    aws_subnet.wrds-App-Private-2.id
  ]
  ami_type       = "AL2_x86_64"
  capacity_type  = "ON_DEMAND"
  instance_types = ["m5.xlarge"]
  disk_size    = 300
  force_update_version = false
  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.nodes_amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.nodes_amazon_ec2_container_registry_read_only,
  ]
}




/* 



################################################################################################
##### ESTABLISH A ROUTE TABLE FOR THE PUBLIC SUBNETS WITH A ROUTE TO THE INTERNET GATEWAY ######
################################################################################################

resource "aws_route_table" "wrds-private-RT"{
    vpc_id                  = data.aws_vpc.selected.id
    route {
      cidr_block            = "0.0.0.0/0"
      gateway_id            = "${aws_internet_gateway.wrds-Internet-GW.id}"
    }
    tags                    = {
      "Name"                = "wrds-Priv-RT"
    }
}

resource "aws_route_table" "wrds-pub-RT"{
    vpc_id                  = data.aws_vpc.selected.id
    route {
      cidr_block            = "0.0.0.0/0"
      nat_gateway_id        = "${aws_nat_gateway.wrds-nat-gw.id}"
    }
    tags                    = {
      "Name"                = "wrds-pub-RT"
    }
}


#################################################################################################
################## ASSOCIATE THE SIX PRIVATE SUBNETS WITH THE ROUTE TABLE #######################
#################################################################################################

#PRIVATE SUBNET ASSOCIATION AZ A
resource "aws_route_table_association" "wrds-Private-1" {
    subnet_id               = "${aws_subnet.wrds-App-Private-1.id}"
    route_table_id          = "${aws_route_table.wrds-private-RT.id}"
}

resource "aws_route_table_association" "wrds-Private-2" {
    subnet_id               = "${aws_subnet.wrds-App-Private-2.id}"
    route_table_id          = "${aws_route_table.wrds-private-RT.id}"
}


#PUBLIC SUBNET ASSOCIATION AZ A
resource "aws_route_table_association" "wrds-Pub-1" {
    subnet_id               = "${aws_subnet.wrds-App-public-1.id}"
    route_table_id          = "${aws_route_table.wrds-pub-RT.id}"
}

resource "aws_route_table_association" "wrds-pub-2" {
    subnet_id               = "${aws_subnet.wrds-App-public-2.id}"
    route_table_id          = "${aws_route_table.wrds-pub-RT.id}"
}

 */
