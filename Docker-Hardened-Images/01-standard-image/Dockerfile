# Standard Docker Image Dockerfile
# This uses the official Python image from Docker Hub
# Demonstrates a typical Dockerfile without DHI

FROM python:3.13

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .

# Expose port
EXPOSE 8000

# Run the application
CMD ["python", "app.py"]

# Characteristics of this image:
# - Uses official python:3.13 from Docker Hub (~412 MB)
# - Runs as root user (default)
# - Includes full OS packages (~610 packages)
# - Contains shell and package managers
# - Has 100+ potential CVEs
# - No SBOM, provenance, or signatures
# - Good for development, not optimal for production
