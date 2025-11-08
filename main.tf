terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate a new unique suffix
resource "random_string" "deployment_id" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# =====================================
# S3 BUCKETS
# =====================================

resource "aws_s3_bucket" "video_uploads" {
  bucket        = "vdt-uploads-${random_string.deployment_id.result}"
  force_destroy = true
  
  tags = {
    Name        = "Video Upload Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "analysis_results" {
  bucket        = "vdt-results-${random_string.deployment_id.result}"
  force_destroy = true
  
  tags = {
    Name        = "Analysis Results Bucket" 
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "frontend_web" {
  bucket        = "vdt-web-${random_string.deployment_id.result}"
  force_destroy = true
  
  tags = {
    Name        = "Frontend Hosting Bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Frontend hosting configuration
resource "aws_s3_bucket_public_access_block" "frontend_access" {
  bucket = aws_s3_bucket.frontend_web.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend_web.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.frontend_web.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend_access]
}

# Add S3 CORS configuration for video uploads bucket
resource "aws_s3_bucket_cors_configuration" "video_upload_cors" {
  bucket = aws_s3_bucket.video_uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]  # Allow all origins for now
    expose_headers  = ["ETag", "x-amz-request-id", "x-amz-id-2"]
    max_age_seconds = 3600
  }
}

# =====================================
# SNS AND SQS
# =====================================

resource "aws_sns_topic" "alerts" {
  name = "vdt-alerts-${random_string.deployment_id.result}"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic" "completion" {
  name = "vdt-completion-${random_string.deployment_id.result}"
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sqs_queue" "results_queue" {
  name                      = "vdt-queue-${random_string.deployment_id.result}"
  visibility_timeout_seconds = 300
  message_retention_seconds = 1209600
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_sns_topic_subscription" "completion_to_queue" {
  topic_arn = aws_sns_topic.completion.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.results_queue.arn
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.results_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.results_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.completion.arn
          }
        }
      }
    ]
  })
}

# =====================================
# IAM ROLES
# =====================================

