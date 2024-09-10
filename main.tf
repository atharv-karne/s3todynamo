provider "aws" {
  region = "ap-south-1"
}


#Bucket for storing csv

resource "aws_s3_bucket" "my_bucket" {
  bucket = "csv-bucket-jenkins-unique"
}



resource "aws_cloudwatch_event_bus" "my_event_bus" {
  name = "my-event-bus"
}


#Send events to this eventbus using s3 notification

resource "aws_s3_bucket_notification" "s3_eventbridge_notification" {
  bucket      = aws_s3_bucket.my_bucket.id
  eventbridge = true

}



#Lambda function to process the events
resource "aws_lambda_function" "lambda_function" {
  filename         = "fun.zip"
  function_name    = "s3todynamo"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "s3todynamo.lambda_handler"
  runtime          = "python3.9"
}


resource "aws_cloudwatch_event_rule" "to_custom_bus_rule" {
  name = "s3_event_rule"
  event_bus_name = "default"
  event_pattern = jsonencode(
    {
        "source": ["aws.s3"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["s3.amazonaws.com"],
      "eventName": ["PutObject"]
    }
    }
  )
}

resource "aws_cloudwatch_event_target" "custom_bus_target" {
  rule = aws_cloudwatch_event_rule.to_custom_bus_rule.name
  event_bus_name = "default"
  arn = aws_cloudwatch_event_bus.my_event_bus.arn
}




resource "aws_cloudwatch_event_rule" "to_lambda_rule" {
    name = "s3_event_rule_2"
    event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
    event_pattern = jsonencode(
    {
    "source": ["aws.s3"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["s3.amazonaws.com"],
      "eventName": ["PutObject"]
    }
    }
  )

}


resource "aws_cloudwatch_event_target" "custom_lambda_target" {
    rule = aws_cloudwatch_event_rule.to_lambda_rule.name
    event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
    arn = aws_lambda_function.lambda_function.arn
}
  
