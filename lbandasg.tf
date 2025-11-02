# APP-tier AMI

resource "time_sleep" "wait_for_user_data" {
  depends_on = [aws_instance.app_layer]
  create_duration = "60s"  
}

resource "aws_ami_from_instance" "app_layer_golden" {
  depends_on = [time_sleep.wait_for_user_data]
  
  name               = "AppLayer-Golden-AMI-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}"
  source_instance_id = aws_instance.app_layer.id
  description        = "Golden AMI for AppLayer Auto Scaling Group"
  
  snapshot_without_reboot = false  

  tags = {
    Name      = "AppLayer-Golden-AMI"
    CreatedBy = "Terraform"
    Source    = "app_layer_instance"
  }
}

resource "aws_launch_template" "app_layer_lt" {
  name_prefix   = "app-layer-lt-"
  description   = "Launch Template for App Layer using Golden AMI"
  image_id      = aws_ami_from_instance.app_layer_golden.id
  instance_type = "t2.micro"

  key_name = null

  vpc_security_group_ids = [aws_security_group.private_instances_sg.id]


  iam_instance_profile {
    name = aws_iam_instance_profile.app_instance_profile.name
  }
user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              
              exec > >(tee /var/log/app-startup.log)
              exec 2>&1
              
              echo "Starting application at $(date)"
              
              sudo -u ec2-user bash << 'USERSCRIPT'
              export NVM_DIR="/home/ec2-user/.nvm"
              [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
              
              cd /home/ec2-user/app-tier
              
              # Install PM2 if not present
              npm list -g pm2 || npm install -g pm2
              
              # Start app
              pm2 start index.js --name app-tier
              pm2 save
              USERSCRIPT
              
              # Set PM2 to start on boot
              sudo env PATH=$PATH:/home/ec2-user/.nvm/versions/node/v16.20.2/bin \
                /home/ec2-user/.nvm/versions/node/v16.20.2/lib/node_modules/pm2/bin/pm2 startup systemd \
                -u ec2-user --hp /home/ec2-user || true
              
              echo "Application started at $(date)"
              EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "AppLayer-From-LaunchTemplate"
    }
  }

  tags = {
    Name = "AppLayer-LaunchTemplate"
    CreatedBy = "Terraform"
  }

  depends_on = [
    aws_ami_from_instance.app_layer_golden
  ]
}

resource "aws_lb_target_group" "apptier_group" {
  name        = "apptiergroup"
  target_type = "instance"        
  port        = 4000              
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
    Name = "AppTier-TargetGroup"
  }
}


resource "aws_lb_listener" "app_lb_listener" {
  load_balancer_arn = aws_lb.app_tier_internal_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apptier_group.arn
  }
   depends_on = [
    aws_lb.app_tier_internal_lb,
    aws_lb_target_group.apptier_group
  ]
}

resource "aws_lb" "app_tier_internal_lb"{
    internal = true
    load_balancer_type = "application"
    security_groups = [aws_security_group.internal_lb_sg.id]
    subnets = [aws_subnet.PrivateAppSubnetAZ1.id,aws_subnet.PrivateAppSubnetAZ2.id]
  tags = {
    Name = "AppTier-Internal-LB"
  }
}    


resource "aws_autoscaling_group" "app_tier_asg" {
  name                      = "app-tier-asg"
  vpc_zone_identifier        = [
    aws_subnet.PrivateAppSubnetAZ1.id,
    aws_subnet.PrivateAppSubnetAZ2.id
  ]

  launch_template {
    id      = aws_launch_template.app_layer_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.apptier_group.arn]

  min_size             = 2
  max_size             = 2
  desired_capacity      = 2

  health_check_type     = "ELB"
  health_check_grace_period = 300  

  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "AppLayer-ASG-Instance"
    propagate_at_launch = true
  }

  depends_on = [
    aws_launch_template.app_layer_lt,
    aws_lb_target_group.apptier_group
  ]
}
