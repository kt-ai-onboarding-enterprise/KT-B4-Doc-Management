import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import initiateSigningWorkflow from '@salesforce/apex/KT_ESignatureOrchestrator.initiateSigningWorkflow';

export default class KtESignatureConfig extends LightningElement {
    @api recordId;
    @api vaultId;

    pageStateVaultId;
    provider = 'KT Sign';
    signingOrder = 'Sequential';
    expiryDays = 14;
    signers = [];
    errorMessage;
    isSaving = false;

    providerOptions = [
        { label: 'KT Sign', value: 'KT Sign' },
        { label: 'DocuSign', value: 'DocuSign' },
        { label: 'Adobe Sign', value: 'Adobe Sign' }
    ];

    orderOptions = [
        { label: 'Sequential', value: 'Sequential' },
        { label: 'Parallel', value: 'Parallel' }
    ];

    roleOptions = [
        { label: 'Onboardee', value: 'Onboardee' },
        { label: 'HR Admin', value: 'HR Admin' },
        { label: 'Hiring Manager', value: 'Hiring Manager' },
        { label: 'Legal Counsel', value: 'Legal Counsel' },
        { label: 'Compliance Officer', value: 'Compliance Officer' }
    ];

    connectedCallback() {
        if (!this.signers.length) {
            this.signers = [this.newSigner(1)];
        }
    }

    get effectiveVaultId() {
        return this.vaultId || this.recordId || this.pageStateVaultId;
    }

    get isCreateDisabled() {
        return this.isSaving || !this.effectiveVaultId || !this.hasValidSigners();
    }

    get signerCount() {
        return this.signers.length;
    }

    get workflowSummary() {
        return `${this.provider} · ${this.signingOrder} · ${this.expiryDays} days`;
    }

    handleProviderChange(event) {
        this.provider = event.detail.value;
    }

    handleOrderChange(event) {
        this.signingOrder = event.detail.value;
    }

    handleExpiryChange(event) {
        this.expiryDays = Number(event.target.value);
    }

    handleSignerChange(event) {
        const index = Number(event.currentTarget.dataset.index);
        const field = event.currentTarget.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        this.signers = this.signers.map((signer, signerIndex) => {
            if (signerIndex !== index) {
                return signer;
            }
            return {
                ...signer,
                [field]: field === 'signingOrder' ? Number(value) : value
            };
        });
    }

    addSigner() {
        this.signers = [...this.signers, this.newSigner(this.signers.length + 1)];
    }

    removeSigner(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.signers = this.signers.filter((signer, signerIndex) => signerIndex !== index);
        if (!this.signers.length) {
            this.addSigner();
        }
    }

    async handleCreateWorkflow() {
        if (this.isCreateDisabled) {
            return;
        }

        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const signatureRequestId = await initiateSigningWorkflow({
                vaultId: this.effectiveVaultId,
                config: {
                    signingProvider: this.provider,
                    signingOrder: this.signingOrder,
                    expiryDays: this.expiryDays,
                    signers: this.signers.map(({ signerName, signerEmail, signerRole, signingOrder }) => ({
                        signerName,
                        signerEmail,
                        signerRole,
                        signingOrder
                    }))
                }
            });
            this.dispatchEvent(new CustomEvent('configured', { detail: { signatureRequestId } }));
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isSaving = false;
        }
    }

    hasValidSigners() {
        return this.signers.every((signer) => signer.signerName && signer.signerEmail && signer.signerRole);
    }

    newSigner(order) {
        return {
            key: `${Date.now()}-${order}-${Math.random()}`,
            signerName: '',
            signerEmail: '',
            signerRole: order === 1 ? 'Onboardee' : 'HR Admin',
            signingOrder: order
        };
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Something went wrong.';
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        const state = pageRef?.state || {};
        this.pageStateVaultId = state.c__vaultId || state.vaultId;
    }
}
