provider "aws" {
  region = "us-east-1" # Cambia a tu región preferida
}

# --- 1. S3 Bucket (Entrada) ---
resource "aws_s3_bucket" "input_bucket" {
  bucket_prefix = "doc-input-"
}

# --- 2. SQS Queue (La cola intermedia) ---
resource "aws_sqs_queue" "process_queue" {
  name                      = "document-process-queue"
  message_retention_seconds = 86400
  visibility_timeout_seconds = 60 # Debe ser mayor que el timeout de la Lambda
}

# Política para permitir que S3 envíe mensajes a SQS
resource "aws_sqs_queue_policy" "s3_to_sqs" {
  queue_url = aws_sqs_queue.process_queue.id
  policy    = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "sqs:SendMessage",
      Resource  = aws_sqs_queue.process_queue.arn,
      Condition = {
        ArnEquals = { "aws:SourceArn": aws_s3_bucket.input_bucket.arn }
      }
    }]
  })
}

# Notificación: Cuando sube un archivo a S3 -> Enviar a SQS
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.process_queue.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

# --- 3. DynamoDB (Persistencia) ---
resource "aws_dynamodb_table" "results_table" {
  name           = "TextractResults"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

# --- 4. Lambda Function ---
# Primero empaquetamos el código Python
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../src/process_file.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "processor" {
  filename      = "lambda_function.zip"
  function_name = "doc_processor_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "process_file.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  # Pasar variables de entorno a la Lambda
  environment {
    variables = {
      DYNAMO_TABLE_NAME = aws_dynamodb_table.results_table.name
    }
  }
}

# Trigger: Conectar SQS a Lambda
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.process_queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
}

# --- 5. IAM Roles (Permisos) ---
resource "aws_iam_role" "lambda_role" {
  name = "lambda_processor_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Política de permisos para la Lambda (Logs, SQS, S3, Dynamo, Textract)
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        # Permisos básicos de Logs
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Leer mensajes de SQS
        Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
        Effect = "Allow",
        Resource = aws_sqs_queue.process_queue.arn
      },
      {
        # Leer el archivo de S3
        Action = ["s3:GetObject"],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.input_bucket.arn}/*"
      },
      {
        # Escribir en DynamoDB
        Action = ["dynamodb:PutItem"],
        Effect = "Allow",
        Resource = aws_dynamodb_table.results_table.arn
      },
      {
        # Usar Textract
        Action = ["textract:DetectDocumentText", "textract:AnalyzeDocument"],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}
