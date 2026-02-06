#!/bin/bash

# Data Model Governance - Simple Linux/macOS Stop Script
# Stops the application running in the same directory

echo "=========================================="
echo "Data Model Governance - Stopping"
echo "=========================================="

# Get script directory
cd "$(dirname "$0")"

# Function to stop by port
stop_by_port() {
    if command -v lsof >/dev/null 2>&1; then
        PID=$(lsof -ti:8080 2>/dev/null)
        if [ -n "$PID" ]; then
            echo "Found process using port 8080: $PID"
            kill -TERM $PID
            sleep 2
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        PID=$(netstat -tlnp 2>/dev/null | grep ":8080" | awk '{print $7}' | cut -d'/' -f1)
        if [ -n "$PID" ] && [ "$PID" != "-" ]; then
            echo "Found process using port 8080: $PID"
            kill -TERM $PID
            sleep 2
            return 0
        fi
    fi
    return 1
}

# Function to stop by process name
stop_by_name() {
    for pid in $(ps aux | grep "[d]ata-model" | grep java | awk '{print $2}'); do
        echo "Found data-model process: $pid"
        kill -TERM $pid
        sleep 2
    done
}

# Try to stop application
echo "Stopping application..."

if stop_by_port; then
    echo "Application stop command sent"
else
    echo "Trying to stop by process name..."
    stop_by_name
fi

# Wait and verify
sleep 3

# Check if still running
if command -v lsof >/dev/null 2>&1; then
    if lsof -ti:8080 >/dev/null 2>&1; then
        echo "WARNING: Application may still be running on port 8080"
    else
        echo "SUCCESS: Application stopped successfully"
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -tlnp 2>/dev/null | grep ":8080" >/dev/null; then
        echo "WARNING: Application may still be running on port 8080"
    else
        echo "SUCCESS: Application stopped successfully"
    fi
else
    echo "Could not verify application status"
fi

echo "=========================================="
