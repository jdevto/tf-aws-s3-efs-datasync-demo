# =============================================================================
# OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.this.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "sample_file" {
  description = "Sample file created in S3 for replication demo"
  value = {
    file_name = aws_s3_object.this.key
    bucket    = aws_s3_bucket.this.bucket
    s3_url    = "s3://${aws_s3_bucket.this.bucket}/${aws_s3_object.this.key}"
  }
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.this.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.this.arn
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.this.dns_name
}


output "datasync_task_arn" {
  description = "ARN of the DataSync task"
  value       = aws_datasync_task.this.arn
}

output "datasync_task_name" {
  description = "Name of the DataSync task"
  value       = aws_datasync_task.this.name
}

output "datasync_schedule" {
  description = "DataSync scheduling information"
  value = {
    schedule_expression = "rate(1 hour)"
    enabled             = true
  }
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group for DataSync"
  value = {
    name = aws_cloudwatch_log_group.datasync.name
    arn  = aws_cloudwatch_log_group.datasync.arn
  }
}

output "ec2_instance" {
  description = "EC2 instance for EFS testing"
  value = {
    instance_id = aws_instance.this.id
    private_ip  = aws_instance.this.private_ip
    subnet_id   = aws_instance.this.subnet_id
    mount_point = "/mnt/efs"
  }
}

output "ssm_connect" {
  description = "SSM Connect information for EC2 instance"
  value = {
    instance_id = aws_instance.this.id
    region      = data.aws_region.current.region
    connect_url = "https://${data.aws_region.current.region}.console.aws.amazon.com/systems-manager/session-manager/${aws_instance.this.id}"
    aws_cli_cmd = "aws ssm start-session --target ${aws_instance.this.id} --region ${data.aws_region.current.region}"
  }
}

output "vpc_endpoints" {
  description = "VPC endpoints created for private traffic"
  value = {
    s3       = aws_vpc_endpoint.s3.id
    efs      = aws_vpc_endpoint.efs.id
    datasync = aws_vpc_endpoint.datasync.id
    sts      = aws_vpc_endpoint.sts.id
    logs     = aws_vpc_endpoint.logs.id
    ssm      = aws_vpc_endpoint.ssm.id
  }
}
