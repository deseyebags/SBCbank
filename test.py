import boto3
from localstack_client.session import Session

session = Session()
region = "ap-southeast-1"

def check_s3():
    s3 = session.client("s3", region_name=region)
    buckets = s3.list_buckets()["Buckets"]
    print("S3 Buckets:", [b["Name"] for b in buckets])

def check_ecs():
    ecs = session.client("ecs", region_name=region)
    clusters = ecs.list_clusters()["clusterArns"]
    print("ECS Clusters:", clusters)
    for arn in clusters:
        services = ecs.list_services(cluster=arn)["serviceArns"]
        print(f"Services in {arn}:", services)

def check_rds():
    rds = session.client("rds", region_name=region)
    dbs = rds.describe_db_instances()["DBInstances"]
    for db in dbs:
        print(f"RDS Instance: {db['DBInstanceIdentifier']} Status: {db['DBInstanceStatus']}")

def check_vpc():
    ec2 = session.client("ec2", region_name=region)
    vpcs = ec2.describe_vpcs()["Vpcs"]
    print("VPCs:", [v["VpcId"] for v in vpcs])
    subnets = ec2.describe_subnets()["Subnets"]
    print("Subnets:", [s["SubnetId"] for s in subnets])

if __name__ == "__main__":
    check_s3()
    check_ecs()
    check_rds()
    check_vpc()