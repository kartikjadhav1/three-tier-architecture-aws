data "template_file" "nginx_conf" {
  template = file("${path.module}/nginx.conf")

  vars = {
    INTERNAL_LB_DNS = aws_lb.app_tier_internal_lb.dns_name
  }
}

resource "aws_s3_object" "upload_nginx_conf" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "nginx.conf"
  content = data.template_file.nginx_conf.rendered
  etag   = md5(data.template_file.nginx_conf.rendered)
}

resource "aws_s3_object" "upload_web_tier" {
  for_each = fileset("${path.module}/web-tier", "**")
  bucket   = aws_s3_bucket.my_bucket.id
  key      = "web-tier/${each.value}"
  source   = "${path.module}/web-tier/${each.value}"
  etag     = filemd5("${path.module}/web-tier/${each.value}")
}

resource "aws_instance" "web_tier" {
    depends_on = [ aws_s3_object.upload_web_tier,aws_s3_object.upload_nginx_conf ]
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.micro"

  subnet_id = aws_subnet.PublicWebSubnetAZ1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  key_name = null  
  associate_public_ip_address = true 

  iam_instance_profile = aws_iam_instance_profile.app_instance_profile.name
    user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Log everything
              exec > >(tee /var/log/user-data.log)
              exec 2>&1
              
              echo "Starting Web Tier setup at $(date)"

              # Run as ec2-user
              sudo -u ec2-user bash << 'USERSCRIPT'
              set -e
              
              # Install NVM
              curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
              source ~/.bashrc
              
              # Install and use Node.js 16
              export NVM_DIR="$HOME/.nvm"
              [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
              nvm install 16
              nvm use 16
              
              # Download web-tier from S3
              cd ~/
              aws s3 cp s3://kj-mybucket-98890/web-tier/ web-tier --recursive
              
              # Build the React app
              cd ~/web-tier
              npm install
              npm run build
              
              USERSCRIPT

              # Install nginx
              sudo amazon-linux-extras install nginx1 -y
              
              # Configure nginx
              cd /etc/nginx
              sudo rm -f nginx.conf
              sudo aws s3 cp s3://kj-mybucket-98890/nginx.conf .
              
              # Set permissions and start nginx
              chmod -R 755 /home/ec2-user
              sudo chkconfig nginx on
              sudo service nginx restart
              
              echo "Web Tier setup completed at $(date)"
              touch /tmp/user-data-complete
              EOF


    
   tags = {
    Name = "WebTier-Instance"
  }
}

resource "time_sleep" "wait_for_user_data_WEB" {
  depends_on = [aws_instance.web_tier]
  create_duration = "60s"  
}

resource "aws_ami_from_instance" "Web_tier_AMI" {
  depends_on = [time_sleep.wait_for_user_data_WEB]
  name               = "Web-Tier-AMI-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}"
  source_instance_id = aws_instance.web_tier.id
  description        = "Golden AMI for web-tier Auto Scaling Group"
  snapshot_without_reboot = false  

  tags = {
    Name      = "Web-Tier-AMI"
  }
}

resource "aws_lb_target_group" "Web_Tier_Target_group" {
  name        = "WebTierGroup"
  target_type = "instance"        
  port        = 80            
  protocol    = "HTTP"
  vpc_id      = aws_vpc.kjmyvpc.id   

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"  
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name = "WebTier-TargetGroup"
  }
}

resource "aws_lb_listener" "web_lb_listener" {
  load_balancer_arn = aws_lb.web_tier_internet_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.Web_Tier_Target_group.arn
  }
   depends_on = [
    aws_lb.web_tier_internet_lb,
    aws_lb_target_group.Web_Tier_Target_group
  ]
}

resource "aws_lb" "web_tier_internet_lb"{
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.internet_facing_lb_sg.id]
    subnets = [aws_subnet.PublicWebSubnetAZ1.id,aws_subnet.PublicWebSubnetAZ2.id]
  tags = {
    Name = "WebTier-Internal-LB"
  }
}   


resource "aws_launch_template" "web_tier_lt" {
  name_prefix   = "web-layer-lt-"
  description   = "Launch Template for Web Layer using web AMI"
  image_id      = aws_ami_from_instance.Web_tier_AMI.id
  instance_type = "t2.micro"

  key_name = null

  vpc_security_group_ids = [aws_security_group.web_sg.id]


  iam_instance_profile {
    name = aws_iam_instance_profile.app_instance_profile.name
  }
user_data = base64encode(<<-EOF
#!bin/bash
set -e

exec > >(tee /var/log/web-startup.log)
exec 2>&1

echo "Starting Web Tier from AMI at $(date)"

sudo sed -i 's|proxy_pass http://.*:80/;|proxy_pass http://${aws_lb.app_tier_internal_lb.dns_name}:80/;|g' /etc/nginx/nginx.conf

sudo service nginx restart

sudo service nginx status

echo "Web Tier startup completed at $(date)"

EOF
)

}



resource "aws_autoscaling_group" "WEb-Tier_asg" {
  name                      = "web-tier-asg"
  vpc_zone_identifier        = [
    aws_subnet.PublicWebSubnetAZ1.id,
    aws_subnet.PublicWebSubnetAZ2.id
  ]

  launch_template {
    id      = aws_launch_template.web_tier_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.Web_Tier_Target_group.arn]

  min_size             = 2
  max_size             = 2
  desired_capacity      = 2

  health_check_type     = "ELB"
  health_check_grace_period = 300  

  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "Web-Layer-ASG-Instance"
    propagate_at_launch = true
  }

  depends_on = [
    aws_launch_template.web_tier_lt,
    aws_lb_target_group.Web_Tier_Target_group
  ]
}
