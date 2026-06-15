terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Resource Group
resource "aws_resourcegroups_group" "lab_group" {
  name = "devops-final-lab-group"
  resource_query {
    query = <<JSON
{
  "ResourceTypeFilters": [
    "AWS::AllSupported"
  ],
  "TagFilters": [
    {
      "Key": "Environment",
      "Values": ["DevOpsLab"]
    }
  ]
}
JSON
  }
}

# 2. Virtual Network (VPC)
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "devops-lab-vpc"
    Environment = "DevOpsLab"
  }
}

resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name        = "devops-lab-igw"
    Environment = "DevOpsLab"
  }
}

resource "aws_subnet" "lab_subnet_1" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "devops-lab-subnet-1"
    Environment = "DevOpsLab"
  }
}

resource "aws_route_table" "lab_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }

  tags = {
    Name        = "devops-lab-rt"
    Environment = "DevOpsLab"
  }
}

resource "aws_route_table_association" "lab_rta_1" {
  subnet_id      = aws_subnet.lab_subnet_1.id
  route_table_id = aws_route_table.lab_rt.id
}

# 3. Storage Account (S3 Bucket)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "lab_bucket" {
  bucket = "devops-final-lab-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "devops-lab-bucket"
    Environment = "DevOpsLab"
  }
}

# 4. ECR Repository
resource "aws_ecr_repository" "lab_repo" {
  name                 = "devops-lab-image"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "devops-lab-repo"
    Environment = "DevOpsLab"
  }
}

# 5. ECS Cluster and Fargate Service
resource "aws_ecs_cluster" "lab_cluster" {
  name = "devops-lab-cluster"

  tags = {
    Name        = "devops-lab-cluster"
    Environment = "DevOpsLab"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRoleLab"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "DevOpsLab"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "lab_ecs_sg" {
  name        = "devops-lab-ecs-sg"
  description = "Allow port 8080"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "devops-lab-ecs-sg"
    Environment = "DevOpsLab"
  }
}

resource "aws_ecs_task_definition" "lab_task" {
  family                   = "devops-lab-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "devops-lab-container"
      image     = "${aws_ecr_repository.lab_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
    }
  ])

  tags = {
    Environment = "DevOpsLab"
  }
}

resource "aws_ecs_service" "lab_service" {
  name            = "devops-lab-service"
  cluster         = aws_ecs_cluster.lab_cluster.id
  task_definition = aws_ecs_task_definition.lab_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.lab_subnet_1.id]
    security_groups  = [aws_security_group.lab_ecs_sg.id]
    assign_public_ip = true
  }

  tags = {
    Environment = "DevOpsLab"
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.lab_repo.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.lab_cluster.name
}

output "service_name" {
  value = aws_ecs_service.lab_service.name
}
