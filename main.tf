provider "aws" {
  region = "ap-south-1"
}

#//////////////////////////////////////////////////////////////////////////////////

#Bucket for storing csv
resource "aws_s3_bucket" "my_bucket" {
  bucket = "csv-bucket-jenkins-unique"
}

# Log bucket for storing logs
resource "aws_s3_bucket" "log-bucket" {
  bucket = "log-bucket-for-cloudtrail-728382"
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
  # include_global_service_events = true
  # is_multi_region_trail         = true
  # enable_log_file_validation    = true

  event_selector {
    data_resource {
      type = "AWS::S3::Object"
      values = ["arn:aws:s3:::${aws_s3_bucket.my_bucket.bucket}/"]
    }
    include_management_events = true
  }
}


#Send events to this eventbus using s3 notification
resource "aws_s3_bucket_notification" "s3_eventbridge_notification" {
  bucket      = aws_s3_bucket.my_bucket.id
  eventbridge = true

}

#////////////////////////////////////////////////////////////////////////////////////




#Creating dynamodb table    Name,HEX,RGB
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
  # attribute {
  #   name = "RGB"
  #   type = "S"
  # }
}

#/////////////////////////////////////////////////////////////////////////////////////////////


#Event Bus
resource "aws_cloudwatch_event_bus" "my_event_bus" {
  name = "my-event-bus"
}

#/////////////////////////////////////////////////////////////////////////////////////


#Assume role policy for lambda
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

#Creating role
resource "aws_iam_role" "aws_execution_role" {
  name               = "lambda_s3_dynamo_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}



#Creating policy for lambda
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
    }
  )
}


#Policy attachment to role
resource "aws_iam_policy_attachment" "attach_policy_to_lambda" {
  name       = "attachment"
  roles      = [aws_iam_role.aws_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

#Policy attachment to role
resource "aws_iam_policy_attachment" "attach_policy_to_lambda1" {
  name       = "attachment_1"
  roles      = [aws_iam_role.aws_execution_role.name]
  policy_arn = aws_iam_policy.lambda_s3_dynamo_policy.arn
}

#Lambda function to process the events
resource "aws_lambda_function" "lambda_function" {
  filename      = "fun.zip"
  function_name = "s3todynamo"
  role          = aws_iam_role.aws_execution_role.arn
  handler       = "s3todynamo.lambda_handler"
  runtime       = "python3.9"
}


#Allowing lambda to be invoked by eventbus
resource "aws_lambda_permission" "allow_by_bus" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_bus.my_event_bus.arn

}



#/////////////////////////////////////////////////////////////////////////////////////////////

#Event Rule for default bus
resource "aws_cloudwatch_event_rule" "to_custom_bus_rule" {
  name           = "s3_event_rule"
  event_bus_name = "default"
  event_pattern = jsonencode(
    {
      "source" : ["aws.s3"],
      "detail-type" : ["AWS API Call via CloudTrail"],
      "detail" : {
        "eventSource" : ["s3.amazonaws.com"],
        "eventName" : ["PutObject"]
      }
    }
  )
}



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
      },
    ]
  })
}


#policy that allows lambda invoke permission
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


#Attach role to policy
resource "aws_iam_role_policy_attachment" "default_bus_policy_attachment" {
  role       = aws_iam_role.default_target_role.name
  policy_arn = aws_iam_policy.default_bus_policy.arn
}




#Default bus target
resource "aws_cloudwatch_event_target" "custom_bus_target" {
  rule           = aws_cloudwatch_event_rule.to_custom_bus_rule.name
  role_arn       = aws_iam_role.default_target_role.arn
  event_bus_name = "default"
  arn            = aws_cloudwatch_event_bus.my_event_bus.arn
}

#/////////////////////////////////////////////////////////////////////////////////////////////


#Event Rule for custom bus
resource "aws_cloudwatch_event_rule" "to_lambda_rule" {
  name           = "s3_event_rule_2"
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
  event_pattern = jsonencode(
    {
      "source" : ["aws.s3"],
      "detail-type" : ["AWS API Call via CloudTrail"],
      "detail" : {
        "eventSource" : ["s3.amazonaws.com"],
        "eventName" : ["PutObject"]
      }
    }
  )

}


#Custom bus target
resource "aws_cloudwatch_event_target" "custom_lambda_target" {
  rule = aws_cloudwatch_event_rule.to_lambda_rule.name
  # role_arn = 
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
  arn            = aws_lambda_function.lambda_function.arn
}

#/////////////////////////////////////////////////////////////////////////////////////////////
