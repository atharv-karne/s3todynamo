provider "aws" {
  region = "ap-south-1"
}

#//////////////////////////////////////////////////////////////////////////////////

# Bucket for storing CSV files
resource "aws_s3_bucket" "my_bucket" {
  bucket = "csv-bucket-jenkins-unique"
}

# Log bucket for storing CloudTrail logs
resource "aws_s3_bucket" "log-bucket" {
  bucket = "log-bucket-for-cloudtrail-728382"
}

# IAM Role for CloudTrail to write logs to CloudWatch
resource "aws_iam_role" "cloudtrail_role" {
  name = "CloudTrail_Logging_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy for CloudTrail to write logs to CloudWatch
resource "aws_iam_policy" "cloudtrail_logs_policy" {
  name   = "CloudTrail_Logs_Policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          # "logs:PutLogEvents",
          # "logs:CreateLogStream",
          # "logs:CreateLogGroup"
          "logs:*"
        ],
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the CloudTrail IAM role
resource "aws_iam_role_policy_attachment" "cloudtrail_policy_attachment" {
  role       = aws_iam_role.cloudtrail_role.name
  policy_arn = aws_iam_policy.cloudtrail_logs_policy.arn
}

# Create CloudWatch Logs Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail_log_group" {
  name = "/aws/cloudtrail/my-trail-logs"
}

# Setting bucket policy to allow CloudTrail to write logs
resource "aws_s3_bucket_policy" "allow_trail_write_logs" {
  bucket = aws_s3_bucket.log-bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect  = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.log-bucket.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect  = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.log-bucket.arn}/*"
      }
    ]
  })
}

# CloudTrail configuration
resource "aws_cloudtrail" "my_trail" {
  name                          = "my-trail"
  s3_bucket_name                = aws_s3_bucket.log-bucket.bucket
  include_global_service_events = true
  is_multi_region_trail         = false
  is_organization_trail         = false

  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail_log_group.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_role.arn

  event_selector {
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${aws_s3_bucket.my_bucket.bucket}/"]
    }
    include_management_events = true
  }
}

# Send events to this event bus using S3 notification
resource "aws_s3_bucket_notification" "s3_eventbridge_notification" {
  bucket      = aws_s3_bucket.my_bucket.id
  eventbridge = true
}

# Creating DynamoDB table
resource "aws_dynamodb_table" "my_dynamo_table" {
  name           = "colors"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "Name"
  range_key      = "HEX"

  attribute {
    name = "Name"
    type = "S"
  }

  attribute {
    name = "HEX"
    type = "S"
  }
}

#/////////////////////////////////////////////////////////////////////////////////////

# Event Bus
resource "aws_cloudwatch_event_bus" "my_event_bus" {
  name = "my-event-bus"
}

#/////////////////////////////////////////////////////////////////////////////////////

# Assume role policy for Lambda
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Creating IAM role for Lambda
resource "aws_iam_role" "aws_execution_role" {
  name               = "lambda_s3_dynamo_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Creating policy for Lambda
resource "aws_iam_policy" "lambda_s3_dynamo_policy" {
  name = "custom_lambda_s3_to_dynamo_policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        "Resource" : "*"
      }
    ]
  })
}

# Attach policies to Lambda execution role
resource "aws_iam_policy_attachment" "attach_policy_to_lambda" {
  name       = "attachment"
  roles      = [aws_iam_role.aws_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_policy_attachment" "attach_policy_to_lambda1" {
  name       = "attachment_1"
  roles      = [aws_iam_role.aws_execution_role.name]
  policy_arn = aws_iam_policy.lambda_s3_dynamo_policy.arn
}

# Lambda function to process the events
resource "aws_lambda_function" "lambda_function" {
  filename      = "fun.zip"
  function_name = "s3todynamo"
  role          = aws_iam_role.aws_execution_role.arn
  handler       = "s3todynamo.lambda_handler"
  runtime       = "python3.9"
}

# Allow Lambda to be invoked by EventBus
resource "aws_lambda_permission" "allow_by_bus" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_bus.my_event_bus.arn
}

#/////////////////////////////////////////////////////////////////////////////////////////////

# Event Rule for default bus
resource "aws_cloudwatch_event_rule" "to_custom_bus_rule" {
  name           = "s3_event_rule"
  event_bus_name = "default"
  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["AWS API Call via CloudTrail"],
    "detail" : {
      "eventSource" : ["s3.amazonaws.com"],
      "eventName" : ["PutObject"]
    }
  })
}

# IAM Role for default event bus target
resource "aws_iam_role" "default_target_role" {
  name = "default_eventbus_target_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# Policy that allows Lambda invoke permission
resource "aws_iam_policy" "default_bus_policy" {
  name = "default_bus_policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction"
        ],
        "Resource" : [
          aws_lambda_function.lambda_function.arn
        ]
      }
    ]
  })
}

# Attach policy to the IAM role for default bus
resource "aws_iam_role_policy_attachment" "default_bus_policy_attachment" {
  role       = aws_iam_role.default_target_role.name
  policy_arn = aws_iam_policy.default_bus_policy.arn
}

# Default bus target
resource "aws_cloudwatch_event_target" "custom_bus_target" {
  rule           = aws_cloudwatch_event_rule.to_custom_bus_rule.name
  role_arn       = aws_iam_role.default_target_role.arn
  event_bus_name = "default"
  arn            = aws_cloudwatch_event_bus.my_event_bus.arn
}

#/////////////////////////////////////////////////////////////////////////////////////////////

# Event Rule for custom bus
resource "aws_cloudwatch_event_rule" "to_lambda_rule" {
  name           = "s3_event_rule_2"
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["AWS API Call via CloudTrail"],
    "detail" : {
      "eventSource" : ["s3.amazonaws.com"],
      "eventName" : ["PutObject"]
    }
  })

}

resource "aws_cloudwatch_event_target" "custom_bus_target_lambda" {
  rule           = aws_cloudwatch_event_rule.to_lambda_rule.name
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
  arn            = aws_lambda_function.lambda_function.arn
}

  