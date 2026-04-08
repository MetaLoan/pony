#!/bin/bash
set -e

# Replace with your actual DockerHub username!
DOCKER_USER="your_dockerhub_username"
IMAGE_NAME="runpod-pulid-serverless"
VERSION="v1"

echo "============================================="
echo " Building ComfyUI Serverless Image"
echo " Image: ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}"
echo "============================================="

docker build -t ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} .

echo "============================================="
echo " Build Complete. Pushing to DockerHub..."
echo "============================================="

# Uncomment below to actually push
# docker push ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}

echo "✅ Done! You can now use ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} as your RunPod Serverless template image."
