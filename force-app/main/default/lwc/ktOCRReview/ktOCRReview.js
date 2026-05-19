import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference } from 'lightning/navigation';
import getReviewData from '@salesforce/apex/KT_OcrIngestionService.getReviewData';
import applyExtraction from '@salesforce/apex/KT_OcrIngestionService.applyExtraction';

export default class KtOCRReview extends LightningElement {
    @api recordId;
    @api ocrJobId;

    pageStateOcrJobId;
    wiredReviewResult;
    reviewData;
    rows = [];
    selectedFieldKeys = new Set();
    isLoading = true;
    isSubmitting = false;
    errorMessage;
    successMessage;

    get effectiveOcrJobId() {
        return this.ocrJobId || this.recordId || this.pageStateOcrJobId;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get providerLabel() {
        return this.reviewData?.provider || 'OCR Provider';
    }

    get documentTypeLabel() {
        return this.reviewData?.documentType || 'Document Type';
    }

    get statusLabel() {
        return this.reviewData?.status || 'Pending Review';
    }

    get fieldCount() {
        return this.reviewData?.fieldCount || 0;
    }

    get selectedCount() {
        return this.rows.filter((row) => row.isSelected).length;
    }

    get highConfidenceCount() {
        return this.rows.filter((row) => row.highConfidence).length;
    }

    get isApplyDisabled() {
        return this.isSubmitting || !this.effectiveOcrJobId || !this.selectedCount || this.isAccepted;
    }

    get isAccepted() {
        return this.reviewData?.status === 'Accepted';
    }

    get summaryConfidence() {
        if (this.reviewData?.confidenceScore === undefined || this.reviewData?.confidenceScore === null) {
            return 'N/A';
        }
        return `${this.reviewData.confidenceScore}%`;
    }

    @wire(getReviewData, { ocrJobId: '$effectiveOcrJobId' })
    wiredReview(result) {
        this.wiredReviewResult = result;
        this.isLoading = false;
        if (result.data) {
            this.errorMessage = undefined;
            this.successMessage = undefined;
            this.reviewData = result.data;
            this.rows = this.buildRows(result.data.fields || []);
            this.selectedFieldKeys = new Set(
                this.rows.filter((row) => row.highConfidence).map((row) => row.rowKey)
            );
            this.syncSelectedRows();
        } else if (result.error) {
            this.reviewData = undefined;
            this.rows = [];
            this.selectedFieldKeys = new Set();
            this.errorMessage = this.normalizeError(result.error);
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateOcrJobId = state.c__ocrJobId || state.ocrJobId;
    }

    buildRows(fields) {
        return fields.map((field, index) => {
            const rowKey = field.providerFieldPath || `${field.targetObject}.${field.targetField}.${index}`;
            return {
                ...field,
                rowKey,
                isSelected: false,
                extractedValueDisplay: field.extractedValue || 'No extracted value',
                currentValueDisplay: field.currentValue || 'No current value',
                confidenceLabel: this.formatConfidence(field.confidence),
                confidenceClass: this.getConfidenceClass(field.confidence)
            };
        });
    }

    syncSelectedRows() {
        this.rows = this.rows.map((row) => ({
            ...row,
            isSelected: this.selectedFieldKeys.has(row.rowKey)
        }));
    }

    handleToggleSelection(event) {
        const key = event.target.dataset.key;
        if (!key) {
            return;
        }

        if (event.target.checked) {
            this.selectedFieldKeys.add(key);
        } else {
            this.selectedFieldKeys.delete(key);
        }
        this.successMessage = undefined;
        this.syncSelectedRows();
    }

    handleAcceptAllHighConfidence() {
        this.selectedFieldKeys = new Set(
            this.rows.filter((row) => row.highConfidence).map((row) => row.rowKey)
        );
        this.successMessage = undefined;
        this.syncSelectedRows();
    }

    handleClearSelections() {
        this.selectedFieldKeys = new Set();
        this.successMessage = undefined;
        this.syncSelectedRows();
    }

    async handleRefresh() {
        this.isLoading = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        await refreshApex(this.wiredReviewResult);
    }

    async handleApplyAccepted() {
        if (this.isApplyDisabled) {
            return;
        }

        this.isSubmitting = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            const acceptedFieldPaths = this.rows
                .filter((row) => row.isSelected)
                .map((row) => row.providerFieldPath || `${row.targetObject}.${row.targetField}`);

            const result = await applyExtraction({
                ocrJobId: this.effectiveOcrJobId,
                acceptedFieldPaths
            });
            this.successMessage = result?.message || 'Accepted OCR fields were applied successfully.';
            await refreshApex(this.wiredReviewResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    formatConfidence(value) {
        if (value === undefined || value === null || value === '') {
            return 'N/A';
        }
        return `${Number(value).toFixed(2)}%`;
    }

    getConfidenceClass(value) {
        const numericValue = Number(value);
        if (Number.isNaN(numericValue)) {
            return 'confidence-pill';
        }
        if (numericValue >= 90) {
            return 'confidence-pill confidence-pill_success';
        }
        if (numericValue >= 70) {
            return 'confidence-pill confidence-pill_warning';
        }
        return 'confidence-pill confidence-pill_danger';
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}
