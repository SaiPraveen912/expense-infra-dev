module "backend" {
    source  = "terraform-aws-modules/ec2-instance/aws"
    name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

    instance_type          = "t3.micro"
    vpc_security_group_ids = [data.aws_ssm_parameter.backend_sg_id.value]
    # convert StringList to list and get first element

    subnet_id              = local.private_subnet_id
    
    # we have seen how to get ami info from terraform-re/data-source/data.tf
    ami = data.aws_ami.ami_info.id
    tags = merge(
        var.common_tags,
        {
            Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
        }
    )
}

resource "null_resource" "backend" {
    triggers = {
      instance_id = module.backend.id # this will be triggered everytime instance is created
    }

    connection {
        type = "ssh"
        user = "ec2-user"
        password = "DevOps321"
        host = module.backend.private_ip
    }

    provisioner "file" {
        source      = "${var.common_tags.Component}.sh" # keep backend.sh file inside the server in tm directory
        destination = "/tmp/${var.common_tags.Component}.sh"
    }

    # to run the copied file we have to use remote exec
    provisioner "remote-exec" {    
        inline = [      
              "chmod +x /tmp/${var.common_tags.Component}.sh",  # given execution permission
              "sudo sh /tmp/${var.common_tags.Component}.sh ${var.common_tags.Component} ${var.environment}" 
        ]  
    }
  
}

resource "aws_ec2_instance_state" "backend" {
  instance_id = module.backend.id
  state       = "stopped"
  # stop the server only when null resource provisioning is completed
  depends_on = [ null_resource.backend ]
}

# Take AMI of the stopped server
resource "aws_ami_from_instance" "backend" {
  name               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  source_instance_id = module.backend.id
  depends_on = [ aws_ec2_instance_state.backend ]
}

# delete stopped ec2 instance after taking AMI
resource "null_resource" "backend_delete" {
    triggers = {
      instance_id = module.backend.id # this will be triggered everytime instance is created
    }

    connection {
        type = "ssh"
        user = "ec2-user"
        password = "DevOps321"
        host = module.backend.private_ip
    }


    # local exec because aws cli is installed here
    provisioner "local-exec" {    
        command = "aws ec2 terminate-instances --instance-ids ${module.backend.id}"
    }

    depends_on = [ aws_ami_from_instance.backend ]
  
}

# aws target group with health check
resource "aws_lb_target_group" "backend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value
  health_check {
    path                = "/health"
    port                = 8080
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# aws launch template creation
resource "aws_launch_template" "backend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  image_id = aws_ami_from_instance.backend.id

  # if traffic is less then terminate
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"
  update_default_version = true # sets the latest version to default

  vpc_security_group_ids = [data.aws_ssm_parameter.backend_sg_id.value]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
        var.common_tags,   
        {
            Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
        }   
    )
  }
}


# Create autoscaling group
resource "aws_autoscaling_group" "backend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1
  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.private_subnet_ids.value)

  instance_refresh {
    strategy = "Rolling" # One by one --> Create new one and delete old one
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"] # trigger after launch_template updates
  }


  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Project"
    value               = "${var.project_name}"
    propagate_at_launch = false
  }
}

# ASG policy using metric CPU utilization
resource "aws_autoscaling_policy" "backend" {
  name                   = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  policy_type            = "TargetTrackingScaling" 
  autoscaling_group_name = aws_autoscaling_group.backend.name

    target_tracking_configuration {
      predefined_metric_specification {
        predefined_metric_type = "ASGAverageCPUUtilization"
      }

      target_value = 10.0 # for testing purpose we are keeping 10, it need to be 75 or greater.
    }
}

# Load balancer listener rule --> backend.app-dev.daws-78s.cloud
resource "aws_lb_listener_rule" "backend" {
  listener_arn = data.aws_ssm_parameter.app_alb_listener_arn.value
  priority     = 100 # less number will be first validated

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  # we are writing rule on host path
  condition {
    host_header {
      values = ["backend.app-${var.environment}.${var.zone_name}"]  # this is host path
    }
  }
}
