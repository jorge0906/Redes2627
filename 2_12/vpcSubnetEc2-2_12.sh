#!/bin/bash

#Tarea 2_12 Redes
#Jorge Escrich Laorden

# Direccionamiento usado en el script
VPC_CIDR="172.16.0.0/16"
PUBLICSUBNET_CIDR="172.16.0.0/20"
PRIVATESUBNET_CIDR="172.16.64.0/20"

# IPs privadas de las instancias
EC2_PUBLIC_IP="172.16.0.100"
EC2_PRIVATE_IP="172.16.64.100"


AZ="us-east-1a"


#CREAR

# 1. VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
--query 'Vpc.VpcId' \
--tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Script-VPC},{Key=Type,Value=prueba}]' \
--output text)
echo "VPC: $VPC_ID"

#Dns support and DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

# 2. Subnet publica
SUBNET_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $PUBLICSUBNET_CIDR \
--availability-zone $AZ \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet-Public},{Key=Type,Value=prueba}]' \
--output text)
echo "Subnet publica: $SUBNET_ID ($AZ)"

# 3. Subnet privada
SUBNET_ID2=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $PRIVATESUBNET_CIDR \
--availability-zone $AZ \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet-Private},{Key=Type,Value=prueba}]' \
--output text)
echo "Subnet privada: $SUBNET_ID2 ($AZ)"

# 4. Internet Gateway y asociarlo a la VPC
IGW_ID=$(aws ec2 create-internet-gateway \
--query 'InternetGateway.InternetGatewayId' \
--tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Script-IGW},{Key=Type,Value=prueba}]' \
--output text)
echo "Internet Gateway: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# 5. Tabla de rutas PUBLICA: salida directa por el Internet Gateway
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId' \
--tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Script-RouteTable-Public},{Key=Type,Value=prueba}]' \
--output text)
echo "Tabla de rutas publica: $ROUTE_TABLE_ID"

aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID

aws ec2 associate-route-table \
--route-table-id $ROUTE_TABLE_ID \
--subnet-id $SUBNET_ID

# 6. NAT Gateway en la subnet publica
EIP_ALLOC_ID=$(aws ec2 allocate-address \
--domain vpc \
--query 'AllocationId' \
--tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=Script-EIP-NAT},{Key=Type,Value=prueba}]' \
--output text)
echo "Elastic IP Allocation ID: $EIP_ALLOC_ID"

NAT_GW_ID=$(aws ec2 create-nat-gateway \
--subnet-id $SUBNET_ID \
--allocation-id $EIP_ALLOC_ID \
--query 'NatGateway.NatGatewayId' \
--tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=Script-NATGW},{Key=Type,Value=prueba}]' \
--output text)
echo "NAT Gateway: $NAT_GW_ID"

echo "Esperando a que el NAT Gateway este disponible..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID

# 7. Tabla de rutas PRIVADA: salida a Internet a traves del NAT Gateway
ROUTE_TABLE_ID2=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId' \
--tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Script-RouteTable-Private},{Key=Type,Value=prueba}]' \
--output text)
echo "Tabla de rutas privada: $ROUTE_TABLE_ID2"

aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID2 \
--destination-cidr-block 0.0.0.0/0 \
--nat-gateway-id $NAT_GW_ID

aws ec2 associate-route-table \
--route-table-id $ROUTE_TABLE_ID2 \
--subnet-id $SUBNET_ID2

# 8. Security Group
SG_ID=$(aws ec2 create-security-group \
--group-name Script-SG \
--description "Security group for Script" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=Script-SG},{Key=Type,Value=prueba}]' \
--output text)
echo "Security Group: $SG_ID"

# SSH desde cualquier IP (para poder conectarnos a la instancia publica)
aws ec2 authorize-security-group-ingress \
--group-id $SG_ID \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0

# Comunicacion entre las dos instancias
aws ec2 authorize-security-group-ingress \
--group-id $SG_ID \
--protocol tcp \
--port 22 \
--source-group $SG_ID


aws ec2 authorize-security-group-ingress \
--group-id $SG_ID \
--protocol icmp \
--port -1 \
--source-group $SG_ID

# 9. Instancia EC2 de la subnet PUBLICA (con IP publica y salida por IGW)
INSTANCE_ID=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t3.micro \
--key-name vockey --subnet-id $SUBNET_ID \
--private-ip-address $EC2_PUBLIC_IP \
--associate-public-ip-address \
--security-group-ids $SG_ID \
--query 'Instances[0].InstanceId' \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance-Public},{Key=Type,Value=prueba}]' \
--output text)
echo "Instancia EC2 publica: $INSTANCE_ID (IP privada $EC2_PUBLIC_IP)"

# 10. Instancia EC2 de la subnet PRIVADA (sin IP publica, salida por NAT)
INSTANCE_ID2=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t3.micro \
--key-name vockey --subnet-id $SUBNET_ID2 \
--private-ip-address $EC2_PRIVATE_IP \
--security-group-ids $SG_ID \
--query 'Instances[0].InstanceId' \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance-Private},{Key=Type,Value=prueba}]' \
--output text)
echo "Instancia EC2 privada: $INSTANCE_ID2 (IP privada $EC2_PRIVATE_IP)"

# Esperar a que ambas esten en ejecucion
echo "Esperando a que las instancias esten running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID $INSTANCE_ID2

# Resumen final
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
--query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "===== RESUMEN ====="
echo "VPC:                  $VPC_ID ($VPC_CIDR)"
echo "Subnet publica:       $SUBNET_ID ($PUBLICSUBNET_CIDR) -> IGW $IGW_ID"
echo "Subnet privada:       $SUBNET_ID2 ($PRIVATESUBNET_CIDR) -> NAT $NAT_GW_ID"
echo "EC2 publica:          $INSTANCE_ID (privada $EC2_PUBLIC_IP / publica $PUBLIC_IP)"
echo "EC2 privada:          $INSTANCE_ID2 (privada $EC2_PRIVATE_IP, sin IP publica)"
echo ""

exit 0
