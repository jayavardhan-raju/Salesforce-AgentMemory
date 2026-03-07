import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent }                    from 'lightning/platformShowToastEvent';
import { refreshApex }                       from '@salesforce/apex';

import getPendingSuggestions  from '@salesforce/apex/AgentMemoryController.getPendingSuggestions';
import getMemoriesForEntities from '@salesforce/apex/AgentMemoryController.getMemoriesForEntities';
import getActionHistory       from '@salesforce/apex/AgentMemoryController.getActionHistory';
import acceptSuggestion       from '@salesforce/apex/AgentMemoryController.acceptSuggestion';
import dismissSuggestion      from '@salesforce/apex/AgentMemoryController.dismissSuggestion';

export default class AgentMemoryDashboard extends LightningElement {

    // ── Public properties ─────────────────────────────────────────────────────
    @api recordId;               // Injected by the record page

    // ── Tracked state ─────────────────────────────────────────────────────────
    @track suggestions       = [];
    @track actionHistory     = [];
    @track memory            = null;
    @track isLoading         = false;
    @track hasError          = false;
    @track errorMessage      = '';
    @track showHistory       = false;
    @track showDismissModal  = false;
    @track dismissReason     = '';
    @track pendingDismissId  = null;

    // ── Wire result references (needed for refreshApex) ───────────────────────
    _wiredSuggestions;
    _wiredMemory;
    _wiredHistory;

    // ── Wired data ────────────────────────────────────────────────────────────

    @wire(getPendingSuggestions, { entityId: '$recordId' })
    wiredSuggestions(result) {
        this._wiredSuggestions = result;
        if (result.data) {
            this.suggestions  = result.data;
            this.hasError     = false;
        } else if (result.error) {
            this.handleError(result.error);
        }
    }

    @wire(getMemoriesForEntities, { entityIds: '$entityIdList' })
    wiredMemory(result) {
        this._wiredMemory = result;
        if (result.data && result.data.length > 0) {
            this.memory   = result.data[0];
            this.hasError = false;
        } else if (result.error) {
            this.handleError(result.error);
        }
    }

    @wire(getActionHistory, { entityId: '$recordId' })
    wiredHistory(result) {
        this._wiredHistory = result;
        if (result.data) {
            this.actionHistory = result.data;
        }
    }

    // ── Computed properties ───────────────────────────────────────────────────

    get entityIdList() {
        return this.recordId ? [this.recordId] : [];
    }

    get hasSuggestions() {
        return this.suggestions && this.suggestions.length > 0;
    }

    get suggestionCount() {
        return this.suggestions ? this.suggestions.length : 0;
    }

    get hasMemory() {
        return this.memory != null;
    }

    get memoryStrength() {
        return this.memory ? Math.round(this.memory.Memory_Strength__c || 0) : 0;
    }

    get patternCount() {
        return this.memory ? (this.memory.Pattern_Count__c || 0) : 0;
    }

    get cloudSource() {
        return this.memory ? (this.memory.Cloud_Source__c || '—') : '—';
    }

    get intentTags() {
        if (!this.memory || !this.memory.Intent_Tags__c) return 'none';
        return this.memory.Intent_Tags__c;
    }

    get strengthBarStyle() {
        const pct   = Math.min(100, Math.max(0, this.memoryStrength));
        let   color = '#2196F3'; // blue — moderate
        if (pct >= 80) color = '#4CAF50'; // green — high
        if (pct <  40) color = '#9E9E9E'; // grey  — low
        return `width:${pct}%; background-color:${color};`;
    }

    get hasHistory() {
        return this.actionHistory && this.actionHistory.length > 0;
    }

    get historyToggleLabel() {
        return this.showHistory ? 'Hide Action History' : 'Show Action History';
    }

    get historyIcon() {
        return this.showHistory ? 'utility:chevronup' : 'utility:chevrondown';
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleAccept(event) {
        const suggestionId = event.detail.suggestionId;
        this.isLoading = true;

        acceptSuggestion({ suggestionId })
            .then(() => {
                this.showToast('Success', 'Suggestion accepted. Automation has been triggered.', 'success');
                return refreshApex(this._wiredSuggestions);
            })
            .then(() => refreshApex(this._wiredMemory))
            .then(() => refreshApex(this._wiredHistory))
            .catch(error => this.handleError(error))
            .finally(() => { this.isLoading = false; });
    }

    handleDismiss(event) {
        this.pendingDismissId = event.detail.suggestionId;
        this.dismissReason    = '';
        this.showDismissModal = true;
    }

    handleDismissReasonChange(event) {
        this.dismissReason = event.target.value;
    }

    confirmDismiss() {
        if (!this.pendingDismissId) return;
        this.isLoading        = true;
        this.showDismissModal = false;

        dismissSuggestion({
            suggestionId : this.pendingDismissId,
            reason       : this.dismissReason || 'No reason provided'
        })
            .then(() => {
                this.showToast('Dismissed', 'Suggestion dismissed. The agent has recorded your feedback.', 'info');
                this.pendingDismissId = null;
                return refreshApex(this._wiredSuggestions);
            })
            .then(() => refreshApex(this._wiredMemory))
            .then(() => refreshApex(this._wiredHistory))
            .catch(error => this.handleError(error))
            .finally(() => { this.isLoading = false; });
    }

    closeDismissModal() {
        this.showDismissModal = false;
        this.pendingDismissId = null;
        this.dismissReason    = '';
    }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this._wiredSuggestions),
            refreshApex(this._wiredMemory),
            refreshApex(this._wiredHistory)
        ])
        .catch(error => this.handleError(error))
        .finally(() => { this.isLoading = false; });
    }

    toggleHistory() {
        this.showHistory = !this.showHistory;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    handleError(error) {
        this.hasError = true;
        if (error && error.body && error.body.message) {
            this.errorMessage = error.body.message;
        } else if (typeof error === 'string') {
            this.errorMessage = error;
        } else {
            this.errorMessage = 'An unexpected error occurred. Please refresh and try again.';
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}