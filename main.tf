provider "aws" {
  region = "ap-south-1"
}

#Bucket for storing csv
resource "aws_s3_bucket" "my_bucket" {
  bucket = "csv-bucket-jenkins-unique"
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
  attribute {
    name = "RGB"
    type = "S"
  }
}

#/////////////////////////////////////////////////////////////////////////////////////////////


#Event Bus
resource "aws_cloudwatch_event_bus" "my_event_bus" {
  name = "my-event-bus"
}

#/////////////////////////////////////////////////////////////////////////////////////



#Send events to this eventbus using s3 notification
resource "aws_s3_bucket_notification" "s3_eventbridge_notification" {
  bucket      = aws_s3_bucket.my_bucket.id
  eventbridge = true

}

#/////////////////////////////////////////////////////////////////////////////////////////////



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


#Policy attachment to role
resource "aws_iam_policy_attachment" "attach_policy_to_lambda" {
  name       = "attachment"
  roles      = [aws_iam_role.aws_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

#Lambda function to process the events
resource "aws_lambda_function" "lambda_function" {
  filename      = "fun.zip"
  function_name = "s3todynamo"
  role          = aws_iam_role.aws_execution_role.arn
  handler       = "s3todynamo.lambda_handler"
  runtime       = "python3.9"
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

#Default bus target
resource "aws_cloudwatch_event_target" "custom_bus_target" {
  rule           = aws_cloudwatch_event_rule.to_custom_bus_rule.name
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
  rule           = aws_cloudwatch_event_rule.to_lambda_rule.name
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
  arn            = aws_lambda_function.lambda_function.arn
}

#/////////////////////////////////////////////////////////////////////////////////////////////
