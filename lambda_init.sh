# macOS/Linux
# export AWS_ACCESS_KEY_ID=test
# export AWS_SECRET_ACCESS_KEY=test

#windows
# $env:AWS_ACCESS_KEY_ID="test"
# $env:AWS_SECRET_ACCESS_KEY="test"


awslocal s3 cp .\lambdas\notification_lambda.zip s3://sbcbank-dev-frontend-000000000000/notification_lambda.zip
awslocal s3 cp .\lambdas\fraud_lambda.zip s3://sbcbank-dev-frontend-000000000000/fraud_lambda.zip