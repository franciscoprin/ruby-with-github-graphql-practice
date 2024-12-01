# Use an official Gradle image as the base image
FROM ruby:2.7.7

# Set the working directory in the container
WORKDIR /app

# Copy the current directory contents into the container's /app directory
COPY . /app

# Install dependencies
RUN bundler install && apt update && apt install -y vim
