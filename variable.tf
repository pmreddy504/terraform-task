variable "web_vpc_cidr" {
  description = "CIDR block for the web VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "web_vpc_public_subnets" {
  description = "public subnets for the web VPC."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
variable "web_vpc_private_subnets" {
  description = "private subnets for the web VPC."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "db_vpc_cidr" {
  description = "CIDR block for the web VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "db_vpc_public_subnets" {
  description = "public subnets for the web VPC."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "db_vpc_private_subnets" {
  description = "private subnets for the web VPC."
  type        = list(string)
  default     = ["10.1.3.0/24", "10.1.4.0/24", "10.1.5.0/24", "10.1.6.0/24"]
}

variable "ami" {
  description = "Amazon Machine Image ID"
  default     = "ami-02eb7a4783e7e9317"
}

variable "instance_type" {
  description = "EC2 Instance Type"
  default     = "t2.small"
}

