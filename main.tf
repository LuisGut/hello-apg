terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "bucket-mb" {
  bucket = "mb-challenge-2"
  acl           = "private"
  force_destroy = true
}
#Package & copy to s3 bucket
data "archive_file" "helloworld" {
  type = "zip"

  source_dir  = "${path.module}/helloworld"
  output_path = "${path.module}/helloworld.zip"
}

resource "aws_s3_bucket_object" "helloworld" {
  bucket = aws_s3_bucket.bucket-mb.id

  key    = "helloworld.zip"
  source = data.archive_file.helloworld.output_path

  etag = filemd5(data.archive_file.helloworld.output_path)
}
#Create lambda
resource "aws_lambda_function" "helloworld" {
  function_name = "HelloWorld"

  s3_bucket = aws_s3_bucket.bucket-mb.id
  s3_key    = aws_s3_bucket_object.helloworld.key

  runtime = "nodejs12.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.helloworld.output_base64sha256

  role = aws_iam_role.lambda-apg.arn
}

resource "aws_cloudwatch_log_group" "helloworld" {
  name = "/aws/lambda/${aws_lambda_function.helloworld.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda-apg" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda-apg.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
#Apg
resource "aws_apigatewayv2_api" "lambda" {
  name          = "lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "helloworld" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.helloworld.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "helloworld" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.helloworld.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.helloworld.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}