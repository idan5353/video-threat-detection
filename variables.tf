variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "video-threat-detection"
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "min_confidence_threshold" {
  description = "Minimum confidence threshold for threat detection"
  type        = number
  default     = 80
}

variable "notification_email" {
  description = "Email address for threat notifications"
  type        = string
  default     = ""
}
