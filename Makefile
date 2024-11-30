# Name of the Docker image
IMAGE_NAME = ruby-with-github-graphql-practice

# Default target when 'make' is run without arguments
.DEFAULT_GOAL := help

# Print help information
help:
	@echo "Available commands:"
	@echo "  make build           - Build the Docker image"
	@echo "  make test            - Run tests inside the Docker container"
	@echo "  make shell           - Start a shell inside the Docker container for debugging"
	@echo "  make clean           - Remove the Docker image"
	@echo "  make rebuild         - Rebuild the Docker image without using cache"
	@echo "  make lint            - Run lint checks (if applicable)"

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Run tests inside the Docker container
test:
	docker run --rm $(IMAGE_NAME) gradle test

# Start a shell inside the Docker container for debugging
shell:
	docker run -it -v $(PWD):/app --user $(id -u):$(id -g) --rm $(IMAGE_NAME) /bin/bash

# Remove the Docker image
clean:
	docker rmi $(IMAGE_NAME)

# Rebuild the Docker image without using cache
rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .

# Example lint target (adjust based on your linting tool)
lint:
	docker run --rm $(IMAGE_NAME) gradle check
