provider "aws" {
  region = "us-east-1"
}

#--------------------------------------------------------------------------------------

# VPC 
resource "aws_vpc" "EA" {      # tf_env, only(_) , no(-)
  cidr_block = "10.0.0.0/16"   # Parameter: the CIDR block for the VPC.
  
  # Enable DNS support and DNS hostnames in the VPC.
  enable_dns_support   = true 
  enable_dns_hostnames = true  

  tags = {
    Name = "EA"
  }
}


# Subnet Configuration
resource "aws_subnet" "public_1a" {     
  vpc_id            = aws_vpc.EA.id  # specifies the VPC to create the subnet in.
  cidr_block        = "10.0.1.0/24"    
  availability_zone = "us-east-1a"      
  
  tags = {
    Name = "public_1a" 
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.EA.id 
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"      

  tags = {
    Name = "private_1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id            = aws_vpc.EA.id 
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "public_1b" 
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.EA.id 
  cidr_block        = "10.0.4.0/24"     
  availability_zone = "us-east-1b"      

  tags = {
    Name = "private_1b" 
  }
}

#----------------------------------------------------------------

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.EA.id

  tags = {
    Name = "EA-igw"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.EA.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Associate Subnets to RT
resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

#-------------------------------------------------------------

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_eip_1a" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-1a"
  }
}

resource "aws_eip" "nat_eip_1b" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-1b"
  }
}


# NAT Gateways 
resource "aws_nat_gateway" "nat_1a" {
  allocation_id = aws_eip.nat_eip_1a.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "nat-1a"
  }
}

resource "aws_nat_gateway" "nat_1b" {
  allocation_id = aws_eip.nat_eip_1b.id
  subnet_id     = aws_subnet.public_1b.id

  tags = {
    Name = "nat-1b"
  }
}

#-----------------------------------------------------------

# Route Tables for Private Subnets 
resource "aws_route_table" "private_1a" {
  vpc_id = aws_vpc.EA.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1a.id
  }

  tags = {
    Name = "private-rt-1a"
  }
}

# Associate Subnets to RT
resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_1a.id
}


resource "aws_route_table" "private_1b" {
  vpc_id = aws_vpc.EA.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1b.id
  }

  tags = {
    Name = "private-rt-1b"
  }
}

# Associate Subnets to RT
resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_1b.id
}

#----------------------------------------------------------------

# EKS_cluster
resource "aws_eks_cluster" "EA_EKS" {
  name     = "EA_EKS"
  role_arn = "arn:aws:iam::373335955733:role/LabRole"

  vpc_config {
    subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
  }

  tags = {
    Name = "EA_EKS"
  }
}

#---------------------------------------------------------------------

# Database variable
variable "db_cluster_identifier" {
  default = "database-1"
}

variable "db_username" {
  default = "root"
}

variable "db_password" {
  default = "12345678"
}

# Database Subnet Group
variable "subnet_ids" {
  type = list(string)
  default = []
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = {
    Name = "Aurora subnet group"
  }
}

# Security Group for RDS
resource "aws_security_group" "DB_SG" {
  name        = "DB_SG"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.EA.id

  tags = {
    Name = "DB_SG"
  }
}

#-------------------------------------------------------------------

# Database Cluster
resource "aws_rds_cluster" "aurora_cluster" {
  cluster_identifier   = var.db_cluster_identifier
  engine               = "aurora-mysql"
  master_username      = var.db_username
  master_password      = var.db_password
  db_subnet_group_name = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids = [aws_security_group.DB_SG.id]

  skip_final_snapshot  = true

  tags = {
    Name = "Aurora Cluster"
  }
}

# Database Instances
resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = 2
  identifier         = "${var.db_cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora_cluster.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.aurora_cluster.engine
  publicly_accessible = false
  apply_immediately  = true
  auto_minor_version_upgrade = false
  monitoring_interval        = 0

  tags = {
    Name = "Aurora Instance ${count.index + 1}"
  }
}

output "rds_cluster_endpoint" {
  value = aws_rds_cluster.aurora_cluster.endpoint
}

output "rds_cluster_reader_endpoint" {
  value = aws_rds_cluster.aurora_cluster.reader_endpoint
}

#-------------------------------------------------------------------
