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
