#!/bin/bash

# Data Model Governance - Linux/macOS Startup Script
# Supports both zip package and extracted directory

echo "=========================================="
echo "Data Model Governance Software - Starting"
echo "=========================================="

# Get script directory
cd "$(dirname "$0")"

# Check if we have a zip package to extract
ZIP_FILE=$(find . -name "data-model-gov-1.0.0-standalone.zip" | head -n 1)

if [ -n "$ZIP_FILE" ]; then
    echo "Found deployment package: $ZIP_FILE"
    echo "Extracting to deployment directory..."
    
    # Create deployment directory
    mkdir -p deployment
    
    # Extract zip file
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$ZIP_FILE" -d deployment/
    else
        echo "ERROR: unzip command not found. Please install unzip."
        exit 1
    fi
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to extract deployment package"
        exit 1
    fi
    
    echo "Extraction completed!"
    cd deployment
fi

# Check application JAR
APP_JAR=""
if [ -f "app/data-model-gov-1.0.0.jar" ]; then
    APP_JAR="app/data-model-gov-1.0.0.jar"
else
    APP_JAR=$(find . -name "*.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" | head -n 1)
fi

if [ -z "$APP_JAR" ]; then
    echo "ERROR: Application JAR file not found"
    echo "Please ensure deployment package is extracted or JAR file exists"
    exit 1
fi

echo "Found application JAR: $APP_JAR"

# Check Java environment
if [ -x "jre/bin/java" ]; then
    echo "Using embedded JRE"
    JAVA_CMD="./jre/bin/java"
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
JAVA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC -XX:+UseStringDeduplication"

# Check for config directory (优先使用外部配置)
if [ -f "../config/application.yml" ]; then
    CONFIG_PATH="../config/application.yml,../config/config/iginx-config.properties"
    echo "Using external config: $CONFIG_PATH"
elif [ -f "../config/application.properties" ]; then
    CONFIG_PATH="../config/application.properties,../config/config/iginx-config.properties"
    echo "Using external config: $CONFIG_PATH"
elif [ -f "config/application.yml" ]; then
    CONFIG_PATH="config/application.yml,config/iginx-config.properties"
    echo "Using internal config: $CONFIG_PATH"
elif [ -f "config/application.properties" ]; then
    CONFIG_PATH="config/application.properties,config/iginx-config.properties"
    echo "Using internal config: $CONFIG_PATH"
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
