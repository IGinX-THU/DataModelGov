#!/bin/bash

# DataModelGov Thrift SDK 一键生成脚本
# 用于生成Java、Go、Python三语言的SDK

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THRIFT_FILE="$PROJECT_ROOT/datamodelgov-server/src/main/resources/thrift/api.thrift"

# SDK输出目录
JAVA_SDK_DIR="$PROJECT_ROOT/datamodelgov-sdk-java/src/main/java"
GO_SDK_DIR="$PROJECT_ROOT/datamodelgov-sdk-go/src"
PYTHON_SDK_DIR="$PROJECT_ROOT/datamodelgov-sdk-python/src"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Thrift环境
check_thrift() {
    log_info "检查Thrift环境..."
    if ! command -v thrift &> /dev/null; then
        log_error "Thrift未安装或不在PATH中"
        log_info "请安装Thrift: https://thrift.apache.org/download"
        exit 1
    fi
    
    THRIFT_VERSION=$(thrift --version 2>/dev/null || echo "unknown")
    log_success "Thrift环境正常，版本: $THRIFT_VERSION"
}

# 验证Thrift文件
validate_thrift_file() {
    log_info "验证Thrift文件语法..."
    if [[ ! -f "$THRIFT_FILE" ]]; then
        log_error "Thrift文件不存在: $THRIFT_FILE"
        exit 1
    fi
    
    if ! thrift --gen dummy "$THRIFT_FILE" 2>/dev/null; then
        log_error "Thrift文件语法错误"
        exit 1
    fi
    
    log_success "Thrift文件语法正确"
}

# 创建输出目录
create_directories() {
    log_info "创建输出目录..."
    
    mkdir -p "$JAVA_SDK_DIR"
    mkdir -p "$GO_SDK_DIR"
    mkdir -p "$PYTHON_SDK_DIR"
    
    log_success "输出目录创建完成"
}

# 生成Java SDK
generate_java_sdk() {
    log_info "生成Java SDK..."
    
    cd "$PROJECT_ROOT"
    if thrift --gen java -out "$JAVA_SDK_DIR" "$THRIFT_FILE"; then
        # 统计生成的文件数
        JAVA_FILES=$(find "$JAVA_SDK_DIR/com/tsinghua/thrift/api" -name "*.java" 2>/dev/null | wc -l)
        log_success "Java SDK生成成功，共 $JAVA_FILES 个文件"
        
        # 检查关键文件
        if [[ -f "$JAVA_SDK_DIR/com/tsinghua/thrift/api/ParsingRule.java" ]]; then
            log_success "✓ ParsingRule.java 已生成"
        fi
        if [[ -f "$JAVA_SDK_DIR/com/tsinghua/thrift/api/RunTask.java" ]]; then
            log_success "✓ RunTask.java 已生成"
        fi
    else
        log_error "Java SDK生成失败"
        return 1
    fi
}

# 生成Go SDK
generate_go_sdk() {
    log_info "生成Go SDK..."
    
    cd "$PROJECT_ROOT"
    if thrift --gen go -out "$GO_SDK_DIR" "$THRIFT_FILE"; then
        # 统计生成的文件数
        GO_FILES=$(find "$GO_SDK_DIR/tsinghua/api" -name "*.go" 2>/dev/null | wc -l)
        log_success "Go SDK生成成功，共 $GO_FILES 个文件"
        
        # 检查关键文件
        if [[ -f "$GO_SDK_DIR/tsinghua/api/api.go" ]]; then
            log_success "✓ api.go 已生成"
        fi
    else
        log_error "Go SDK生成失败"
        return 1
    fi
}

# 生成Python SDK
generate_python_sdk() {
    log_info "生成Python SDK..."
    
    cd "$PROJECT_ROOT"
    if thrift --gen py -out "$PYTHON_SDK_DIR" "$THRIFT_FILE"; then
        # 统计生成的文件数
        PYTHON_FILES=$(find "$PYTHON_SDK_DIR/tsinghua/api" -name "*.py" 2>/dev/null | wc -l)
        log_success "Python SDK生成成功，共 $PYTHON_FILES 个文件"
        
        # 检查关键文件
        if [[ -f "$PYTHON_SDK_DIR/tsinghua/api/ttypes.py" ]]; then
            log_success "✓ ttypes.py 已生成"
        fi
    else
        log_error "Python SDK生成失败"
        return 1
    fi
}

