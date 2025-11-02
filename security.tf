# my ip
variable "my_ip" {
  description = "My public IP"
  type        = string
}

# first
resource "aws_security_group" "internet_facing_lb_sg"{
    name = "first_security_group"
    description = "this is for internet facing lb"
    vpc_id = aws_vpc.kjmyvpc.id

    ingress {
    
    description = "Allow HTTP from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]

    }
    tags = {
    Name = "internet_facing_lb_sg"
  }

}
# second
resource "aws_security_group" "web_sg" {
  name        = "web-tier-sg"
  description = "Allow HTTP from LB and my IP"
  vpc_id      = aws_vpc.kjmyvpc.id

  # HTTP from Load Balancer SG
  ingress {
    description              = "Allow HTTP from LB SG"
    from_port                = 80
    to_port                  = 80
    protocol                 = "tcp"
    security_groups          = [aws_security_group.internet_facing_lb_sg.id]
  }

  # HTTP from your IP
  ingress {
    description = "Allow HTTP from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Outbound: allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebTierSG"
  }
}
# third
resource "aws_security_group" "internal_lb_sg" {
  name        = "internal-load-balancer-sg"
  description = "Allow HTTP from web tier instances"
  vpc_id      = aws_vpc.kjmyvpc.id

  # Allow HTTP from Web Tier SG
  ingress {
    description       = "Allow HTTP from Web Tier SG"
    from_port         = 80
    to_port           = 80
    protocol          = "tcp"
    security_groups   = [aws_security_group.web_sg.id]
  }

  # Outbound: allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "InternalLoadBalancerSG"
  }
}
# fourth
resource "aws_security_group" "private_instances_sg" {
  name        = "private-instances-sg"
  description = "Allow app traffic on port 4000"
  vpc_id      = aws_vpc.kjmyvpc.id


  ingress {
    description       = "App traffic from Internal LB"
    from_port         = 4000
    to_port           = 4000
    protocol          = "tcp"
    security_groups   = [aws_security_group.internal_lb_sg.id]
  }

  ingress {
    description = "App traffic from my IP"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "PrivateInstancesSG"
  }
}
# fifth
resource "aws_security_group" "db_sg" {
  name        = "database-sg"
  description = "Allow DB access from private instances"
  vpc_id      = aws_vpc.kjmyvpc.id


  ingress {
    description       = "MySQL/Aurora from App tier"
    from_port         = 3306
    to_port           = 3306
    protocol          = "tcp"
    security_groups   = [aws_security_group.private_instances_sg.id]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DatabaseSG"
  }
}
