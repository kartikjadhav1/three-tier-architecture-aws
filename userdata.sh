#!/bin/bash
set -e

DB_ENDPOINT="${db_endpoint}"  # from Terraform

# Run as root
yum update -y
yum install -y mysql

# Database setup
mysql -h $DB_ENDPOINT -u admin -pAdmin1234! <<SQL_COMMANDS
CREATE DATABASE IF NOT EXISTS webappdb;
USE webappdb;
CREATE TABLE IF NOT EXISTS transactions(
  id INT NOT NULL AUTO_INCREMENT,
  amount DECIMAL(10,2),
  description VARCHAR(100),
  PRIMARY KEY(id)
);
INSERT INTO transactions (amount, description) VALUES (400, 'groceries');
SQL_COMMANDS

# Switch to ec2-user for Node/NVM/PM2 installation
sudo -u ec2-user bash << 'EOF'
# Install NVM as ec2-user
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node.js
nvm install 16
nvm use 16

# Install PM2
npm install -g pm2

# Download application
cd /home/ec2-user
aws s3 cp s3://kj-mybucket-98890/app-tier/ app-tier --recursive

# Install dependencies
cd /home/ec2-user/app-tier
npm install

# Start with PM2
pm2 start index.js
pm2 save

# Setup PM2 startup
pm2 startup systemd -u ec2-user --hp /home/ec2-user
EOF

# Execute the PM2 startup command (as root)
env PATH=$PATH:/home/ec2-user/.nvm/versions/node/v16.20.2/bin /home/ec2-user/.nvm/versions/node/v16.20.2/lib/node_modules/pm2/bin/pm2 startup systemd -u ec2-user --hp /home/ec2-user

# Save PM2 process list as ec2-user
sudo -u ec2-user bash << 'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
pm2 save
EOF