# 验证生成的SDK
verify_sdks() {
    log_info "验证生成的SDK..."
    
    # 验证Java SDK
    if [[ -f "$JAVA_SDK_DIR/com/tsinghua/thrift/api/ApiService.java" ]]; then
        JAVA_SIZE=$(wc -c < "$JAVA_SDK_DIR/com/tsinghua/thrift/api/ApiService.java")
        log_success "✓ Java ApiService.java ($JAVA_SIZE bytes)"
    fi
    
    # 验证Go SDK
    if [[ -f "$GO_SDK_DIR/tsinghua/api/api.go" ]]; then
        GO_SIZE=$(wc -c < "$GO_SDK_DIR/tsinghua/api/api.go")
        log_success "✓ Go api.go ($GO_SIZE bytes)"
    fi
    
    # 验证Python SDK
    if [[ -f "$PYTHON_SDK_DIR/tsinghua/api/ApiService.py" ]]; then
        PYTHON_SIZE=$(wc -c < "$PYTHON_SDK_DIR/tsinghua/api/ApiService.py")
        log_success "✓ Python ApiService.py ($PYTHON_SIZE bytes)"
    fi
}

# 显示生成结果
show_results() {
    echo
    echo "==================================="
    echo "🎉 SDK生成完成！"
    echo "==================================="
    echo
    echo "📁 生成位置:"
    echo "  Java SDK:  $JAVA_SDK_DIR/com/tsinghua/thrift/api/"
    echo "  Go SDK:    $GO_SDK_DIR/tsinghua/api/"
    echo "  Python SDK: $PYTHON_SDK_DIR/tsinghua/api/"
    echo
    echo "📋 新增API支持:"
    echo "  ✅ ParsingRule - 解析规则管理 (包含example字段)"
    echo "  ✅ RunTask - 运行任务管理"
    echo "  ✅ ExtractModelFileRequest - 模型文件提取"
    echo
    echo "🚀 使用方法:"
    echo "  启动应用: mvn spring-boot:run"
    echo "  Thrift服务将在端口9090启动"
    echo
    echo "📖 更多信息请查看各SDK模块的README.md文件"
}

# 清理旧文件
cleanup_old_files() {
    log_info "清理旧的生成文件..."
    
    # 清理Java SDK
    if [[ -d "$JAVA_SDK_DIR/com/tsinghua/thrift/api" ]]; then
        rm -rf "$JAVA_SDK_DIR/com/tsinghua/thrift/api"
        log_info "已清理旧的Java SDK文件"
    fi
    
    # 清理Go SDK
    if [[ -d "$GO_SDK_DIR/tsinghua" ]]; then
        rm -rf "$GO_SDK_DIR/tsinghua"
        log_info "已清理旧的Go SDK文件"
    fi
    
    # 清理Python SDK
    if [[ -d "$PYTHON_SDK_DIR/tsinghua" ]]; then
        rm -rf "$PYTHON_SDK_DIR/tsinghua"
        log_info "已清理旧的Python SDK文件"
    fi
}

# 显示帮助信息
show_help() {
    echo "DataModelGov Thrift SDK 生成脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示帮助信息"
    echo "  -c, --clean    仅清理旧文件，不生成新SDK"
    echo "  -v, --validate 仅验证Thrift文件，不生成SDK"
    echo
    echo "示例:"
    echo "  $0              # 完整生成SDK"
    echo "  $0 --clean      # 清理旧文件"
    echo "  $0 --validate   # 验证Thrift文件"
}

# 主函数
main() {
    local clean_only=false
    local validate_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                clean_only=true
                shift
                ;;
            -v|--validate)
                validate_only=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "==================================="
    echo "🚀 DataModelGov Thrift SDK 生成器"
    echo "==================================="
    echo
    
    # 仅清理模式
    if [[ "$clean_only" == true ]]; then
        cleanup_old_files
        log_success "清理完成"
        exit 0
    fi
    
    # 仅验证模式
    if [[ "$validate_only" == true ]]; then
        check_thrift
        validate_thrift_file
        log_success "验证通过"
        exit 0
    fi
    
    # 完整生成流程
    check_thrift
    validate_thrift_file
    cleanup_old_files
    create_directories
    
    # 生成各语言SDK
    generate_java_sdk || exit 1
    generate_go_sdk || exit 1
    generate_python_sdk || exit 1
    
    # 验证和显示结果
    verify_sdks
    show_results
}

# 执行主函数
main "$@"
