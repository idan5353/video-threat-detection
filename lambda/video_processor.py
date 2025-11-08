import json
import boto3
import os
import uuid
from urllib.parse import unquote_plus

rekognition = boto3.client('rekognition')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Lambda function triggered by S3 upload to start Rekognition video analysis
    """
    
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing video: {key} from bucket: {bucket}")
            
            # Generate unique job ID
            job_id_prefix = str(uuid.uuid4())
            
            # Start Label Detection
            label_response = rekognition.start_label_detection(
                Video={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                NotificationChannel={
                    'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                    'RoleArn': os.environ['REKOGNITION_ROLE_ARN']
                },
                JobTag=f"label-detection-{job_id_prefix}",
                MinConfidence=float(os.environ.get('MIN_CONFIDENCE', '80'))
            )
            
            print(f"Started label detection job: {label_response['JobId']}")
            
            # Start Content Moderation (for violence/unsafe content)
            moderation_response = rekognition.start_content_moderation(
                Video={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                NotificationChannel={
                    'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                    'RoleArn': os.environ['REKOGNITION_ROLE_ARN']
                },
                JobTag=f"content-moderation-{job_id_prefix}",
                MinConfidence=float(os.environ.get('MIN_CONFIDENCE', '80'))
            )
            
            print(f"Started content moderation job: {moderation_response['JobId']}")
            
            # Start Person Tracking
            person_response = rekognition.start_person_tracking(
                Video={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                NotificationChannel={
                    'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                    'RoleArn': os.environ['REKOGNITION_ROLE_ARN']
                },
                JobTag=f"person-tracking-{job_id_prefix}"
            )
            
            print(f"Started person tracking job: {person_response['JobId']}")
            
            # Store job metadata for later processing
            job_metadata = {
                'video_key': key,
                'bucket': bucket,
                'label_job_id': label_response['JobId'],
                'moderation_job_id': moderation_response['JobId'],
                'person_job_id': person_response['JobId'],
                'job_prefix': job_id_prefix
            }
            
            # Send initial processing notification
            sns.publish(
                TopicArn=os.environ['THREAT_ALERT_TOPIC'],
                Subject=f"Video Processing Started: {key}",
                Message=json.dumps({
                    'status': 'PROCESSING_STARTED',
                    'video': key,
                    'jobs': job_metadata
                })
            )
            
    except Exception as e:
        print(f"Error processing video: {str(e)}")
        sns.publish(
            TopicArn=os.environ['THREAT_ALERT_TOPIC'],
            Subject=f"Video Processing Error",
            Message=f"Error processing video {key}: {str(e)}"
        )
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Video processing jobs started successfully')
    }
