# Define provider
provider "aws" {
  region = "us-east-1" # Change this to your desired region
}


resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Save the private key to a local file
resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "${path.module}/private_key.pem"
}

# Save the public key to a local file
resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "${path.module}/public_key.pub"
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Create security group
resource "aws_security_group" "web" {
  name        = "web_sg"
  description = "Allow HTTP inbound traffic"

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
}

# Create IAM role for EC2 instance
resource "aws_iam_role" "ec2_role" {
  name               = "ec2_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach S3 read-only policy to IAM role
resource "aws_iam_role_policy_attachment" "s3_read_only" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_role" {
  name = "ec2-role"
  role =aws_iam_role.ec2_role.name
}

# Create launch configuration
resource "aws_launch_configuration" "web" {
  name_prefix          = "web_lc_"
  image_id             = "ami-051f8a213df8bc089" # Change this to your desired AMI
  instance_type        = "t2.micro" # Change this to your desired instance type
  key_name             = aws_key_pair.deployer.key_name # Optional: Uncomment if you want to use SSH key
  security_groups      = [aws_security_group.web.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_role.name
  user_data            = <<-EOF
                          #!/bin/bash
                          yum install -y httpd
                          systemctl start httpd
                          systemctl enable httpd
                          aws s3 cp s3://aws-test-rv/index.html /var/www/html/index.html
                          EOF
  lifecycle {
    create_before_destroy = true
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "web" {
  name                      = "web_asg"
  launch_configuration     = aws_launch_configuration.web.id
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  health_check_type         = "EC2"
  vpc_zone_identifier       = ["subnet-83d0b1ad"] # Change this to your desired subnet ID(s)
  depends_on = [ aws_s3_bucket.html_bucket, aws_s3_object.html_object ]
}


# Create ALB
resource "aws_lb" "web" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = ["subnet-83d0b1ad","subnet-a07d48ea"] # Change this to your desired subnet ID(s)
}

# Create ALB listener
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Create ALB target group
resource "aws_lb_target_group" "web" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-0866d072" # Change this to your desired VPC ID

  health_check {
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# Register targets (EC2 instances) with ALB target group
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web.name
  lb_target_group_arn   = aws_lb_target_group.web.arn
}

# Create S3 bucket
resource "aws_s3_bucket" "html_bucket" {
  bucket = "aws-test-rv" # Change this to your desired bucket name
  # acl    = "public-read"
}

# Upload HTML file to S3 bucket
resource "aws_s3_object" "html_object" {
  bucket = aws_s3_bucket.html_bucket.bucket
  key    = "index.html"
  source = "../code/index.html" # Change this to the path of your HTML file
}
