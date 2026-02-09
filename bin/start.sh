#!/bin/bash

# Data Model Governance - Linux/macOS Startup Script
# For manually extracted deployment package

echo "=========================================="
echo "Data Model Governance Software - Starting"
echo "=========================================="

# Get script directory and go to parent directory
cd "$(dirname "$0")/.."

# Check application JAR
APP_JAR="app/data-model-gov-1.0.0.jar"
if [ ! -f "$APP_JAR" ]; then
    echo "ERROR: Application JAR file not found at $APP_JAR"
    echo "Please ensure you have extracted the deployment package correctly"
    exit 1
fi

echo "Found application JAR: $APP_JAR"

# Check Java environment - prioritize embedded JRE
if [ -x "jre/bin/java" ]; then
    echo "Using embedded JRE"
    JAVA_CMD="./jre/bin/java"
    # Set JRE home to fix library path issues
    export JRE_HOME="$(pwd)/jre"
    export JAVA_HOME="$(pwd)/jre"
else
    echo "Using system Java"
    if ! command -v java &> /dev/null; then
        echo "ERROR: Java environment not found"
        echo "Please ensure Java 8+ is installed or JRE directory exists"
        exit 1
    fi
    JAVA_CMD="java"
fi

# Set Java options
JAVA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC -XX:+UseStringDeduplication -Djava.library.path=jre/bin"

# Check for config directory
if [ -f "config/application.yml" ]; then
    CONFIG_PATH="config/application.yml,config/config/iginx-config.properties"
    echo "Using config: $CONFIG_PATH"
elif [ -f "config/application.yaml" ]; then
    CONFIG_PATH="config/application.yaml,config/config/iginx-config.properties"
    echo "Using config: $CONFIG_PATH"
elif [ -f "config/application.properties" ]; then
    CONFIG_PATH="config/application.properties,config/config/iginx-config.properties"
    echo "Using config: $CONFIG_PATH"
else
    echo "WARNING: No configuration file found, using defaults"
    CONFIG_PATH=""
fi

# Start application
echo ""
echo "Starting Data Model Governance..."
echo "Java command: $JAVA_CMD"
echo "Java options: $JAVA_OPTS"
[ -n "$CONFIG_PATH" ] && echo "Config file: $CONFIG_PATH"
echo ""

# Create logs directory if not exists
mkdir -p logs

# Start the application
if [ -n "$CONFIG_PATH" ]; then
    $JAVA_CMD $JAVA_OPTS -jar "$APP_JAR" --spring.config.location="$CONFIG_PATH" --spring.profiles.active=standalone
else
    $JAVA_CMD $JAVA_OPTS -jar "$APP_JAR" --spring.profiles.active=standalone
fi

# Check if application started successfully
if [ $? -eq 0 ]; then
    echo ""
    echo "Application started successfully!"
    echo "Access the application at: http://localhost:8080"
    echo "Press Ctrl+C to stop the application"
else
    echo ""
    echo "ERROR: Application failed to start"
    echo "Please check the error message above"
    exit 1
fi
