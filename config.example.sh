# Copy this file to config.sh and edit it:  cp config.example.sh config.sh
# config.sh is git-ignored. The deploy/teardown scripts source it automatically.
# (You can also just export these in your shell instead of using a file.)

# A short, DNS-safe name. Becomes part of your bucket name:
#   <PROJECT_NAME>-<your-account-id>
# Allowed: 3-42 chars, lowercase letters, digits, hyphens.
export PROJECT_NAME="my-static-site"

# Where the S3 bucket lives. CloudFront is global regardless of this.
export AWS_REGION="us-east-1"

# The scoped AWS CLI profile to deploy with (see the "Scoped deploy profile"
# section in README.md).
# Comment this out to use your default credentials instead.
export AWS_PROFILE="static-site-deployer"
