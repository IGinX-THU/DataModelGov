#!/bin/bash

echo "Testing Thrift installation..."

# Check if thrift is installed
if ! command -v thrift &> /dev/null; then
    echo "❌ Thrift is not installed or not in PATH"
    echo "Please install Thrift:"
    echo "  Ubuntu/Debian: sudo apt-get install thrift-compiler"
    echo "  macOS: brew install thrift"
    echo "  Windows: Download from https://thrift.apache.org/download"
    exit 1
fi

# Check thrift version
echo "✅ Thrift found: $(thrift --version)"

# Test thrift file syntax
echo "Testing Thrift file syntax..."
thrift --gen dummy datamodelgov-server/src/main/resources/thrift/api.thrift

if [ $? -eq 0 ]; then
    echo "✅ Thrift file syntax is valid"
else
    echo "❌ Thrift file syntax error"
    exit 1
fi

# Test code generation
echo "Testing code generation..."
mkdir -p test-output

thrift --gen java -out test-output datamodelgov-server/src/main/resources/thrift/api.thrift
if [ $? -eq 0 ]; then
    echo "✅ Java code generation successful"
else
    echo "❌ Java code generation failed"
fi

thrift --gen go -out test-output datamodelgov-server/src/main/resources/thrift/api.thrift
if [ $? -eq 0 ]; then
    echo "✅ Go code generation successful"
else
    echo "❌ Go code generation failed"
fi

thrift --gen py -out test-output datamodelgov-server/src/main/resources/thrift/api.thrift
if [ $? -eq 0 ]; then
    echo "✅ Python code generation successful"
else
    echo "❌ Python code generation failed"
fi

# Clean up
rm -rf test-output

echo "✅ All tests completed successfully!"
