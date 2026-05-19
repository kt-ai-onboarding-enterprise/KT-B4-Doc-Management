import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference } from 'lightning/navigation';
import getVaultEntries from '@salesforce/apex/KT_DocumentVaultService.getVaultEntries';

export default class KtDocumentVaultPortal extends LightningElement {
    @api recordId;
    @api ktOnboardingId;
    @api uploadFlowApiName;

    pageStateOnboardingId;
    wiredResult;
    documents = [];
    isLoading = false;
    errorMessage;
    showUploadFlow = false;
    selectedDocumentRequestId;
    searchTerm = '';

    connectedCallback() {
        this.restoreCachedDocuments();
    }

    get effectiveOnboardingId() {
        return this.ktOnboardingId || this.recordId || this.pageStateOnboardingId;
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get hasUploadFlow() {
        return Boolean(this.uploadFlowApiName);
    }

    get completedCount() {
        return this.documents.filter((doc) => doc.status === 'Verified' || doc.status === 'Signed' || doc.status === 'Archived').length;
    }

    get visibleDocuments() {
        const search = this.searchTerm.trim().toLowerCase();
        return this.documents.filter((doc) => {
            return (
                !search ||
                String(doc.documentName || '').toLowerCase().includes(search) ||
                String(doc.documentType || '').toLowerCase().includes(search) ||
                String(doc.status || '').toLowerCase().includes(search)
            );
        });
    }

    get hasVisibleDocuments() {
        return this.visibleDocuments.length > 0;
    }

    get visibleCount() {
        return this.visibleDocuments.length;
    }

    get completionLabel() {
        return `${this.completedCount}/${this.documents.length} complete`;
    }

    get completionStyle() {
        const percent = this.documents.length ? Math.round((this.completedCount / this.documents.length) * 100) : 0;
        return `width: ${percent}%;`;
    }

    get flowInputVariables() {
        return [
            { name: 'recordId', type: 'String', value: this.effectiveOnboardingId },
            { name: 'documentRequestId', type: 'String', value: this.selectedDocumentRequestId }
        ];
    }

    @wire(getVaultEntries, { onboardingId: '$effectiveOnboardingId' })
    wiredDocuments(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.errorMessage = undefined;
            this.documents = result.data.map((doc) => this.decorateDocument(doc));
            this.cacheDocuments();
        } else if (result.error) {
            this.errorMessage = 'Showing cached documents.';
            this.restoreCachedDocuments();
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateOnboardingId = state.c__onboardingId || state.onboardingId;
    }

    decorateDocument(doc) {
        return {
            ...doc,
            cardClass: doc.isExpired ? 'document-card document-card_expired' : 'document-card',
            statusClass: `status-pill ${this.statusClassName(doc.status)}`,
            viewDisabled: !doc.contentDocumentId
        };
    }

    async handleRefresh() {
        this.isLoading = true;
        await refreshApex(this.wiredResult);
        this.isLoading = false;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    openUploadFlow(event) {
        const doc = this.documents.find((item) => item.id === event.currentTarget.dataset.id);
        this.selectedDocumentRequestId = doc?.documentRequestId;
        this.showUploadFlow = true;
    }

    closeUploadFlow() {
        this.showUploadFlow = false;
        this.selectedDocumentRequestId = undefined;
    }

    async handleInlineUpload() {
        this.closeUploadFlow();
        await this.handleRefresh();
    }

    async handleFlowStatus(event) {
        if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
            this.closeUploadFlow();
            await this.handleRefresh();
        }
    }

    handleView(event) {
        const doc = this.documents.find((item) => item.id === event.currentTarget.dataset.id);
        if (doc?.contentDocumentId) {
            window.open(`/sfc/servlet.shepherd/document/download/${doc.contentDocumentId}`, '_blank');
        }
    }

    statusClassName(status) {
        return String(status || '').toLowerCase().replace(/\s+/g, '-');
    }

    cacheDocuments() {
        try {
            window.localStorage.setItem(this.cacheKey, JSON.stringify(this.documents));
        } catch (error) {
            // Offline cache is opportunistic.
        }
    }

    restoreCachedDocuments() {
        try {
            const cached = window.localStorage.getItem(this.cacheKey);
            if (cached) {
                this.documents = JSON.parse(cached);
            }
        } catch (error) {
            this.documents = [];
        }
    }

    get cacheKey() {
        return `ktDocumentVaultPortal:${this.effectiveOnboardingId || 'unknown'}`;
    }
}
