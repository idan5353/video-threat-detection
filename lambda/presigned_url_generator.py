import json
import boto3
import os
import uuid
from datetime import datetime
from botocore.config import Config

def lambda_handler(event, context):
    """
    Generate presigned URL with proper regional endpoint
    """
    
    print(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Always return CORS headers
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'Access-Control-Max-Age': '86400'
        }
        
        # Handle OPTIONS request
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS preflight'})
            }
        
        # Parse request
        if not event.get('body'):
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'No request body'})
            }
            
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid JSON'})
            }
        
        file_name = body.get('fileName')
        file_type = body.get('fileType', 'video/mp4')
        
        if not file_name:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'fileName is required'})
            }
        
        # Generate unique key
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        unique_id = str(uuid.uuid4())[:8]
        file_extension = file_name.split('.')[-1] if '.' in file_name else 'mp4'
        key = f"videos/{timestamp}_{unique_id}.{file_extension}"
        
        # Create S3 client with explicit regional configuration
        region = os.environ.get('AWS_REGION', 'us-west-2')
        s3_client = boto3.client(
            's3',
            region_name=region,
            config=Config(
                signature_version='s3v4',
                s3={
                    'addressing_style': 'virtual',  # Use virtual hosted-style URLs
                }
            )
        )
        
        # Generate presigned URL
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': os.environ['UPLOAD_BUCKET'],
                'Key': key,
                'ContentType': file_type
            },
            ExpiresIn=3600
        )
        
        # Use regional endpoint for file URL
        bucket_name = os.environ['UPLOAD_BUCKET']
        file_url = f"https://{bucket_name}.s3.{region}.amazonaws.com/{key}"
        
        print(f"Generated regional presigned URL: {presigned_url}")
        print(f"File URL: {file_url}")
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'uploadUrl': presigned_url,
                'key': key,
                'bucket': bucket_name,
                'fileUrl': file_url,
                'method': 'PUT'
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
