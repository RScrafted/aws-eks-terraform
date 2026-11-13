variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "aws_profile" {
  type = string
}

variable "project_name" {
  type    = string
  default = "eks"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_version" {
  type = string
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}
