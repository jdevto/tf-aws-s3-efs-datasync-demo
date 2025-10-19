# AWS S3 to EFS DataSync Demo

A Terraform demo that shows automated file replication from Amazon S3 to Amazon EFS using AWS DataSync with private networking and hourly scheduling.

## 🎯 Overview

This demo creates infrastructure for continuous data replication from S3 to EFS, demonstrating AWS DataSync capabilities with private networking.

## 🏗️ Architecture

```plaintext
S3 Bucket → DataSync (hourly) → EFS → EC2 Mount
     ↓
CloudWatch Logs
     ↓
SSM Access for Management
```

### Key Components

- **VPC**: Private networking with public/private subnets
- **S3 Bucket**: Source data storage with versioning and encryption
- **EFS**: Target file system with mount targets in private subnets
- **DataSync**: Automated replication with hourly scheduling
- **EC2 Instance**: Testing instance with EFS mount for verification
- **VPC Endpoints**: Private access to AWS services
- **CloudWatch**: Comprehensive logging and monitoring

## 🚀 Features

- **Private Networking**: All traffic stays within VPC
- **Automated Replication**: Hourly DataSync scheduling
- **Incremental Sync**: Only transfers changed files
- **Security**: IAM policies with separated read/write permissions
- **Monitoring**: CloudWatch logs for DataSync
- **Testing**: EC2 instance with SSM access for verification

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Access to create VPC, S3, EFS, DataSync, and EC2 resources

## 🛠️ Usage

### 1. Clone and Initialize

```bash
git clone <repository-url>
cd tf-aws-s3-efs-datasync
terraform init
```

### 2. Configure Variables (Optional)

```hcl
# variables.tf
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "s3-efs-datasync-replication"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}
```

### 3. Deploy Infrastructure

```bash
terraform plan
terraform apply
```

### 4. Test the Setup

```bash
# Get SSM connection details
terraform output ssm_connect

# Connect to EC2 instance via SSM
aws ssm start-session --target <instance-id> --region <region>

# On the EC2 instance, run the helper script
/home/ec2-user/check-datasync.sh
```

## 📊 Outputs

| Output | Description |
|--------|-------------|
| `s3_bucket_name` | Name of the S3 bucket |
| `efs_file_system_id` | ID of the EFS file system |
| `datasync_task_arn` | ARN of the DataSync task |
| `ec2_instance` | EC2 instance details |
| `ssm_connect` | SSM connection information |
| `vpc_endpoints` | VPC endpoint IDs |

## 🔧 Configuration

### DataSync Schedule

The DataSync task runs every hour by default. To modify:

```hcl
schedule {
  schedule_expression = "rate(1 hour)"  # Change as needed
}
```

### Available Schedule Options

- `rate(30 minutes)` - Every 30 minutes
- `rate(2 hours)` - Every 2 hours
- `cron(0 2 * * ? *)` - Daily at 2 AM
- `cron(0 9 ? * MON-FRI *)` - Weekdays at 9 AM

### EFS Performance

```hcl
performance_mode                = "generalPurpose"
throughput_mode                 = "provisioned"
provisioned_throughput_in_mibps = 100  # Adjust as needed
```

## 🔍 Monitoring

### CloudWatch Logs

- **DataSync Logs**: `/aws/datasync/s3-efs-datasync-replication-s3-to-efs`
- **EC2 Logs**: `/aws/ssm/` (for SSM sessions)

### DataSync Console

Monitor task execution history and status in the AWS DataSync console.

## 🧪 Testing

### 1. Upload Test Files to S3

```bash
# Upload a test file
aws s3 cp test-file.txt s3://<bucket-name>/

# Check DataSync execution
aws datasync list-task-executions --task-arn <task-arn>
```

### 2. Verify on EC2

```bash
# Connect via SSM
aws ssm start-session --target <instance-id>

# Check EFS mount
df -h /mnt/efs

# List replicated files
ls -la /mnt/efs/

# Run helper script
/home/ec2-user/check-datasync.sh
```

## 🛡️ Security

- **IAM Policies**: Separated read/write permissions for DataSync and EC2
- **Private Subnets**: EC2 and EFS in private subnets
- **VPC Endpoints**: Private access to AWS services
- **Security Groups**: Basic ingress/egress rules

## 💰 Cost Considerations

- Uses t3.micro EC2 instance
- Provisioned EFS throughput (100 MiB/s)
- VPC endpoints for private access
- CloudWatch logs with 1-day retention

## 🗑️ Cleanup

```bash
terraform destroy
```

**Note**: This will delete all resources including S3 bucket contents and EFS data.

## 📚 References

- [AWS DataSync Documentation](https://docs.aws.amazon.com/datasync/)
- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
