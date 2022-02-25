# For AWS the following should be set as enviornment variables
#    AWS_ACCESS_KEY_ID
#    AWS_SECRET_ACCESS_KEY
#    AWS_DEFAULT_REGION
provider "aws " {
 access_key  = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}
