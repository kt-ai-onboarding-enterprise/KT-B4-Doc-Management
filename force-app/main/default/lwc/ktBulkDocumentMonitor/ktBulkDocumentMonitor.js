import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import getBulkJobStatus from '@salesforce/apex/KT_BulkDocumentJobService.getBulkJobStatus';
import getRecentBulkJobs from '@salesforce/apex/KT_BulkDocumentJobService.getRecentBulkJobs';

const REFRESH_INTERVAL_MS = 10000;

export default class KtBulkDocumentMonitor extends NavigationMixin(LightningElement) {
    recentJobLimit = 8;

    _jobId;
    _recordId;
    draftJobId;
    effectiveJobId;
    selectedJobId;
    pageStateJobId;

    job;
    recentJobs = [];
    errorMessage;
    isLoading = false;

    refreshHandle;
    wiredStatusResult;
    wiredRecentJobsResult;

    @api
    get jobId() {
        return this._jobId;
    }

    set jobId(value) {
        this._jobId = value;
        if (value && !this.draftJobId) {
            this.draftJobId = value;
        }
        this.syncEffectiveJobId();
    }

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.syncEffectiveJobId();
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const state = pageReference ? pageReference.state || {} : {};
        this.pageStateJobId = state.c__jobId || state.jobId || null;
        if (this.pageStateJobId && !this.draftJobId) {
            this.draftJobId = this.pageStateJobId;
        }
        this.syncEffectiveJobId();
    }

    @wire(getBulkJobStatus, { jobId: '$effectiveJobId' })
    wiredJobStatus(result) {
        this.wiredStatusResult = result;
        if (!this.effectiveJobId) {
            this.job = undefined;
            this.isLoading = false;
            return;
        }

        if (result.data) {
            this.errorMessage = undefined;
            this.job = this.decorateJob(result.data);
            this.isLoading = false;
            if (this.job.complete) {
                this.stopAutoRefresh();
            } else {
                this.startAutoRefresh();
            }
        } else if (result.error) {
            this.job = undefined;
            this.errorMessage = this.normalizeError(result.error);
            this.isLoading = false;
        }
    }

    @wire(getRecentBulkJobs, { maxResults: '$recentJobLimit' })
    wiredRecentJobs(result) {
        this.wiredRecentJobsResult = result;
        if (result.data) {
            this.recentJobs = result.data.map((row) => this.decorateJob(row));
        } else if (result.error && !this.hasJob) {
            this.recentJobs = [];
            this.errorMessage = this.normalizeError(result.error);
        }
    }

    connectedCallback() {
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    get hasJob() {
        return Boolean(this.job);
    }

    get hasRecentJobs() {
        return !this.hasJob && this.recentJobs.length > 0;
    }

    get hasFailureDetails() {
        return this.hasJob && this.job.failureDetails.length > 0;
    }

    get shouldShowSelector() {
        return !this._jobId && !this._recordId && !this.pageStateJobId;
    }

    get shouldShowLoadButton() {
        return this.shouldShowSelector;
    }

    get showClearButton() {
        return this.shouldShowSelector && Boolean(this.effectiveJobId);
    }

    get isMonitorDisabled() {
        return this.isLoading || !this.draftJobId;
    }

    handleJobIdInput(event) {
        this.draftJobId = event.target.value ? event.target.value.trim() : '';
    }

    handleLoadJob() {
        if (!this.draftJobId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        this.selectedJobId = this.draftJobId;
        this.syncEffectiveJobId();
        this.startAutoRefresh();
    }

    handleSelectRecent(event) {
        this.draftJobId = event.currentTarget.dataset.id;
        this.handleLoadJob();
    }

    handleOpenJob() {
        if (!this.effectiveJobId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.effectiveJobId,
                objectApiName: 'KT_Bulk_Document_Job__c',
                actionName: 'view'
            }
        });
    }

    handleClearSelection() {
        this.selectedJobId = undefined;
        this.draftJobId = '';
        this.errorMessage = undefined;
        this.job = undefined;
        this.syncEffectiveJobId();
        this.stopAutoRefresh();
    }

    async handleRefresh() {
        await this.refreshData(true);
    }

    syncEffectiveJobId() {
        this.effectiveJobId = this._jobId || this._recordId || this.pageStateJobId || this.selectedJobId || null;
    }

    startAutoRefresh() {
        if (this.refreshHandle) {
            return;
        }
        this.refreshHandle = window.setInterval(() => {
            this.refreshData(false);
        }, REFRESH_INTERVAL_MS);
    }

    stopAutoRefresh() {
        if (!this.refreshHandle) {
            return;
        }
        window.clearInterval(this.refreshHandle);
        this.refreshHandle = undefined;
    }

    async refreshData(showSpinner) {
        const refreshCalls = [];
        if (this.effectiveJobId && this.wiredStatusResult && (!this.job || !this.job.complete || showSpinner)) {
            refreshCalls.push(refreshApex(this.wiredStatusResult));
        }
        if (this.wiredRecentJobsResult) {
            refreshCalls.push(refreshApex(this.wiredRecentJobsResult));
        }
        if (refreshCalls.length === 0) {
            return;
        }

        if (showSpinner) {
            this.isLoading = true;
        }
        this.errorMessage = undefined;
        try {
            await Promise.all(refreshCalls);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            if (showSpinner) {
                this.isLoading = false;
            }
        }
    }

    decorateJob(row) {
        const failureDetails = row.failureSummary
            ? row.failureSummary
                .split('\n')
                .filter((item) => item)
                .map((message, index) => ({
                    key: `${row.jobId}-${index}`,
                    message
                }))
            : [];

        return {
            ...row,
            progressValue: Number(row.progressPercent || 0),
            progressCaption: `${row.processed} of ${row.totalRecords} processed`,
            statusClass: `status-pill ${this.statusClassName(row.status)}`,
            startedAtLabel: this.formatDateTime(row.startedAt),
            completedAtLabel: this.formatDateTime(row.completedAt),
            estimatedCompletionLabel: this.resolveEstimatedCompletionLabel(row),
            failureDetails,
            hasFailureCountWithoutSummary: row.failureCount > 0 && failureDetails.length === 0
        };
    }

    resolveEstimatedCompletionLabel(row) {
        if (row.complete) {
            return row.completedAt ? this.formatDateTime(row.completedAt) : 'Completed';
        }
        if (row.estimatedCompletionAt) {
            return this.formatDateTime(row.estimatedCompletionAt);
        }
        return 'Calculating';
    }

    formatDateTime(value) {
        if (!value) {
            return '--';
        }
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date(value));
    }

    statusClassName(status) {
        return (status || 'unknown')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '');
    }

    normalizeError(error) {
        if (Array.isArray(error && error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return (error && error.body && error.body.message) || error.message || 'Something went wrong.';
    }
}
