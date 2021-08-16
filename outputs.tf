output "lambda_bucket_name" {
  description = "S3 bucket name"

  value = aws_s3_bucket.bucket-mb.id
}
#lambda
output "function_name" {
  description = "Name of the Lambda function."

  value = aws_lambda_function.helloworld.function_name
}
#Apg
output "base_url" {
  description = "Base URL for api gateway stage."

  value = aws_apigatewayv2_stage.lambda.invoke_url
}
