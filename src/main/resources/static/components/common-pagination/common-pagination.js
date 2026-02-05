class CommonPagination extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalRecords = 0;
        this.maxVisiblePages = 7; // 最大显示页码数
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        this.bindEvents();
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/common-pagination/common-pagination.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/common-pagination/common-pagination.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.shadowRoot.innerHTML = this.getFallbackHTML();
        }
    }

    getFallbackHTML() {
        return `
            <div class="pagination-container">
                <div class="pagination-info">
                    <span class="pagination-text">显示第 <span class="start-record">1</span>-<span class="end-record">10</span> 条，共 <span class="total-records">0</span> 条</span>
                    <div class="page-size-selector">
                        <span class="page-size-label">每页显示：</span>
                        <select class="page-size-select">
                            <option value="10">10条</option>
                            <option value="20">20条</option>
                            <option value="50">50条</option>
                            <option value="100">100条</option>
                        </select>
                    </div>
                </div>
                <div class="pagination-controls">
                    <button class="page-btn first-page" title="首页">首页</button>
                    <button class="page-btn prev-page" title="上一页">上一页</button>
                    <div class="page-numbers">
                        <!-- 页码按钮将动态生成 -->
                    </div>
                    <button class="page-btn next-page" title="下一页">下一页</button>
                    <button class="page-btn last-page" title="尾页">尾页</button>
                </div>
            </div>
        `;
    }

    render() {
        this.updateInfo();
        this.updatePageNumbers();
        this.updateButtonStates();
    }

    updateInfo() {
        const startRecord = this.shadowRoot.querySelector('.start-record');
        const endRecord = this.shadowRoot.querySelector('.end-record');
        const totalRecords = this.shadowRoot.querySelector('.total-records');
        const pageSizeSelect = this.shadowRoot.querySelector('.page-size-select');

        if (startRecord && endRecord && totalRecords) {
            const totalPages = Math.ceil(this.totalRecords / this.pageSize);
            const start = this.totalRecords === 0 ? 0 : (this.currentPage - 1) * this.pageSize + 1;
            const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);

            startRecord.textContent = start;
            endRecord.textContent = end;
            totalRecords.textContent = this.totalRecords;
        }

        if (pageSizeSelect) {
            pageSizeSelect.value = this.pageSize.toString();
        }
    }

    updatePageNumbers() {
        const pageNumbersContainer = this.shadowRoot.querySelector('.page-numbers');
        if (!pageNumbersContainer) return;

        const totalPages = Math.ceil(this.totalRecords / this.pageSize);
        pageNumbersContainer.innerHTML = '';

        if (totalPages <= 1) return;

        const pageNumbers = this.calculateVisiblePages(totalPages);
        
        pageNumbers.forEach(pageNum => {
            if (pageNum === '...') {
                const ellipsis = document.createElement('span');
                ellipsis.className = 'page-ellipsis';
                ellipsis.textContent = '...';
                pageNumbersContainer.appendChild(ellipsis);
            } else {
                const pageBtn = document.createElement('button');
                pageBtn.className = 'page-number';
                pageBtn.textContent = pageNum;
                pageBtn.dataset.page = pageNum;
                
                if (pageNum === this.currentPage) {
                    pageBtn.classList.add('active');
                }
                
                pageBtn.addEventListener('click', () => {
                    this.goToPage(pageNum);
                });
                
                pageNumbersContainer.appendChild(pageBtn);
            }
        });
    }

    calculateVisiblePages(totalPages) {
        const pages = [];
        const half = Math.floor(this.maxVisiblePages / 2);

        if (totalPages <= this.maxVisiblePages) {
            // 总页数少于最大显示页数，显示所有页码
            for (let i = 1; i <= totalPages; i++) {
                pages.push(i);
            }
        } else {
            // 总页数较多，需要省略显示
            if (this.currentPage <= half + 1) {
                // 当前页在前半部分
                for (let i = 1; i <= this.maxVisiblePages - 2; i++) {
                    pages.push(i);
                }
                pages.push('...');
                pages.push(totalPages);
            } else if (this.currentPage >= totalPages - half) {
                // 当前页在后半部分
                pages.push(1);
                pages.push('...');
                for (let i = totalPages - this.maxVisiblePages + 3; i <= totalPages; i++) {
                    pages.push(i);
                }
            } else {
                // 当前页在中间部分
                pages.push(1);
                pages.push('...');
                for (let i = this.currentPage - half + 1; i <= this.currentPage + half - 1; i++) {
                    pages.push(i);
                }
                pages.push('...');
                pages.push(totalPages);
            }
        }

        return pages;
    }

    updateButtonStates() {
        const firstBtn = this.shadowRoot.querySelector('.first-page');
        const prevBtn = this.shadowRoot.querySelector('.prev-page');
        const nextBtn = this.shadowRoot.querySelector('.next-page');
        const lastBtn = this.shadowRoot.querySelector('.last-page');

        const totalPages = Math.ceil(this.totalRecords / this.pageSize);
        const canGoPrev = this.currentPage > 1;
        const canGoNext = this.currentPage < totalPages;

        if (firstBtn) {
            firstBtn.disabled = !canGoPrev;
        }
        if (prevBtn) {
            prevBtn.disabled = !canGoPrev;
        }
        if (nextBtn) {
            nextBtn.disabled = !canGoNext;
        }
        if (lastBtn) {
            lastBtn.disabled = !canGoNext;
        }
    }

    bindEvents() {
        // 首页按钮
        const firstBtn = this.shadowRoot.querySelector('.first-page');
        if (firstBtn) {
            firstBtn.addEventListener('click', () => this.goToPage(1));
        }

        // 上一页按钮
        const prevBtn = this.shadowRoot.querySelector('.prev-page');
        if (prevBtn) {
            prevBtn.addEventListener('click', () => this.goToPrevPage());
        }

        // 下一页按钮
        const nextBtn = this.shadowRoot.querySelector('.next-page');
        if (nextBtn) {
            nextBtn.addEventListener('click', () => this.goToNextPage());
        }

        // 尾页按钮
        const lastBtn = this.shadowRoot.querySelector('.last-page');
        if (lastBtn) {
            lastBtn.addEventListener('click', () => this.goToLastPage());
        }

        // 每页显示条数选择
        const pageSizeSelect = this.shadowRoot.querySelector('.page-size-select');
        if (pageSizeSelect) {
            pageSizeSelect.addEventListener('change', (e) => {
                this.changePageSize(parseInt(e.target.value));
            });
        }
    }

    // 公共方法
    setPagination(currentPage, pageSize, totalRecords) {
        this.currentPage = currentPage;
        this.pageSize = pageSize;
        this.totalRecords = totalRecords;
        this.render();
    }

    goToPage(page) {
        if (page < 1 || page > Math.ceil(this.totalRecords / this.pageSize)) {
            return;
        }
        
        this.currentPage = page;
        this.render();
        this.dispatchChangeEvent();
    }

    goToPrevPage() {
        if (this.currentPage > 1) {
            this.goToPage(this.currentPage - 1);
        }
    }

    goToNextPage() {
        const totalPages = Math.ceil(this.totalRecords / this.pageSize);
        if (this.currentPage < totalPages) {
            this.goToPage(this.currentPage + 1);
        }
    }

    goToLastPage() {
        const totalPages = Math.ceil(this.totalRecords / this.pageSize);
        this.goToPage(totalPages);
    }

    changePageSize(newPageSize) {
        this.pageSize = newPageSize;
        // 重置到第一页
        this.currentPage = 1;
        this.render();
        this.dispatchChangeEvent();
    }

    dispatchChangeEvent() {
        const event = new CustomEvent('pagination-change', {
            detail: {
                currentPage: this.currentPage,
                pageSize: this.pageSize,
                totalRecords: this.totalRecords,
                totalPages: Math.ceil(this.totalRecords / this.pageSize)
            }
        });
        this.dispatchEvent(event);
    }

    // 获取分页信息
    getPaginationInfo() {
        return {
            currentPage: this.currentPage,
            pageSize: this.pageSize,
            totalRecords: this.totalRecords,
            totalPages: Math.ceil(this.totalRecords / this.pageSize),
            startIndex: (this.currentPage - 1) * this.pageSize,
            endIndex: Math.min(this.currentPage * this.pageSize, this.totalRecords) - 1
        };
    }

    // 重置分页
    reset() {
        this.currentPage = 1;
        this.totalRecords = 0;
        this.render();
    }
}

// 注册自定义元素
customElements.define('common-pagination', CommonPagination);