resource "aws_iam_role" "lambda_video_role" {
  name = "vdt-video-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_video_policy" {
  name = "vdt-video-policy-${random_string.deployment_id.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream", 
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.video_uploads.arn}/*",
          "${aws_s3_bucket.analysis_results.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:StartLabelDetection",
          "rekognition:StartContentModeration",
          "rekognition:StartPersonTracking"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.alerts.arn,
          aws_sns_topic.completion.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.rekognition_role.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_video_attach" {
  role       = aws_iam_role.lambda_video_role.name
  policy_arn = aws_iam_policy.lambda_video_policy.arn
}

resource "aws_iam_role" "lambda_results_role" {
  name = "vdt-results-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_results_policy" {
  name = "vdt-results-policy-${random_string.deployment_id.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:GetLabelDetection",
          "rekognition:GetContentModeration", 
          "rekognition:GetPersonTracking"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.results_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.analysis_results.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.websocket_connections.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_results_attach" {
  role       = aws_iam_role.lambda_results_role.name
  policy_arn = aws_iam_policy.lambda_results_policy.arn
}

resource "aws_iam_role" "lambda_api_role" {
  name = "vdt-api-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_api_policy" {
  name = "vdt-api-policy-${random_string.deployment_id.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.video_uploads.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api_attach" {
  role       = aws_iam_role.lambda_api_role.name
  policy_arn = aws_iam_policy.lambda_api_policy.arn
}

resource "aws_iam_role" "rekognition_role" {
  name = "vdt-rekognition-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rekognition.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "rekognition_policy" {
  name = "vdt-rekognition-policy-${random_string.deployment_id.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.completion.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rekognition_attach" {
  role       = aws_iam_role.rekognition_role.name
  policy_arn = aws_iam_policy.rekognition_policy.arn
}

# =====================================
# WEBSOCKET LAMBDA ROLE
# =====================================

resource "aws_iam_role" "websocket_lambda_role" {
  name = "vdt-websocket-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "websocket_lambda_policy" {
  name = "vdt-websocket-policy-${random_string.deployment_id.result}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.websocket_connections.arn
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "websocket_lambda_attach" {
  role       = aws_iam_role.websocket_lambda_role.name
  policy_arn = aws_iam_policy.websocket_lambda_policy.arn
}

# =====================================
# THREAT ANALYZER IAM ROLE
# =====================================

resource "aws_iam_role" "lambda_analysis_role" {
  name = "vdt-lambda-analysis-role-${random_string.deployment_id.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Update the IAM Policy for Analysis Lambda in your main.tf
resource "aws_iam_role_policy" "lambda_analysis_policy" {
  name = "vdt-lambda-analysis-policy"
  role = aws_iam_role.lambda_analysis_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.video_uploads.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectFaces",
          "rekognition:StartLabelDetection",
          "rekognition:GetLabelDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:us-west-2:*:ufdrenitih/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.websocket_connections.arn
      }
    ]
  })
}


# =====================================
# LAMBDA FUNCTIONS
# =====================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_functions.zip"
}

resource "aws_lambda_function" "video_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-video-processor-${random_string.deployment_id.result}"
  role            = aws_iam_role.lambda_video_role.arn
  handler         = "video_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.completion.arn
      REKOGNITION_ROLE_ARN = aws_iam_role.rekognition_role.arn
      RESULTS_BUCKET = aws_s3_bucket.analysis_results.bucket
      THREAT_ALERT_TOPIC = aws_sns_topic.alerts.arn
      MIN_CONFIDENCE = var.min_confidence_threshold
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_stage.websocket_stage.invoke_url
    }
  }
}

resource "aws_lambda_function" "results_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-results-processor-${random_string.deployment_id.result}"
  role            = aws_iam_role.lambda_results_role.arn
  handler         = "results_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      THREAT_ALERT_TOPIC = aws_sns_topic.alerts.arn
      RESULTS_BUCKET = aws_s3_bucket.analysis_results.bucket
      MIN_CONFIDENCE = var.min_confidence_threshold
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_stage.websocket_stage.invoke_url
      CONNECTIONS_TABLE = aws_dynamodb_table.websocket_connections.name
    }
  }
}

resource "aws_lambda_function" "presigned_url_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-api-generator-${random_string.deployment_id.result}"
  role            = aws_iam_role.lambda_api_role.arn
  handler         = "presigned_url_generator.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 512
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      UPLOAD_BUCKET = aws_s3_bucket.video_uploads.bucket
    }
  }
}

# Video Analysis Lambda Function
resource "aws_lambda_function" "threat_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-threat-analyzer-${random_string.deployment_id.result}"
  role            = aws_iam_role.lambda_analysis_role.arn
  handler         = "threat_analyzer.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300  # 5 minutes for video analysis
  memory_size     = 1024
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      WEBSOCKET_API_ENDPOINT = aws_apigatewayv2_stage.websocket_stage.invoke_url
      CONNECTIONS_TABLE      = aws_dynamodb_table.websocket_connections.name
    }
  }
}

# WebSocket Lambda Functions
resource "aws_lambda_function" "websocket_connect" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-websocket-connect-${random_string.deployment_id.result}"
  role            = aws_iam_role.websocket_lambda_role.arn
  handler         = "websocket_connect.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.websocket_connections.name
    }
  }
}

resource "aws_lambda_function" "websocket_disconnect" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vdt-websocket-disconnect-${random_string.deployment_id.result}"
  role            = aws_iam_role.websocket_lambda_role.arn
  handler         = "websocket_disconnect.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.websocket_connections.name
    }
  }
}

# =====================================
# API GATEWAY (REST API WITH CORS)
# =====================================

resource "aws_api_gateway_rest_api" "video_api" {
  name = "vdt-api-${random_string.deployment_id.result}"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  parent_id   = aws_api_gateway_rest_api.video_api.root_resource_id
  path_part   = "upload-url"
}

# POST Method
resource "aws_api_gateway_method" "upload_url_post" {
  rest_api_id   = aws_api_gateway_rest_api.video_api.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "POST"
  authorization = "NONE"
  
  request_validator_id = aws_api_gateway_request_validator.upload_validator.id
}

# OPTIONS Method for CORS
resource "aws_api_gateway_method" "upload_url_options" {
  rest_api_id   = aws_api_gateway_rest_api.video_api.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Method Responses FIRST (before integration responses)
resource "aws_api_gateway_method_response" "upload_url_response_200" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "upload_url_options_response_200" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# POST Integration
resource "aws_api_gateway_integration" "upload_url_integration" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.presigned_url_generator.invoke_arn
}

# OPTIONS Integration for CORS
resource "aws_api_gateway_integration" "upload_url_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method

  type = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# Integration Responses AFTER method responses exist
resource "aws_api_gateway_integration_response" "upload_url_integration_response" {
  depends_on = [
    aws_api_gateway_method_response.upload_url_response_200,
    aws_api_gateway_integration.upload_url_integration
  ]
  
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_post.http_method
  status_code = aws_api_gateway_method_response.upload_url_response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "upload_url_options_integration_response" {
  depends_on = [
    aws_api_gateway_method_response.upload_url_options_response_200,
    aws_api_gateway_integration.upload_url_options_integration
  ]
  
  rest_api_id = aws_api_gateway_rest_api.video_api.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method
  status_code = aws_api_gateway_method_response.upload_url_options_response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
  }
}

resource "aws_api_gateway_deployment" "video_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.upload_url_integration,
    aws_api_gateway_integration.upload_url_options_integration,
    aws_api_gateway_integration_response.upload_url_integration_response,
    aws_api_gateway_integration_response.upload_url_options_integration_response,
  ]

  rest_api_id = aws_api_gateway_rest_api.video_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload_url.id,
      aws_api_gateway_method.upload_url_post.id,
      aws_api_gateway_method.upload_url_options.id,
      aws_api_gateway_integration.upload_url_integration.id,
      aws_api_gateway_integration.upload_url_options_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "video_api_stage" {
  deployment_id = aws_api_gateway_deployment.video_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.video_api.id
  stage_name    = "prod"
}

resource "aws_lambda_permission" "api_gw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned_url_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.video_api.execution_arn}/*/*"
}

