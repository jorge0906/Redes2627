import boto3

def crear_vpc():
    ec2 = boto3.client('ec2')

    # Crear VPC
    vpc_response = ec2.create_vpc(CidrBlock='10.0.0.0/16')
    vpc_id = vpc_response['Vpc']['VpcId']

    # Habilitar soporte para DNS y nombres de host DNS
    ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsSupport={'Value': True})
    ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsHostnames={'Value': True})

    # Agregar etiquetas a la VPC
    ec2.create_tags(Resources=[vpc_id], Tags=[{'Key': 'Name', 'Value': 'Script-VPC'}, {'Key': 'Environment', 'Value': 'Script'}])

    print(f"VPC creada con ID: {vpc_id}")

    return vpc_id

