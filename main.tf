# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Random string for S3 bucket name uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# VPC AND NETWORKING
# =============================================================================

# VPC
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateway
resource "aws_eip" "nat" {
  count = length(var.availability_zones) > 0 ? 1 : 0

  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "this" {
  count = length(var.availability_zones) > 0 ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = "${var.project_name}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


# S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket        = "${var.project_name}-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-logs"
  })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Sample file
resource "aws_s3_object" "this" {
  bucket  = aws_s3_bucket.this.id
  key     = "sample-document.txt"
  content = "This is a sample document for S3 to EFS replication demo.\n\nThis file will be automatically replicated to EFS via AWS DataSync.\n\nFile created by Terraform for testing purposes."

  tags = merge(local.tags, {
    Name = "${var.project_name}-sample-file"
    Type = "Sample"
  })
}

# =============================================================================
# VPC ENDPOINTS FOR PRIVATE TRAFFIC
# =============================================================================

# Gateway VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3Read"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      },
      {
        Sid       = "S3Write"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

# Interface VPC Endpoint for EFS (REQUIRED for EC2 access)
resource "aws_vpc_endpoint" "efs" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.elasticfilesystem"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-efs-endpoint"
  })
}

# Interface VPC Endpoint for DataSync (REQUIRED for DataSync in private subnets)
resource "aws_vpc_endpoint" "datasync" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.datasync"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-datasync-endpoint"
  })
}



# Interface VPC Endpoint for STS (for IAM role assumption)
resource "aws_vpc_endpoint" "sts" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.sts"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-sts-endpoint"
  })
}

# Interface VPC Endpoint for CloudWatch Logs (for DataSync logging)
resource "aws_vpc_endpoint" "logs" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.logs"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-logs-endpoint"
  })
}

# Interface VPC Endpoint for SSM
resource "aws_vpc_endpoint" "ssm" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.ssm"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm-endpoint"
  })
}

# Interface VPC Endpoint for SSM Messages
resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.ssmmessages"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm-messages-endpoint"
  })
}

# Interface VPC Endpoint for EC2 Messages
resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.ec2messages"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-messages-endpoint"
  })
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpc-endpoints-"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc-endpoints-sg"
  })
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-efs-"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-efs-sg"
  })
}


# =============================================================================
# EFS FILE SYSTEM
# =============================================================================

# EFS File System
resource "aws_efs_file_system" "this" {
  creation_token = "${var.project_name}-efs-${random_id.bucket_suffix.hex}"
  encrypted      = true

  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 100

  tags = merge(local.tags, {
    Name = "${var.project_name}-efs"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "this" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}


# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for DataSync
resource "aws_iam_role" "datasync" {
  name = "${var.project_name}-datasync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DataSyncAssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "datasync.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# IAM policy for DataSync S3 access
resource "aws_iam_role_policy" "datasync_s3" {
  name = "${var.project_name}-datasync-s3-policy"
  role = aws_iam_role.datasync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DataSyncS3Read"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectMetadata"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      },
      {
        Sid    = "DataSyncS3Write"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploads",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for DataSync EFS access
resource "aws_iam_role_policy" "datasync_efs" {
  name = "${var.project_name}-datasync-efs-policy"
  role = aws_iam_role.datasync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DataSyncEFSRead"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount"
        ]
        Resource = aws_efs_file_system.this.arn
      },
      {
        Sid    = "DataSyncEFSWrite"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.this.arn
      }
    ]
  })
}

# =============================================================================
# EC2 INSTANCE FOR EFS MOUNT TESTING
# =============================================================================

# Security group for EC2 instance
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  vpc_id      = aws_vpc.this.id

  # EFS access
  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.efs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

# IAM role for EC2 instance
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = local.tags
}

# IAM policy for EFS access
resource "aws_iam_role_policy" "ec2_efs" {
  name = "${var.project_name}-ec2-efs-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2EFSRead"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount"
        ]
        Resource = aws_efs_file_system.this.arn
      },
      {
        Sid    = "EC2EFSWrite"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.this.arn
      }
    ]
  })
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy for CloudWatch Logs (for SSM logging)
resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "${var.project_name}-ec2-cloudwatch-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ssm/*"
      },
      {
        Sid    = "EC2CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ssm/*",
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ssm/*:log-stream:*"
        ]
      }
    ]
  })
}

# EC2 instance
resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    efs_id = aws_efs_file_system.this.id
  }))

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2"
  })

  depends_on = [aws_efs_mount_target.this]
}

# Data source for Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

# CloudWatch Log Group for DataSync
resource "aws_cloudwatch_log_group" "datasync" {
  name              = "/aws/datasync/${var.project_name}-s3-to-efs"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-datasync-logs"
  })
}

# =============================================================================
# DATASYNC LOCATIONS AND TASK
# =============================================================================

# DataSync S3 location
resource "aws_datasync_location_s3" "this" {
  s3_bucket_arn = aws_s3_bucket.this.arn
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync.arn
  }

  tags = local.tags
}

# DataSync EFS location
resource "aws_datasync_location_efs" "this" {
  efs_file_system_arn = aws_efs_file_system.this.arn
  subdirectory        = "/"

  ec2_config {
    security_group_arns = [aws_security_group.efs.arn]
    subnet_arn          = aws_subnet.private[0].arn
  }

  depends_on = [aws_efs_mount_target.this]

  tags = local.tags
}

# DataSync task
resource "aws_datasync_task" "this" {
  destination_location_arn = aws_datasync_location_efs.this.arn
  source_location_arn      = aws_datasync_location_s3.this.arn

  name = "${var.project_name}-s3-to-efs-task"

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.datasync.arn

  # Schedule the task to run every hour
  schedule {
    schedule_expression = "rate(1 hour)"
  }

  options {
    verify_mode            = "POINT_IN_TIME_CONSISTENT"
    overwrite_mode         = "ALWAYS"
    atime                  = "BEST_EFFORT"
    mtime                  = "PRESERVE"
    uid                    = "INT_VALUE"
    gid                    = "INT_VALUE"
    preserve_deleted_files = "PRESERVE"
    preserve_devices       = "NONE"
    posix_permissions      = "NONE"
    bytes_per_second       = -1
    task_queueing          = "ENABLED"
    log_level              = "TRANSFER"
    transfer_mode          = "CHANGED"
    object_tags            = "PRESERVE"
  }

  tags = local.tags
}
