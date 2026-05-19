import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import uploadDocument from '@salesforce/apex/KT_DocumentUploadService.uploadDocument';

const MAX_BYTES = 26214400;
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg', 'png', 'docx'];

export default class KtDocumentUpload extends LightningElement {
    @api recordId;
    @api ktOnboardingId;
    @api documentRequestId;

    pageStateOnboardingId;
    pageStateDocumentRequestId;
    selectedFile;
    selectedFileName = 'Drop a file or choose one';
    isDragging = false;
    isUploading = false;
    progressValue = 0;
    errorMessage;
    successMessage;

    get effectiveOnboardingId() {
        return this.ktOnboardingId || this.recordId || this.pageStateOnboardingId;
    }

    get effectiveDocumentRequestId() {
        return this.documentRequestId || this.pageStateDocumentRequestId;
    }

    get acceptedTypes() {
        return ALLOWED_EXTENSIONS.map((extension) => `.${extension}`).join(',');
    }

    get isUploadDisabled() {
        return this.isUploading || !this.selectedFile || !this.effectiveOnboardingId;
    }

    get dropZoneClass() {
        return this.isDragging ? 'drop-zone drop-zone_active' : 'drop-zone';
    }

    handleDragOver(event) {
        event.preventDefault();
        this.isDragging = true;
    }

    handleDragLeave() {
        this.isDragging = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragging = false;
        const [file] = event.dataTransfer.files;
        this.selectFile(file);
    }

    handleFileChange(event) {
        const [file] = event.target.files;
        this.selectFile(file);
    }

    selectFile(file) {
        this.errorMessage = undefined;
        this.successMessage = undefined;
        this.progressValue = 0;

        if (!file) {
            this.selectedFile = undefined;
            this.selectedFileName = 'Drop a file or choose one';
            return;
        }

        const extension = this.getExtension(file.name);
        if (!ALLOWED_EXTENSIONS.includes(extension)) {
            this.selectedFile = undefined;
            this.selectedFileName = 'Drop a file or choose one';
            this.errorMessage = 'Unsupported file type.';
            return;
        }

        if (file.size > MAX_BYTES) {
            this.selectedFile = undefined;
            this.selectedFileName = 'Drop a file or choose one';
            this.errorMessage = 'File exceeds the 25MB limit.';
            return;
        }

        this.selectedFile = file;
        this.selectedFileName = file.name;
    }

    async handleUpload() {
        if (this.isUploadDisabled) {
            return;
        }

        this.isUploading = true;
        this.errorMessage = undefined;
        this.successMessage = undefined;
        this.progressValue = 20;

        try {
            const base64Data = await this.readFileAsDataUrl(this.selectedFile);
            this.progressValue = 65;
            const result = await uploadDocument({
                onboardingId: this.effectiveOnboardingId,
                documentRequestId: this.effectiveDocumentRequestId,
                fileName: this.selectedFile.name,
                base64Data,
                contentType: this.selectedFile.type
            });
            this.progressValue = 100;
            if (result?.success === false) {
                this.errorMessage = result.message;
            } else {
                this.successMessage = result?.message || 'Document uploaded successfully.';
            }
            this.dispatchEvent(new CustomEvent('uploaded', { detail: result }));
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isUploading = false;
        }
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    getExtension(fileName) {
        const dotIndex = fileName.lastIndexOf('.');
        return dotIndex === -1 ? '' : fileName.slice(dotIndex + 1).toLowerCase();
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
        this.pageStateOnboardingId = state.c__onboardingId || state.onboardingId;
        this.pageStateDocumentRequestId = state.c__documentRequestId || state.documentRequestId;
    }
}
