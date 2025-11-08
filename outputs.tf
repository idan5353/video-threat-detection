output "websocket_api_url" {
  description = "WebSocket API endpoint URL"
  value       = aws_apigatewayv2_stage.websocket_stage.invoke_url
}

output "api_gateway_url" {
  description = "REST API endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.video_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
}

output "deployment_urls" {
  description = "All important URLs for your app"
  value = {
    frontend_url    = "http://${aws_s3_bucket_website_configuration.frontend_config.website_endpoint}"
    api_url        = "https://${aws_api_gateway_rest_api.video_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
    websocket_url  = aws_apigatewayv2_stage.websocket_stage.invoke_url
    upload_bucket  = aws_s3_bucket.video_uploads.bucket
    frontend_bucket = aws_s3_bucket.frontend_web.bucket
  }
}
