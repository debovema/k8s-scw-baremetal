variable "docker_version" {
  default     = "17.03.0~ce-0~ubuntu-xenial"
  description = "Use 17.12.0~ce-0~ubuntu for x86_64 and 17.03.0~ce-0~ubuntu-xenial for arm"
}

variable "k8s_version" {
  default = "stable-1.11"
}

variable "weave_passwd" {
  default = "ChangeMe"
}

variable "arch" {
  default     = "arm"
  description = "Values: arm arm64 x86_64"
}

variable "region" {
  default     = "par1"
  description = "Values: par1 ams1"
}

variable "server_type" {
  default     = "C1"
  description = "Use C1 for arm, ARM64-2GB for arm64 and C2S for x86_64"
}

variable "server_type_node" {
  default     = "C1"
  description = "Use C1 for arm, ARM64-2GB for arm64 and C2S for x86_64"
}

variable "masters_count" {
  default = 1
}

variable "nodes_count" {
  default = 2
}

variable "ip_admin" {
  type        = "list"
  default     = ["0.0.0.0/0"]
  description = "IP access to services"
}

variable "private_key" {
  type        = "string"
  default     = "~/.ssh/id_rsa"
  description = "The path to your private key"
}

variable "lb_enabled" {
  type        = "string"
  default     = "false"
  description = "Whether to enable load balancing feature or not"
}

variable "lb_name" {
  type        = "string"
  default     = "scaleway-lb"
  description = "Name of the Scaleway Load Balancer"
}

variable "traefik_version" {
  type        = "string"
  default     = "v1.7.6"
  description = "The Docker image version for Traefik load balancer"
}

variable "domain_name" {
  type        = "string"
}
