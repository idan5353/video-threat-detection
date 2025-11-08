import json
import boto3
import os
from datetime import datetime

rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

# Threat detection labels
THREAT_LABELS = [
    'Weapon', 'Gun', 'Knife', 'Rifle', 'Handgun', 'Pistol',
    'Fire', 'Smoke', 'Explosion', 'Violence', 'Fighting',
    'Crowd', 'Protest', 'Riot', 'Suspicious Activity'
]

def lambda_handler(event, context):
    """
    Process Rekognition job completion notifications and analyze results for threats
    """
    
    try:
        for record in event['Records']:
            # Parse SQS message from SNS
            message_body = json.loads(record['body'])
            sns_message = json.loads(message_body['Message'])
            
            job_id = sns_message['JobId']
            job_status = sns_message['Status']
            api = sns_message['API']
            
            print(f"Processing {api} job {job_id} with status {job_status}")
            
            if job_status == 'SUCCEEDED':
                threats_detected = []
                
                if api == 'StartLabelDetection':
                    threats_detected.extend(process_label_detection(job_id))
                elif api == 'StartContentModeration':
                    threats_detected.extend(process_content_moderation(job_id))
                elif api == 'StartPersonTracking':
                    threats_detected.extend(process_person_tracking(job_id))
                
                # Save results and send alerts if threats found
                if threats_detected:
                    save_threat_results(job_id, api, threats_detected)
                    send_threat_alert(job_id, api, threats_detected, sns_message.get('Video', {}))
                    
                    # Send CloudWatch metrics
                    send_metrics(len(threats_detected), api)
                
            elif job_status == 'FAILED':
                print(f"Job {job_id} failed")
                sns.publish(
                    TopicArn=os.environ['THREAT_ALERT_TOPIC'],
                    Subject=f"Video Analysis Failed - {api}",
                    Message=f"Analysis job {job_id} failed for {api}"
                )
                
    except Exception as e:
        print(f"Error processing results: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Results processed successfully')
    }

def process_label_detection(job_id):
    """Process label detection results for threats"""
    threats = []
    min_confidence = float(os.environ.get('MIN_CONFIDENCE', '80'))
    
    try:
        response = rekognition.get_label_detection(JobId=job_id)
        
        for label_detection in response.get('Labels', []):
            label = label_detection.get('Label', {})
            
            if (label.get('Name') in THREAT_LABELS and 
                label.get('Confidence', 0) >= min_confidence):
                
                threats.append({
                    'type': 'THREAT_LABEL',
                    'label': label.get('Name'),
                    'confidence': label.get('Confidence'),
                    'timestamp': label_detection.get('Timestamp'),
                    'instances': label.get('Instances', [])
                })
                
    except Exception as e:
        print(f"Error processing label detection: {str(e)}")
    
    return threats

def process_content_moderation(job_id):
    """Process content moderation results for unsafe content"""
    threats = []
    min_confidence = float(os.environ.get('MIN_CONFIDENCE', '80'))
    
    try:
        response = rekognition.get_content_moderation(JobId=job_id)
        
        for moderation_detection in response.get('ModerationLabels', []):
            moderation_label = moderation_detection.get('ModerationLabel', {})
            
            if moderation_label.get('Confidence', 0) >= min_confidence:
                threats.append({
                    'type': 'UNSAFE_CONTENT',
                    'label': moderation_label.get('Name'),
                    'confidence': moderation_label.get('Confidence'),
                    'timestamp': moderation_detection.get('Timestamp'),
                    'parent_name': moderation_label.get('ParentName', '')
                })
                
    except Exception as e:
        print(f"Error processing content moderation: {str(e)}")
    
    return threats

def process_person_tracking(job_id):
    """Process person tracking for crowd detection"""
    threats = []
    
    try:
        response = rekognition.get_person_tracking(JobId=job_id)
        
        # Group persons by timestamp to detect crowds
        persons_by_timestamp = {}
        
        for person_detection in response.get('Persons', []):
            timestamp = person_detection.get('Timestamp', 0)
            if timestamp not in persons_by_timestamp:
                persons_by_timestamp[timestamp] = []
            persons_by_timestamp[timestamp].append(person_detection)
        
        # Check for crowd formation (more than 5 people at same time)
        for timestamp, persons in persons_by_timestamp.items():
            if len(persons) > 5:
                threats.append({
                    'type': 'CROWD_DETECTION',
                    'label': 'Large Crowd',
                    'confidence': 95.0,  # High confidence for counting
                    'timestamp': timestamp,
                    'person_count': len(persons)
                })
                
    except Exception as e:
        print(f"Error processing person tracking: {str(e)}")
    
    return threats

def save_threat_results(job_id, api, threats):
    """Save threat detection results to S3"""
    try:
        results = {
            'job_id': job_id,
            'api': api,
            'timestamp': datetime.utcnow().isoformat(),
            'threats_detected': threats,
            'threat_count': len(threats)
        }
        
        s3_key = f"threat-results/{datetime.utcnow().strftime('%Y/%m/%d')}/{job_id}-{api}.json"
        
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=s3_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        
        print(f"Saved threat results to s3://{os.environ['RESULTS_BUCKET']}/{s3_key}")
        
    except Exception as e:
        print(f"Error saving results: {str(e)}")

def send_threat_alert(job_id, api, threats, video_info):
    """Send threat alert notification"""
    try:
        threat_summary = {}
        for threat in threats:
            threat_type = threat.get('type', 'UNKNOWN')
            if threat_type not in threat_summary:
                threat_summary[threat_type] = []
            threat_summary[threat_type].append(threat.get('label', 'Unknown'))
        
        alert_message = {
            'alert_type': 'THREAT_DETECTED',
            'job_id': job_id,
            'api': api,
            'video_info': video_info,
            'threat_count': len(threats),
            'threat_summary': threat_summary,
            'threats': threats[:5],  # Include first 5 threats in alert
            'timestamp': datetime.utcnow().isoformat()
        }
        
        sns.publish(
            TopicArn=os.environ['THREAT_ALERT_TOPIC'],
            Subject=f"🚨 THREAT DETECTED - {len(threats)} threats found",
            Message=json.dumps(alert_message, indent=2)
        )
        
        print(f"Sent threat alert for {len(threats)} threats")
        
    except Exception as e:
        print(f"Error sending alert: {str(e)}")

def send_metrics(threat_count, api):
    """Send custom metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='VideoThreatDetection',
            MetricData=[
                {
                    'MetricName': 'ThreatsDetected',
                    'Value': threat_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'API',
                            'Value': api
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        print(f"Error sending metrics: {str(e)}")
