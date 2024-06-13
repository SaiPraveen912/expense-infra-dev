module "bastion" {
    source  = "terraform-aws-modules/ec2-instance/aws"

    name = "${var.project_name}-${var.environment}-bastion"

    instance_type          = "t3.micro"
    vpc_security_group_ids = [data.aws_ssm_parameter.bastion_sg_id.value]
    # convert StringList to list and get first element

    subnet_id              = local.public_subnet_id
    
    # we have seen how to get ami info from terraform-re/data-source/data.tf
    ami = data.aws_ami.ami_info.id
    user_data = file("bastion.sh") # By default we wil install MySql here
    tags = merge(
        var.common_tags,
        {
            Name = "${var.project_name}-${var.environment}-bastion"
        }
    )
}