import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Handle WebSocket disconnection
    """
    
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Remove connection from DynamoDB
        table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
        
        table.delete_item(
            Key={
                'connectionId': connection_id
            }
        )
        
        print(f"✅ Removed WebSocket connection: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Disconnected')
        }
        
    except Exception as e:
        print(f"❌ Error removing connection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
