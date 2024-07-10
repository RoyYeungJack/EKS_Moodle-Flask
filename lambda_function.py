import boto3
import os
import sys
import uuid
from urllib.parse import unquote_plus
from PIL import Image

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        tmpkey = key.replace('/', '')
        download_path = '/tmp/{}{}'.format(uuid.uuid4(), tmpkey)
        upload_path = '/tmp/resized-{}'.format(tmpkey)
        
        s3_client.download_file(bucket, key, download_path)
        
        with Image.open(download_path) as image:
            rgb_im = image.convert('RGB')
            rgb_im.save(upload_path, format='JPEG')
        
        s3_client.upload_file(upload_path, bucket, 'converted-{}.jpg'.format(os.path.splitext(key)[0]))
        
        os.remove(download_path)
        os.remove(upload_path)
    
    return {
        'statusCode': 200,
        'body': 'Image converted successfully'
    }