import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getPreviewData from '@salesforce/apex/KT_DocumentGeneratorService.getPreviewData';
import generateDocument from '@salesforce/apex/KT_DocumentGeneratorService.generateDocument';

export default class KtDocumentPreview extends NavigationMixin(LightningElement) {
    @api recordId;
    @api ktOnboardingId;

    _templateId;
    pageStateOnboardingId;
    pageStateTemplateId;
    draftTemplateId;
    rows = [];
    errorMessage;
    isLoading = false;

    @api
    get templateId() {
        return this._templateId || this.draftTemplateId || this.pageStateTemplateId;
    }

    set templateId(value) {
        this._templateId = value;
        this.draftTemplateId = value;
    }

    get effectiveOnboardingId() {
        return this.ktOnboardingId || this.recordId || this.pageStateOnboardingId;
    }

    get hasTemplateApiValue() {
        return Boolean(this._templateId);
    }

    get isGenerateDisabled() {
        return this.isLoading || !this.templateId || !this.effectiveOnboardingId;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get completionStyle() {
        return `width: ${this.completionPercent}%;`;
    }

    get completionPercent() {
        if (!this.rows.length) {
            return 0;
        }
        const resolved = this.rows.filter((row) => row.resolved).length;
        return Math.round((resolved / this.rows.length) * 100);
    }

    get resolvedCount() {
        return this.rows.filter((row) => row.resolved).length;
    }

    get unresolvedCount() {
        return this.rows.length - this.resolvedCount;
    }

    @wire(getPreviewData, { templateId: '$templateId', onboardingId: '$effectiveOnboardingId' })
    wiredPreview({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.errorMessage = undefined;
            this.rows = Object.keys(data)
                .sort()
                .map((token) => {
                    const value = data[token] || token;
                    const resolved = value !== token;
                    return {
                        token,
                        value,
                        resolved,
                        rowClass: resolved ? 'preview-row' : 'preview-row preview-row_unresolved'
                    };
                });
        } else if (error) {
            this.rows = [];
            this.errorMessage = this.normalizeError(error);
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateOnboardingId = state.c__onboardingId || state.onboardingId;
        this.pageStateTemplateId = state.c__templateId || state.templateId;
    }

    handleTemplateChange(event) {
        this.draftTemplateId = event.target.value;
        this.errorMessage = undefined;
        this.isLoading = Boolean(this.draftTemplateId && this.effectiveOnboardingId);
        this.dispatchEvent(
            new CustomEvent('templatechange', {
                detail: { templateId: this.draftTemplateId }
            })
        );
    }

    async handleGenerate() {
        if (this.isGenerateDisabled) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const result = await generateDocument({
                onboardingId: this.effectiveOnboardingId,
                templateId: this.templateId
            });
            this.dispatchEvent(new CustomEvent('generated', { detail: result }));
            if (result?.vaultEntryId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result.vaultEntryId,
                        objectApiName: 'KT_DocumentVault__c',
                        actionName: 'view'
                    }
                });
            }
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
