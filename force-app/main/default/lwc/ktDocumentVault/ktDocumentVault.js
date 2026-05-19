import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference } from 'lightning/navigation';
import getVaultEntries from '@salesforce/apex/KT_DocumentVaultService.getVaultEntries';
import getVersionHistory from '@salesforce/apex/KT_DocumentVaultService.getVersionHistory';
import archiveVaultEntry from '@salesforce/apex/KT_DocumentVaultService.archiveVaultEntry';
import requestSignature from '@salesforce/apex/KT_DocumentVaultService.requestSignature';
import triggerOCR from '@salesforce/apex/KT_DocumentVaultService.triggerOCR';
import waiveDocument from '@salesforce/apex/KT_DocumentVaultService.waiveDocument';

export default class KtDocumentVault extends LightningElement {
    @api recordId;
    @api ktOnboardingId;

    pageStateOnboardingId;
    wiredVaultResult;
    entries = [];
    sections = [];
    expandedTypes = new Set();
    versions = [];
    previewUrl;
    previewTitle;
    selectedVaultEntryId;
    waiverReason = '';
    isWaiveModalOpen = false;
    isLoading = false;
    errorMessage;
    searchTerm = '';
    statusFilter = 'All';

    get effectiveOnboardingId() {
        return this.ktOnboardingId || this.recordId || this.pageStateOnboardingId;
    }

    get hasSections() {
        return this.sections.length > 0;
    }

    get documentCount() {
        return this.entries.length;
    }

    get visibleEntries() {
        const search = this.searchTerm.trim().toLowerCase();
        return this.entries.filter((entry) => {
            const matchesStatus = this.statusFilter === 'All' || entry.status === this.statusFilter;
            const matchesSearch =
                !search ||
                String(entry.documentName || '').toLowerCase().includes(search) ||
                String(entry.documentType || '').toLowerCase().includes(search) ||
                String(entry.regulatoryTag || '').toLowerCase().includes(search);
            return matchesStatus && matchesSearch;
        });
    }

    get visibleDocumentCount() {
        return this.visibleEntries.length;
    }

    get signaturePendingCount() {
        return this.entries.filter((entry) => entry.signatureStatus === 'Pending').length;
    }

    get ocrReviewCount() {
        return this.entries.filter((entry) => entry.ocrStatus === 'Review Required').length;
    }

    get statusOptions() {
        const statuses = Array.from(new Set(this.entries.map((entry) => entry.status).filter(Boolean))).sort();
        return [{ label: 'All Statuses', value: 'All' }, ...statuses.map((status) => ({ label: status, value: status }))];
    }

    get hasPreview() {
        return Boolean(this.previewUrl);
    }

    get hasVersions() {
        return this.versions.length > 0;
    }

    @wire(getVaultEntries, { onboardingId: '$effectiveOnboardingId' })
    wiredVault(result) {
        this.wiredVaultResult = result;
        this.isLoading = false;
        if (result.data) {
            this.errorMessage = undefined;
            this.entries = result.data.map((entry) => this.decorateEntry(entry));
            this.sections = this.groupEntries(this.visibleEntries);
        } else if (result.error) {
            this.entries = [];
            this.sections = [];
            this.errorMessage = this.normalizeError(result.error);
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateOnboardingId = state.c__onboardingId || state.onboardingId;
    }

    decorateEntry(entry) {
        return {
            ...entry,
            expiryLabel: entry.expiryDate || '',
            statusClass: `status-pill ${this.statusClassName(entry.status)}`
        };
    }

    groupEntries(entries) {
        const byType = new Map();
        entries.forEach((entry) => {
            const type = entry.documentType || 'Other';
            if (!byType.has(type)) {
                byType.set(type, []);
            }
            byType.get(type).push(entry);
        });
        return Array.from(byType.keys()).map((type) => ({
            type,
            iconName: this.iconForType(type),
            expanded: this.expandedTypes.has(type) || this.expandedTypes.size === 0,
            count: byType.get(type).length,
            entries: byType.get(type)
        }));
    }

    toggleSection(event) {
        const type = event.currentTarget.dataset.type;
        if (this.expandedTypes.has(type)) {
            this.expandedTypes.delete(type);
        } else {
            this.expandedTypes.add(type);
        }
        this.sections = this.groupEntries(this.visibleEntries);
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        this.sections = this.groupEntries(this.visibleEntries);
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
        this.sections = this.groupEntries(this.visibleEntries);
    }

    async handleRefresh() {
        this.isLoading = true;
        await refreshApex(this.wiredVaultResult);
        this.isLoading = false;
    }

    handlePreview(event) {
        const entry = this.findEntry(event.currentTarget.dataset.id);
        if (!entry?.contentDocumentId) {
            return;
        }
        this.previewTitle = entry.documentName;
        this.previewUrl = `/sfc/servlet.shepherd/document/download/${entry.contentDocumentId}`;
    }

    handleDownload(event) {
        const entry = this.findEntry(event.currentTarget.dataset.id);
        if (entry?.contentDocumentId) {
            window.open(`/sfc/servlet.shepherd/document/download/${entry.contentDocumentId}`, '_blank');
        }
    }

    async handleRequestSignature(event) {
        await this.runAction(() => requestSignature({ vaultEntryId: event.currentTarget.dataset.id }));
    }

    async handleTriggerOCR(event) {
        await this.runAction(() => triggerOCR({ vaultEntryId: event.currentTarget.dataset.id }));
    }

    async handleArchive(event) {
        await this.runAction(() => archiveVaultEntry({ vaultEntryId: event.currentTarget.dataset.id }));
    }

    async handleVersionHistory(event) {
        const entry = this.findEntry(event.currentTarget.dataset.id);
        if (!entry?.contentDocumentId) {
            this.versions = [];
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.versions = await getVersionHistory({ contentDocumentId: entry.contentDocumentId });
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    openWaiveModal(event) {
        this.selectedVaultEntryId = event.currentTarget.dataset.id;
        this.waiverReason = '';
        this.isWaiveModalOpen = true;
    }

    closeWaiveModal() {
        this.isWaiveModalOpen = false;
        this.selectedVaultEntryId = undefined;
        this.waiverReason = '';
    }

    handleWaiverReasonChange(event) {
        this.waiverReason = event.target.value;
    }

    async handleWaive() {
        if (!this.selectedVaultEntryId || !this.waiverReason) {
            return;
        }
        await this.runAction(() =>
            waiveDocument({
                vaultEntryId: this.selectedVaultEntryId,
                waiverReason: this.waiverReason
            })
        );
        this.closeWaiveModal();
    }

    closePreview() {
        this.previewUrl = undefined;
        this.previewTitle = undefined;
    }

    closeVersions() {
        this.versions = [];
    }

    async runAction(action) {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            await action();
            await refreshApex(this.wiredVaultResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    findEntry(id) {
        return this.entries.find((entry) => entry.id === id);
    }

    statusClassName(status) {
        return String(status || '').toLowerCase().replace(/\s+/g, '-');
    }

    iconForType(type) {
        if (type === 'Identity Document') {
            return 'standard:contact';
        }
        if (type === 'Certificate') {
            return 'standard:reward';
        }
        if (type === 'Compliance Record') {
            return 'standard:approval';
        }
        return 'standard:file';
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}
