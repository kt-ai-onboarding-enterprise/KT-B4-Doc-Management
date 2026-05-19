import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSigningSession from '@salesforce/apex/KT_ESignatureService.getSigningSession';
import completeSignature from '@salesforce/apex/KT_ESignatureOrchestrator.completeSignature';

export default class KtSignaturePad extends LightningElement {
    @api signerId;
    @api sessionToken;

    pageStateSignerId;
    pageStateSessionToken;
    session;
    context;
    canvasInitialized = false;
    isDrawing = false;
    hasStroke = false;
    hasAgreed = false;
    isSubmitting = false;
    errorMessage;
    successMessage;
    latitude;
    longitude;

    get effectiveSignerId() {
        return this.signerId || this.pageStateSignerId;
    }

    get effectiveSessionToken() {
        return this.sessionToken || this.pageStateSessionToken;
    }

    @wire(getSigningSession, { signerId: '$effectiveSignerId', sessionToken: '$effectiveSessionToken' })
    wiredSession({ data, error }) {
        if (data) {
            this.session = data;
            this.errorMessage = data.valid ? undefined : 'Signing session is invalid or expired.';
            if (data.valid) {
                this.captureGeolocation();
                requestAnimationFrame(() => this.initializeCanvas());
            }
        } else if (error) {
            this.session = undefined;
            this.errorMessage = this.normalizeError(error);
        }
    }

    renderedCallback() {
        if (this.hasValidSession && !this.canvasInitialized) {
            this.initializeCanvas();
        }
    }

    get hasValidSession() {
        return Boolean(this.session?.valid);
    }

    get signerName() {
        return this.session?.signerName || '';
    }

    get signerEmail() {
        return this.session?.signerEmail || '';
    }

    get legalNoticeText() {
        return this.session?.legalNoticeText || '';
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.hasAgreed || !this.hasStroke;
    }

    initializeCanvas() {
        const canvas = this.template.querySelector('canvas');
        if (!canvas) {
            return;
        }
        const ratio = window.devicePixelRatio || 1;
        const rect = canvas.getBoundingClientRect();
        canvas.width = Math.max(rect.width * ratio, 1);
        canvas.height = Math.max(rect.height * ratio, 1);
        this.context = canvas.getContext('2d');
        this.context.scale(ratio, ratio);
        this.context.lineCap = 'round';
        this.context.lineJoin = 'round';
        this.context.lineWidth = 2.5;
        this.context.strokeStyle = '#181818';
        this.canvasInitialized = true;
    }

    handlePointerDown(event) {
        if (!this.context) {
            return;
        }
        event.preventDefault();
        const point = this.getCanvasPoint(event);
        this.context.beginPath();
        this.context.moveTo(point.x, point.y);
        this.isDrawing = true;
    }

    handlePointerMove(event) {
        if (!this.isDrawing || !this.context) {
            return;
        }
        event.preventDefault();
        const point = this.getCanvasPoint(event);
        this.context.lineTo(point.x, point.y);
        this.context.stroke();
        this.hasStroke = true;
    }

    handlePointerUp() {
        this.isDrawing = false;
    }

    handleAgreementChange(event) {
        this.hasAgreed = event.target.checked;
    }

    handleClear() {
        const canvas = this.template.querySelector('canvas');
        if (canvas && this.context) {
            const rect = canvas.getBoundingClientRect();
            this.context.clearRect(0, 0, rect.width, rect.height);
        }
        this.hasStroke = false;
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) {
            return;
        }

        this.isSubmitting = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        try {
            const canvas = this.template.querySelector('canvas');
            const signatureBase64 = canvas.toDataURL('image/png');
            const workflowComplete = await completeSignature({
                signerId: this.effectiveSignerId,
                signatureBase64,
                ipAddress: null,
                deviceUserAgent: window.navigator.userAgent,
                latitude: this.latitude,
                longitude: this.longitude,
                sessionToken: this.effectiveSessionToken
            });
            this.successMessage = workflowComplete ? 'Signature complete. The workflow is fully signed.' : 'Signature captured. Waiting for remaining signers.';
            this.dispatchEvent(new CustomEvent('signed', { detail: { workflowComplete } }));
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    getCanvasPoint(event) {
        const canvas = this.template.querySelector('canvas');
        const rect = canvas.getBoundingClientRect();
        return {
            x: event.clientX - rect.left,
            y: event.clientY - rect.top
        };
    }

    captureGeolocation() {
        if (!window.navigator.geolocation) {
            return;
        }
        window.navigator.geolocation.getCurrentPosition(
            (position) => {
                this.latitude = position.coords.latitude;
                this.longitude = position.coords.longitude;
            },
            () => {
                this.latitude = undefined;
                this.longitude = undefined;
            },
            { maximumAge: 60000, timeout: 5000 }
        );
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
        this.pageStateSignerId = state.c__signerId || state.signerId;
        this.pageStateSessionToken = state.c__sessionToken || state.sessionToken;
    }
}