# Update the API Gateway method to handle larger payloads
resource "aws_api_gateway_request_validator" "upload_validator" {
  name                        = "upload-validator"
  rest_api_id                = aws_api_gateway_rest_api.video_api.id
  validate_request_body       = false
  validate_request_parameters = false
}

# =====================================
# WEBSOCKET API
# =====================================

resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = "vdt-websocket-${random_string.deployment_id.result}"
  protocol_type             = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id      = aws_apigatewayv2_api.websocket_api.id
  name        = "prod"
  auto_deploy = true
}

# DynamoDB table for WebSocket connections
resource "aws_dynamodb_table" "websocket_connections" {
  name         = "vdt-connections-${random_string.deployment_id.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }
}

# WebSocket Routes
resource "aws_apigatewayv2_route" "websocket_connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_connect_integration.id}"
}

resource "aws_apigatewayv2_route" "websocket_disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.websocket_disconnect_integration.id}"
}

# WebSocket Integrations
resource "aws_apigatewayv2_integration" "websocket_connect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_connect.invoke_arn
}

resource "aws_apigatewayv2_integration" "websocket_disconnect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_disconnect.invoke_arn
}

# Lambda permissions for WebSocket
resource "aws_lambda_permission" "websocket_connect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "websocket_disconnect_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

# =====================================
# EVENT SOURCE MAPPINGS
# =====================================

resource "aws_lambda_event_source_mapping" "sqs_to_results_processor" {
  event_source_arn = aws_sqs_queue.results_queue.arn
  function_name    = aws_lambda_function.results_processor.arn
  batch_size       = 10
}

resource "aws_lambda_permission" "s3_invoke_video_processor" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.video_uploads.arn
}

# Lambda permission for S3 to invoke threat analyzer
resource "aws_lambda_permission" "s3_invoke_threat_analyzer" {
  statement_id  = "AllowExecutionFromS3BucketThreatAnalyzer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.threat_analyzer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.video_uploads.arn
}

# =====================================
# S3 BUCKET NOTIFICATIONS
# =====================================

# =====================================
# S3 BUCKET NOTIFICATIONS  
# =====================================

# =====================================
# S3 BUCKET NOTIFICATIONS
# =====================================

resource "aws_s3_bucket_notification" "video_upload_notification" {
  bucket = aws_s3_bucket.video_uploads.id

  # Threat analyzer - handles ALL video files
  lambda_function {
    lambda_function_arn = aws_lambda_function.threat_analyzer.arn
    events             = ["s3:ObjectCreated:*"]
    filter_prefix      = "videos/"
    id                 = "ThreatAnalyzerTrigger"
  }

  depends_on = [
    aws_lambda_permission.s3_invoke_video_processor,
    aws_lambda_permission.s3_invoke_threat_analyzer
  ]
}



