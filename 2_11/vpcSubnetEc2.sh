#!/bin/bash

#Tarea 2_11 Redes
#Jorge Escrich Laorden

# Direccionamiento usado en el script
VPC_CIDR="172.16.0.0/16"
SUBNET_CIDR="172.16.0.0/20"
EC2_PRIVATE_IP="172.16.0.100"
# Zona de disponibilidad donde se crea la subnet (y por tanto la instancia)
AZ="us-east-1a"

echo "Menú de opciones:"
echo "1 Eliminar VPC, Subnet, tabla de rutas, gateway e Instancia EC2"
echo "2 Crear VPC, Subnet, tabla de rutas, gateway e Instancia EC2"
echo "Ingrese el número de la opción que desea ejecutar (1 o 2):"
read opcion

if [ "$opcion" != "1" ] && [ "$opcion" != "2" ]; then
    echo "Opción inválida. Por favor, elija 1 o 2."
    exit 1
fi


if [ $opcion -eq 1 ]; then
    
# OPCIÓN 1: ELIMINAR 
echo "Buscando y eliminando recursos por etiqueta..."

# 1. Buscar y eliminar la instancia EC2 por tipo prueba
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=prueba" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    echo "Terminando instancia EC2: $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null 2>&1
    echo "Esperando a que la instancia se termine por completo..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID > /dev/null 2>&1
else
    echo "No se encontró ninguna instancia activa con el tipo prueba."
fi

# 2. Buscar y eliminar el Security Group por etiqueta
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Type,Values=prueba" \
    --query "SecurityGroups[].GroupId" \
    --output text)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo "Eliminando Security Group: $SG_ID"
    # El grupo puede tardar unos segundos en liberarse al terminar la instancia
    for intento in 1 2 3 4 5; do
        aws ec2 delete-security-group --group-id $SG_ID && break
        echo "Reintentando en 5 segundos..."
        sleep 5
    done
else
    echo "No se encontró ningún Security Group con el tipo prueba."
fi

# 3. Buscar y eliminar las tablas de rutas por etiqueta
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Type,Values=prueba" \
    --query "RouteTables[].RouteTableId" \
    --output text)

if [ -n "$ROUTE_TABLE_IDS" ] && [ "$ROUTE_TABLE_IDS" != "None" ]; then
    for RT_ID in $ROUTE_TABLE_IDS; do
        echo "Procesando tabla de rutas: $RT_ID"

        # Desasociar la tabla de rutas de la subred (la asociación principal no se toca)
        ASSOC_IDS=$(aws ec2 describe-route-tables \
            --route-table-ids $RT_ID \
            --query "RouteTables[].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text)

        for ASSOC_ID in $ASSOC_IDS; do
            echo " Desasociando $ASSOC_ID"
            aws ec2 disassociate-route-table --association-id $ASSOC_ID
        done

        echo " Eliminando tabla de rutas: $RT_ID"
        aws ec2 delete-route-table --route-table-id $RT_ID
    done
else
    echo "No se encontró ninguna tabla de rutas con el tipo prueba."
fi

# 4. Buscar, desasociar y eliminar el Internet Gateway por etiqueta
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Type,Values=prueba" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text)

if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    for GW_ID in $IGW_ID; do
        VPC_ATTACHED=$(aws ec2 describe-internet-gateways \
            --internet-gateway-ids $GW_ID \
            --query "InternetGateways[].Attachments[].VpcId" \
            --output text)

        if [ -n "$VPC_ATTACHED" ] && [ "$VPC_ATTACHED" != "None" ]; then
            echo "Desasociando Internet Gateway $GW_ID de la VPC $VPC_ATTACHED"
            aws ec2 detach-internet-gateway --internet-gateway-id $GW_ID --vpc-id $VPC_ATTACHED
        fi

        echo "Eliminando Internet Gateway: $GW_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id $GW_ID
    done
else
    echo "No se encontró ningún Internet Gateway con el tipo prueba."
fi

# 5. Buscar y eliminar la Subnet por etiqueta
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Subnets[].SubnetId" \
    --output text)

if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ]; then
    echo "Eliminando Subnet: $SUBNET_ID"
    aws ec2 delete-subnet --subnet-id $SUBNET_ID
else
    echo "No se encontró ninguna Subnet con el tipo prueba."
fi

# 6. Buscar y eliminar la VPC por etiqueta
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Vpcs[].VpcId" \
    --output text)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo "Eliminando VPC: $VPC_ID"
    for intento in 1 2 3 4 5; do
        aws ec2 delete-vpc --vpc-id $VPC_ID && break
        echo "Reintentando en 5 segundos..."
        sleep 5
    done
else
    echo "No se encontró ninguna VPC con el tipo prueba."
fi

fi



#OPCIÓN 2: CREAR 

if [ $opcion -eq 2 ]; then
    echo "Creando VPC, Subnet, Gateway, Tabla de rutas e Instancia EC2"



VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
--query 'Vpc.VpcId' \
--tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Script-VPC},{Key=Type,Value=prueba}]' \
--output text) 
echo "VPC: $VPC_ID"

#Dns support and DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

#Crear Subnet
SUBNET_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $SUBNET_CIDR \
--availability-zone $AZ \
--query 'Subnet.SubnetId' \
--tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Script-Subnet},{Key=Type,Value=prueba}]' \
--output text) 
echo "Subnet: $SUBNET_ID ($AZ)"

# Crear Internet Gateway y asociarlo a la VPC
IGW_ID=$(aws ec2 create-internet-gateway \
--query 'InternetGateway.InternetGatewayId' \
--tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Script-IGW},{Key=Type,Value=prueba}]' \
--output text)
echo "Internet Gateway: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Crear tabla de rutas y asociarla a la subnet
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--query 'RouteTable.RouteTableId' \
--tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Script-RouteTable},{Key=Type,Value=prueba}]' \
--output text)
echo "Tabla de rutas: $ROUTE_TABLE_ID"

# Ruta por defecto hacia el Internet Gateway
aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID

# Asociar la tabla de rutas a la subnet
aws ec2 associate-route-table \
--route-table-id $ROUTE_TABLE_ID \
--subnet-id $SUBNET_ID


# Crear Security Group
SG_ID=$(aws ec2 create-security-group \
--group-name Script-SG \
--description "Security group for Script" \
--vpc-id $VPC_ID \
--query 'GroupId' \
--tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=Script-SG},{Key=Type,Value=prueba}]' \
--output text)
echo "Security Group: $SG_ID"

aws ec2 authorize-security-group-ingress \
--group-id $SG_ID \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0 


#Crear intancia EC2
INSTANCE_ID=$(aws ec2 run-instances \
--image-id ami-0b6d9d3d33ba97d99 \
--count 1 --instance-type t2.micro \
--key-name vockey --subnet-id $SUBNET_ID \
--private-ip-address $EC2_PRIVATE_IP \
--query 'Instances[0].InstanceId' \
--associate-public-ip-address \
--security-group-ids $SG_ID \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Script-Instance},{Key=Type,Value=prueba}]' \
--output text) 
echo "Instancia EC2: $INSTANCE_ID (IP privada $EC2_PRIVATE_IP)"




fi

exit 0
