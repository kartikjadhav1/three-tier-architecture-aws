# vpc
resource "aws_vpc" "kjmyvpc" {
  cidr_block = "10.10.0.0/16"
}
resource "aws_internet_gateway" "kj_igw01" {
  vpc_id = aws_vpc.kjmyvpc.id
}
# Public Route table for 2 subnet associations
resource "aws_route_table" "PublicRouteTable"{
    vpc_id = aws_vpc.kjmyvpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.kj_igw01.id
    }
}
# Route table associations
resource "aws_route_table_association" "pub_sub_assoc_az1" {
  subnet_id = aws_subnet.PublicWebSubnetAZ1.id
  route_table_id = aws_route_table.PublicRouteTable.id
}
resource "aws_route_table_association" "pub_sub_assoc_az2" {
  subnet_id = aws_subnet.PublicWebSubnetAZ2.id
  route_table_id = aws_route_table.PublicRouteTable.id
}
# AZ 1
resource "aws_subnet" "PublicWebSubnetAZ1" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
}
# Elastic Ip AZ 1
resource "aws_eip" "nat_eip_AZ1" {
  domain = "vpc"
}
# Nat gateway AZ 1
resource "aws_nat_gateway" "nat_gw_AZ1"{
  allocation_id = aws_eip.nat_eip_AZ1.id
  subnet_id = aws_subnet.PublicWebSubnetAZ1.id
  depends_on = [aws_internet_gateway.kj_igw01]
}
# Private Route table AZ 2
resource "aws_route_table" "custom_priv_table_AZ1" {
  vpc_id = aws_vpc.kjmyvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_AZ1.id
  }
}
# Private route table association
resource "aws_route_table_association" "priv_sub_assoc_AZ1" {
  subnet_id = aws_subnet.PrivateAppSubnetAZ1.id
  route_table_id = aws_route_table.custom_priv_table_AZ1.id
}
resource "aws_subnet" "PrivateAppSubnetAZ1" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1a"
}
resource "aws_subnet" "PrivateDBSubnetAZ1" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-1a"
}

# AZ 2
resource "aws_subnet" "PublicWebSubnetAZ2" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"

}
# Elastic Ip
resource "aws_eip" "nat_eip_AZ2" {
  domain = "vpc"
}
# Nat gateway AZ2
resource "aws_nat_gateway" "nat_gw_AZ2"{
  allocation_id = aws_eip.nat_eip_AZ2.id
  subnet_id = aws_subnet.PublicWebSubnetAZ2.id
  depends_on = [aws_internet_gateway.kj_igw01]

}
# Private Route table AZ 2
resource "aws_route_table" "custom_priv_table_AZ2" {
  vpc_id = aws_vpc.kjmyvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw_AZ2.id
  }
}
# Private route table association
resource "aws_route_table_association" "priv_sub_assoc_AZ2" {
  subnet_id = aws_subnet.PrivateAppSubnetAZ2.id
  route_table_id = aws_route_table.custom_priv_table_AZ2.id
}
resource "aws_subnet" "PrivateAppSubnetAZ2" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.5.0/24"
  availability_zone = "us-east-1b"
}
resource "aws_subnet" "PrivateDBSubnetAZ2" {
  vpc_id            = aws_vpc.kjmyvpc.id
  cidr_block        = "10.10.6.0/24"
  availability_zone = "us-east-1b"
}
