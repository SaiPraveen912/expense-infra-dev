resource "aws_key_pair" "vpn" {
  key_name   = "openvpn"
  # you can paste public key directly like this
  # public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ/5S5cxNCVkmEYl39Ee75iRk4/GPgejuXn0j9RWS4v6 saipr@SaiPraveen"
  public_key = file("~/.ssh/openvpn.pub")
  # ~ means windows home dierectory
}

module "vpn" {
    source  = "terraform-aws-modules/ec2-instance/aws"
    key_name = aws_key_pair.vpn.key_name
    name = "${var.project_name}-${var.environment}-vpn"

    instance_type          = "t3.micro"
    vpc_security_group_ids = [data.aws_ssm_parameter.vpn_sg_id.value]
    # convert StringList to list and get first element

    subnet_id              = local.public_subnet_id
    
    # we have seen how to get ami info from terraform-re/data-source/data.tf
    ami = data.aws_ami.ami_info.id
    tags = merge(
        var.common_tags,
        {
            Name = "${var.project_name}-${var.environment}-vpn"
        }
    )
}