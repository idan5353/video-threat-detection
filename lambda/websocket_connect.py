import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Handle WebSocket connection
    """
    
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Store connection in DynamoDB
        table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
        
        table.put_item(
            Item={
                'connectionId': connection_id,
                'timestamp': context.aws_request_id
            }
        )
        
        print(f"✅ Stored WebSocket connection: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Connected')
        }
        
    except Exception as e:
        print(f"❌ Error storing connection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
