import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference } from 'lightning/navigation';
import getDocumentRequests from '@salesforce/apex/KT_DocumentChecklistService.getDocumentRequests';
import markUploadRequested from '@salesforce/apex/KT_DocumentChecklistService.markUploadRequested';
import waiveDocumentRequest from '@salesforce/apex/KT_DocumentChecklistService.waiveDocumentRequest';
import generateDocument from '@salesforce/apex/KT_DocumentGeneratorService.generateDocument';

export default class KtDocumentRequestList extends LightningElement {
    @api recordId;
    @api ktOnboardingId;

    pageStateOnboardingId;
    wiredResult;
    rows = [];
    errorMessage;
    isLoading = false;
    isWaiveModalOpen = false;
    waiverReason = '';
    selectedRequestId;
    searchTerm = '';
    statusFilter = 'All';

    get effectiveOnboardingId() {
        return this.ktOnboardingId || this.recordId || this.pageStateOnboardingId;
    }

    get hasRequests() {
        return this.rows.length > 0;
    }

    get totalCount() {
        return this.rows.length;
    }

    get visibleRows() {
        const search = this.searchTerm.trim().toLowerCase();
        return this.rows.filter((row) => {
            const matchesStatus = this.statusFilter === 'All' || row.status === this.statusFilter;
            const matchesSearch =
                !search ||
                String(row.templateName || '').toLowerCase().includes(search) ||
                String(row.documentDirection || '').toLowerCase().includes(search) ||
                String(row.status || '').toLowerCase().includes(search);
            return matchesStatus && matchesSearch;
        });
    }

    get hasVisibleRows() {
        return this.visibleRows.length > 0;
    }

    get visibleCount() {
        return this.visibleRows.length;
    }

    get completedCount() {
        return this.rows.filter((row) => row.status === 'Complete' || row.status === 'Waived').length;
    }

    get openCount() {
        return this.rows.filter((row) => row.status !== 'Complete' && row.status !== 'Waived').length;
    }

    get overdueCount() {
        return this.rows.filter((row) => row.isOverdue).length;
    }

    get statusOptions() {
        const statuses = Array.from(new Set(this.rows.map((row) => row.status).filter(Boolean))).sort();
        return [{ label: 'All Statuses', value: 'All' }, ...statuses.map((status) => ({ label: status, value: status }))];
    }

    get completionStyle() {
        const percent = this.totalCount ? Math.round((this.completedCount / this.totalCount) * 100) : 0;
        return `width: ${percent}%;`;
    }

    @wire(getDocumentRequests, { onboardingId: '$effectiveOnboardingId' })
    wiredRequests(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.errorMessage = undefined;
            this.rows = result.data.map((row) => this.decorateRow(row));
        } else if (result.error) {
            this.rows = [];
            this.errorMessage = this.normalizeError(result.error);
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateOnboardingId = state.c__onboardingId || state.onboardingId;
    }

    decorateRow(row) {
        const isComplete = row.status === 'Complete' || row.status === 'Waived';
        return {
            ...row,
            dueDateLabel: row.dueDate || '',
            requiredLabel: row.isRequired ? 'Yes' : 'No',
            generateDisabled: !row.templateId || isComplete,
            rowClass: row.isOverdue ? 'overdue-row' : '',
            statusClass: `status-pill ${this.statusClassName(row.status)}`
        };
    }

    statusClassName(status) {
        return String(status || '').toLowerCase().replace(/\s+/g, '-');
    }

    async handleRefresh() {
        this.isLoading = true;
        await refreshApex(this.wiredResult);
        this.isLoading = false;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
    }

    async handleGenerate(event) {
        const templateId = event.currentTarget.dataset.templateId;
        if (!templateId || !this.effectiveOnboardingId) {
            return;
        }
        await this.runAction(() =>
            generateDocument({
                onboardingId: this.effectiveOnboardingId,
                templateId
            })
        );
        this.dispatchEvent(new CustomEvent('generated'));
    }

    async handleRequestUpload(event) {
        await this.runAction(() => markUploadRequested({ requestId: event.currentTarget.dataset.requestId }));
    }

    openWaiveModal(event) {
        this.selectedRequestId = event.currentTarget.dataset.requestId;
        this.waiverReason = '';
        this.isWaiveModalOpen = true;
    }

    closeWaiveModal() {
        this.isWaiveModalOpen = false;
        this.selectedRequestId = undefined;
        this.waiverReason = '';
    }

    handleWaiverReasonChange(event) {
        this.waiverReason = event.target.value;
    }

    async handleWaive() {
        if (!this.selectedRequestId || !this.waiverReason) {
            return;
        }
        await this.runAction(() =>
            waiveDocumentRequest({
                requestId: this.selectedRequestId,
                waiverReason: this.waiverReason
            })
        );
        this.closeWaiveModal();
    }

    async runAction(action) {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            await action();
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}
