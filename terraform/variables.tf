#
#AWS authentication variables
variable "aws_access_key" {
  type = string
  description = "AWS Access Key"
}
variable "aws_secret_key" {
  type = string
  description = "AWS Secret Key"
}
variable "aws_region" {
  type = string
  description = "AWS Region"
}
variable "AWS_VPC_NAME" {
  type = string
}
variable "AWS_SUBNET_NAME" {
  type = string
}
variable "AWS_PRIV_SUBNET_NAME" {
  type = string
}
variable "AWS_PG_NAME" {
  type = string
}
variable "AWS_JLAB_AMI" {
  type = string
}
variable "AWS_JLAB_ITYPE" {
  type = string
}
variable "AWS_DSCHED_ITYPE" {
  type = string
}
variable "AWS_DWORKERS_COUNT" {
  type = number
}
variable "AWS_SSHGW_ITYPE" {
  type = string
}
variable "AWS_SSH_KEY_NAME" {
  type = string
}

