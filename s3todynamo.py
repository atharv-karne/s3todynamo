import json
import boto3
import csv
from io import StringIO

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    object_key = event['Records'][0]['s3']['object']['key']
    
    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    csv_content = response['Body'].read().decode('utf-8')
    
    csv_reader = csv.DictReader(StringIO(csv_content))
    
    table = dynamodb.Table('colors')

    for row in csv_reader:
        table.put_item(
            Item={
                'id': row['id'],
                'value': row['value']
            }
        )

    return {
        'statusCode': 200,
        'body': json.dumps('CSV processed successfully')
    }
