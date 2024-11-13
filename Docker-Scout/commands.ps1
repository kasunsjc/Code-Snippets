# Commmands for the demo

# Login to Docker Hub

docker login

# Change to the sample-python-app directory

cd .\sample-python-app

# Build the image

docker build --push -t kasunrajapakse/sample-python:v1 .

# Enable Docker scout for the organization

docker scout enroll kasunrajapakse

# Enable Docker scout for the repository

docker scout repo enable --org kasunrajapakse kasunrajapakse/sample-python

# Check CVEs for the image

docker scout cves kasunrajapakse/sample-python:v1

#################################################################
# Change to the scout-demo directory

cd .\scout-demo-service

# Build the image

docker build --push -t kasunrajapakse/scout-demo .

# Enable Docker scout for the organization

docker scout enroll kasunrajapakse

# Enable Docker scout for the repository

docker scout repo enable --org kasunrajapakse kasunrajapakse/scout-demo

# Check CVEs for the image

docker scout cves kasunrajapakse/scout-demo

# View the CVEs in the specific repository

docker scout cves --only-package express kasunrajapakse/scout-demo