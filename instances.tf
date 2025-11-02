# Dynamic Amazon Linux 2 AMI lookup
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] 
}

# App Layer EC2 Instance
resource "aws_instance" "app_layer" {
  depends_on = [aws_db_instance.primary,
      aws_s3_object.upload_dbconfig,
    aws_s3_object.upload_app_tier] 
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.PrivateAppSubnetAZ1.id
  vpc_security_group_ids = [aws_security_group.private_instances_sg.id]

  key_name = null 
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.app_instance_profile.name
  user_data = templatefile("${path.module}/userdata.sh", {
    db_endpoint = aws_db_instance.primary.address
    db_user     = aws_db_instance.primary.username
    db_pass     = aws_db_instance.primary.password
})

  tags = {
    Name = "AppLayer"
  }
}