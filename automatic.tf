#providing the details for login
provider "aws" {
  region                  = "ap-south-1"
  profile                 = "myterraform"
}

#creating key pair_publically and privately
resource "tls_private_key" "terraform_key" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}

#creating private key
resource "local_file" "private_key" {
    depends_on = [tls_private_key.terraform_key]
    content         =  tls_private_key.terraform_key.private_key_pem
    filename        =  "keyforterraform.pem"
    file_permission =  0400
}

#creating the public key
resource "aws_key_pair" "webserver_key" {
    depends_on = [local_file.private_key]
    key_name   = "keyforterraform"
    public_key = tls_private_key.terraform_key.public_key_openssh
}





#creating the security group and its rules
resource "aws_security_group" "webserver_firewall" {
    name        = "firewall"
    description = "https, ssh, icmp"
 ingress {
        description = "http"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "ssh"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
 ingress {
        description = "ping-icmp"
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
 egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
 tags = {
        Name = "firewallwebserver"
    }
}



#creating s3 bucket and downloading git code in local system
resource "aws_s3_bucket" "bucket1" {
  depends_on = [aws_security_group.webserver_firewall]
  bucket = "this-bucket-is-for-terraform"
  acl    = "public-read"
  force_destroy = true
  provisioner "local-exec" {
    command = "git clone https://github.com/akhilsukhnani/imageforwebserver.git image_webserver"
  }
}



#adding objects to the bukcet we have created
resource "aws_s3_bucket_object" "image_upload" {
    depends_on = [aws_s3_bucket.bucket1]
    bucket  = aws_s3_bucket.bucket1.bucket
    key     = "ricknmorty.jpg"
    source  = "C:/Users/akhil/Desktop/terraform/task1fullyautomated/image_webserver/ricky-morty-s4-hero.jpg"
    acl     = "public-read"
}



#creating the cloudfront 
resource "aws_cloudfront_distribution" "s3_cloudfront" {
    enabled       = true 
    viewer_certificate {
    cloudfront_default_certificate = true
     }
    
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "s3-thisbucketisforterraform"
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }    

     
    restrictions {
        geo_restriction {
        restriction_type = "none"
        }
     }

    origin {
    domain_name = "${aws_s3_bucket.bucket1.bucket_domain_name}"
    origin_id   = "s3-thisbucketisforterraform"
         }
}



#creating the instance
resource "aws_instance" "inst1" {
  depends_on = [aws_cloudfront_distribution.s3_cloudfront]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.webserver_key.key_name
  security_groups = [ "firewall" ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.terraform_key.private_key_pem
    host     = aws_instance.inst1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"   
 ]
  }
  tags = {
    Name = "automated web server"
  }
}


#creating the volume
resource "aws_ebs_volume" "vol1" {
  depends_on = [aws_instance.inst1]
  availability_zone = aws_instance.inst1.availability_zone
  size              = 1
  
  tags = {
    Name = "pendrive"
  }
}


#attaching the volume that we have created
resource "aws_volume_attachment" "vol-attach1" {
  depends_on = [aws_ebs_volume.vol1]
  device_name = "/dev/sdh"
  volume_id   =  "${aws_ebs_volume.vol1.id}"
  instance_id =  "${aws_instance.inst1.id}"
  force_detach = true	
}


#creating the null resource for mounting adn downloading the contents from github
resource "null_resource" "mounting_downloading" {
  depends_on = [aws_volume_attachment.vol-attach1]
  connection {
        type     = "ssh"
        user     = "ec2-user"
        private_key = tls_private_key.terraform_key.private_key_pem
        host     = aws_instance.inst1.public_ip
     }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html ",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/akhilsukhnani/we_r-automating_terraform.git   /var/www/html/"   
 ]
  }
  
  }



#success message and storing the result in a file
resource "null_resource" "storing_ip_in_a_file" {
    depends_on = [null_resource.mounting_downloading]
    provisioner "local-exec" {
    command = "echo the website ran successfully and >> result.txt  && echo the ip of the website is  ${aws_instance.inst1.public_ip} >>result.txt"
  }
}

#after the completion of every step running the website
resource "null_resource" "running_the_website" {
    depends_on = [null_resource.storing_ip_in_a_file]
    provisioner "local-exec" {
    command = "chrome ${aws_instance.inst1.public_ip}"
  }
}

