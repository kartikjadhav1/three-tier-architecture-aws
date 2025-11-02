# Subnet groups
resource "aws_db_subnet_group" "DB_subnet_group" {
  name        = "main-db-subnet-group"
  subnet_ids  = [
    aws_subnet.PrivateDBSubnetAZ1.id,
    aws_subnet.PrivateDBSubnetAZ2.id
  ]
  description = "Subnets for RDS instance"

  tags = {
    Name = "MainDBSubnetGroup"
  }
}



# DB
resource "aws_db_instance" "primary" {
  identifier              = "mydb-primary"
  engine                  = "mysql"
  engine_version          = "8.0.39"        
  instance_class          = "db.t3.micro"   
  allocated_storage       = 20              
  max_allocated_storage   = 30          
  username                = "admin"
  password                = "Admin1234!"
  db_subnet_group_name    = aws_db_subnet_group.DB_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  availability_zone       = "us-east-1a"
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az = false
  backup_retention_period = 7 
  apply_immediately       = true



  tags = {
    Name = "MySQL-Primary"
  }
}

# resource "aws_db_instance" "read_replica" {
#   identifier              = "mydb-replica"
#   replicate_source_db     = aws_db_instance.primary.arn
#   instance_class          = "db.t3.micro"
#   db_subnet_group_name    = aws_db_subnet_group.DB_subnet_group.name
#   vpc_security_group_ids  = [aws_security_group.db_sg.id]
#   publicly_accessible     = false
#   skip_final_snapshot     = true

#   tags = {
#     Name = "MySQL-Replica"
#   }
# }

locals {
  DbConfig_content = templatefile("${path.module}/DbConfig.tpl", {
    db_endpoint = aws_db_instance.primary.address
    db_username = aws_db_instance.primary.username
    db_password = aws_db_instance.primary.password
  })

  upload_files = [for f in fileset("${path.module}/app-tier", "**") : f if f != "DbConfig.js"]
}

resource "local_file" "DbConfig_js" {
  content  = local.DbConfig_content
  filename = "${path.module}/app-tier/DbConfig.js"
  depends_on = [aws_db_instance.primary]
}

resource "aws_s3_object" "upload_dbconfig" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "app-tier/DbConfig.js"
  source = "${path.module}/app-tier/DbConfig.js"
  depends_on = [local_file.DbConfig_js]
}

resource "aws_s3_object" "upload_app_tier" {
  for_each = { for file in local.upload_files : file => file }

  bucket = aws_s3_bucket.my_bucket.id
  key    = "app-tier/${each.key}"
  source = "${path.module}/app-tier/${each.key}"
  etag   = filemd5("${path.module}/app-tier/${each.key}")

  depends_on = [
    local_file.DbConfig_js
  ]
}
