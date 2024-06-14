variable "project_name" {
    default = "expense"
}

variable "environment" {
    default = "dev"
}

variable "common_tags" {
    default = {
        Project = "expense"
        Environment = "dev"
        Terraform = true
        Component = "web-alb" # Useful for billing --> Individual component making how much bill
    } 
}

variable "zone_name" {
    default = "daws-78s.cloud"
  
}