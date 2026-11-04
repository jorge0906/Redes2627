#!/bin/bash
# Elimina todos los recursos creados con la etiqueta Type=prueba
# (Instancia EC2, Security Group, Tabla de rutas, Internet Gateway, Subred y VPC)

echo "Buscando y eliminando recursos con la etiqueta Type=prueba..."

# 1. Buscar y eliminar la instancia EC2 por etiqueta
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
    for SUB_ID in $SUBNET_ID; do
        echo "Eliminando Subnet: $SUB_ID"
        aws ec2 delete-subnet --subnet-id $SUB_ID
    done
else
    echo "No se encontró ninguna Subnet con el tipo prueba."
fi

# 6. Buscar y eliminar la VPC por etiqueta
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Type,Values=prueba" \
    --query "Vpcs[].VpcId" \
    --output text)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    for VPC in $VPC_ID; do
        echo "Eliminando VPC: $VPC"
        for intento in 1 2 3 4 5; do
            aws ec2 delete-vpc --vpc-id $VPC && break
            echo "Reintentando en 5 segundos..."
            sleep 5
        done
    done
else
    echo "No se encontró ninguna VPC con el tipo prueba."
fi

echo "Proceso completado."
exit 0
