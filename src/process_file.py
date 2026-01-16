import json
import boto3
import os

s3 = boto3.client('s3')
textract = boto3.client('textract')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMO_TABLE_NAME'])

def lambda_handler(event, context):
    # La Lambda recibe un lote de mensajes de SQS
    for record in event['Records']:
        # El cuerpo del mensaje SQS contiene el evento de S3
        payload = json.loads(record['body'])
        
        # A veces S3 envía una estructura de prueba, validamos
        if 'Records' in payload:
            s3_event = payload['Records'][0]
            bucket_name = s3_event['s3']['bucket']['name']
            file_key = s3_event['s3']['object']['key']
            
            print(f"Procesando archivo: {file_key} del bucket {bucket_name}")

            # 1. Llamar a Textract (Simulado para brevedad)
            # response = textract.detect_document_text(
            #     Document={'S3Object': {'Bucket': bucket_name, 'Name': file_key}}
            # )
            
            # 2. Guardar resultados en DynamoDB
            table.put_item(
                Item={
                    'id': file_key,
                    'status': 'PROCESSED',
                    'bucket': bucket_name
                    # 'text_data': json.dumps(response) 
                }
            )
            
    return {"statusCode": 200, "body": "Procesamiento completado"}
