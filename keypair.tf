# resource "aws_key_pair" "my_key" {
#   key_name   = "my-key"
#   public_key = file("~/.ssh/my-key.pub")
# }
# Iam for
data "aws_iam_role" "s3_read_role" {
  name = "3TierEc2-S3Role"
}

# Create an Instance Profile for EC2 to assume that IAM role
resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "AppLayerInstanceProfile"
  role = data.aws_iam_role.s3_read_role.name
}