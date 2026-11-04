import boto3

def crear_vpc():
    # Crear cliente de EC2
    ec2 = boto3.client('ec2')

    # Crear la VPC
    vpc = ec2.create_vpc(CidrBlock='193.168.5.0/16')
    vpc_id = vpc['Vpc']['VpcId']
    print(f"✅ VPC creada con ID: {vpc_id}")

    # Habilitar DNS support
    ec2.modify_vpc_attribute(
        VpcId=vpc_id,
        EnableDnsSupport={'Value': True}
    )

    # Habilitar DNS hostnames
    ec2.modify_vpc_attribute(
        VpcId=vpc_id,
        EnableDnsHostnames={'Value': True}
    )


    # Etiquetar la VPC (opcional)
    ec2.create_tags(
        Resources=[vpc_id],
        Tags=[{'Key': 'Name', 'Value': 'MiVPC-Boto3'},{'Key': 'Type', 'Value': 'prueba'}]
    )

  

    print("🌐 DNS habilitado y etiqueta 'MiVPC-Boto3' asignada.")
    return vpc_id


def crear_subnet(vpc_id):
    # Crear cliente de EC2
    ec2 = boto3.client('ec2')

    # Crear la subred
    subnet = ec2.create_subnet(
        VpcId=vpc_id,
        CidrBlock='193.168.5.0/24'
    )

    ec2.create_tags(
        Resources=[subnet['Subnet']['SubnetId']],
        Tags=[{'Key': 'Name', 'Value': 'MiSubred-Boto3'},{'Key': 'Type', 'Value': 'prueba'}]
    )

    subnet_id = subnet['Subnet']['SubnetId']
    print(f"✅ Subred creada con ID: {subnet_id}")



    return subnet_id


def crear_internet_gateway(vpc_id):
    # Crear cliente de EC2
    ec2 = boto3.client('ec2')

    # Crear el Internet Gateway
    igw = ec2.create_internet_gateway()
    igw_id = igw['InternetGateway']['InternetGatewayId']

    # Adjuntar el Internet Gateway a la VPC
    ec2.attach_internet_gateway(
        InternetGatewayId=igw_id,
        VpcId=vpc_id
    )

    ec2.create_tags(
        Resources=[igw_id],
        Tags=[{'Key': 'Name', 'Value': 'MiIGW-Boto3'},{'Key': 'Type', 'Value': 'prueba'}]
    )

    print(f"✅ Internet Gateway creado y adjuntado a la VPC: {igw_id}")
    return igw_id


def crear_tabla_rutas(vpc_id, igw_id, subnet_id):
    # Crear cliente de EC2
    ec2 = boto3.client('ec2')

    # Crear la tabla de rutas
    route_table = ec2.create_route_table(VpcId=vpc_id)
    route_table_id = route_table['RouteTable']['RouteTableId']

    # Agregar ruta por defecto hacia el Internet Gateway
    ec2.create_route(
        RouteTableId=route_table_id,
        DestinationCidrBlock='0.0.0.0/0',
        GatewayId=igw_id
    )

    # Asociar la tabla de rutas a la subred
    ec2.associate_route_table(
        RouteTableId=route_table_id,
        SubnetId=subnet_id
    )

    ec2.create_tags(
        Resources=[route_table_id],
        Tags=[{'Key': 'Name', 'Value': 'MiTablaRutas-Boto3'},{'Key': 'Type', 'Value': 'prueba'}]
    )

    print(f"✅ Tabla de rutas creada y asociada a la subred: {route_table_id}")
    return route_table_id


def crear_Ec2_instance(subnet_id):
    # Crear cliente de EC2
    ec2 = boto3.client('ec2')

    # Crear la instancia EC2
    instance = ec2.run_instances(
        ImageId='ami-0b6d9d3d33ba97d99',  
        InstanceType='t2.micro',
        MaxCount=1,
        MinCount=1
    )
    ec2.create_tags(
        Resources=[instance['Instances'][0]['InstanceId']],
        Tags=[{'Key': 'Name', 'Value': 'MiInstancia-Boto3'},{'Key': 'Type', 'Value': 'prueba'}]
    )

    instance_id = instance['Instances'][0]['InstanceId']
    print(f"✅ Instancia EC2 creada con ID: {instance_id}")

    return instance_id


if __name__ == "__main__":
    vpc_id = crear_vpc()
    subnet_id = crear_subnet(vpc_id)
    igw_id = crear_internet_gateway(vpc_id)
    route_table_id = crear_tabla_rutas(vpc_id, igw_id, subnet_id)
    instance_id = crear_Ec2_instance(subnet_id)
    print(f"🚀 Proceso completado. ID de la VPC: {vpc_id}, ID de la Subred: {subnet_id}, ID del Internet Gateway: {igw_id}, ID de la Tabla de Rutas: {route_table_id}, ID de la Instancia: {instance_id}")