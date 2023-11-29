# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

# Create a new VPC
resource "aws_vpc" "custom_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "custom_vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "custom_gateway"
  }
}

# Create a Custom Route Table
resource "aws_route_table" "custom_route_table" {
  vpc_id = aws_vpc.custom_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "custom_route_table"
  }
}

# Create a Subnet
resource "aws_subnet" "custom_subnet" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true  # Ensures instances launched in this subnet receive a public IP

  tags = {
    Name = "custom_subnet"
  }
}

# Create an Additional Subnet in a different Availability Zone
resource "aws_subnet" "custom_subnet_2" {
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = "10.0.2.0/24"  # Make sure the CIDR block is different
  availability_zone = "us-east-1b"   # Different Availability Zone
  map_public_ip_on_launch = true

  tags = {
    Name = "custom_subnet_2"
  }
}


# Associate Subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.custom_subnet.id
  route_table_id = aws_route_table.custom_route_table.id
}

# Create a Security Group
resource "aws_security_group" "example" {
  name = "example"
  vpc_id = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "example"
  }
}

# Create a Network Interface
resource "aws_network_interface" "web_nic" {
  subnet_id   = aws_subnet.custom_subnet.id
  private_ips = ["10.0.1.50"]
  security_groups = [aws_security_group.example.id]

  tags = {
    Name = "web_nic"
  }
}

# Assign an Elastic IP to the Network Interface
resource "aws_eip" "web_eip" {
  vpc = true  # Deprecated, but kept for compatibility
  network_interface = aws_network_interface.web_nic.id
  associate_with_private_ip = "10.0.1.50"

  tags = {
    Name = "web_eip"
  }
}

# Create multiple AWS EC2 Instances
resource "aws_instance" "example" {
  count                  = 3  # Number of instances to create
  ami                    = "ami-0fc5d935ebf8bc3bc"  # Replace with Ubuntu AMI ID
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.custom_subnet.id
  vpc_security_group_ids = [aws_security_group.example.id]

  user_data = <<-EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
echo "<h1>Hello World from Instance ${count.index + 1}</h1>" | sudo tee /var/www/html/index.html
EOF

  tags = {
    Name = "WorkshopInstance-${count.index}"
  }
}

# Output the Public IP Addresses
output "instance_public_ips" {
  value = [for instance in aws_instance.example : instance.public_ip]
}

# Application Load Balancer
resource "aws_lb" "example_alb" {
  name               = "example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example.id]
  subnets            = [aws_subnet.custom_subnet.id, aws_subnet.custom_subnet_2.id]  # Include both subnets

  enable_deletion_protection = false

  tags = {
    Name = "example-alb"
  }
}


# Target Group
resource "aws_lb_target_group" "example_tg" {
  name     = "example-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
  }

  tags = {
    Name = "example-tg"
  }
}

# Listener
resource "aws_lb_listener" "example_listener" {
  load_balancer_arn = aws_lb.example_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_tg.arn
  }
}

# Register Instances with Target Group
resource "aws_lb_target_group_attachment" "example_tga" {
  count            = length(aws_instance.example.*.id)
  target_group_arn = aws_lb_target_group.example_tg.arn
  target_id        = aws_instance.example[count.index].id
  port             = 80
}

# Output Load Balancer DNS Name
output "alb_dns_name" {
  value = aws_lb.example_alb.dns_name
}
