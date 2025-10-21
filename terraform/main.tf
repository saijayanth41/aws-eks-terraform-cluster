provider "aws" { region = var.region }

terraform {
  backend "s3" {
    bucket         = "rsj-tf-state-1761023519"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-locks"
    encrypt        = true
  }
}

module "vpc" {
  source              = "terraform-aws-modules/vpc/aws"
  version             = "~> 5.8"
  name                = "rsj-vpc"
  cidr                = "10.0.0.0/16"
  azs                 = ["${var.region}a", "${var.region}b"]
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = true
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "~> 20.17"
  cluster_name                             = var.cluster_name
  cluster_version                          = "1.29"
  cluster_endpoint_public_access           = true
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  control_plane_subnet_ids                 = module.vpc.private_subnets
  enable_cluster_creator_admin_permissions = true
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      capacity_type  = "ON_DEMAND"
    }
  }
  tags = { Project = "Week5-EKS" }
}

# Auth token must still be fetched from AWS once cluster exists
data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks] # ensure cluster exists first
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
