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