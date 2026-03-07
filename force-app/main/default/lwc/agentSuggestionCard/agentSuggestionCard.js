import { LightningElement, api } from 'lwc';

export default class AgentSuggestionCard extends LightningElement {

    @api suggestion;

    // ── Computed properties ───────────────────────────────────────────────────

    get sourceCloud() {
        return this.suggestion ? (this.suggestion.Source_Cloud__c || 'Unknown') : '';
    }

    get targetCloud() {
        return this.suggestion ? (this.suggestion.Target_Cloud__c || 'Unknown') : '';
    }

    get suggestionBody() {
        return this.suggestion ? (this.suggestion.Suggestion_Body__c || '') : '';
    }

    get confidenceScore() {
        return this.suggestion ? (this.suggestion.Confidence_Score__c || 0) : 0;
    }

    get confidenceLabel() {
        const score = this.confidenceScore;
        if (score >= 80) return score + '% — High Confidence';
        if (score >= 60) return score + '% — Moderate Confidence';
        if (score >= 40) return score + '% — Low Confidence';
        return score + '%';
    }

    get expiresAt() {
        if (!this.suggestion || !this.suggestion.Expires_At__c) return '—';
        const d = new Date(this.suggestion.Expires_At__c);
        return d.toLocaleDateString(undefined, {
            month : 'short',
            day   : 'numeric',
            hour  : '2-digit',
            minute: '2-digit'
        });
    }

    /**
     * Card border and background colour driven by confidence tier:
     *   >= 80%  → green  (high)
     *   >= 60%  → blue   (moderate)
     *   >= 40%  → grey   (low — still above insert threshold)
     */
    get cardClass() {
        const score = this.confidenceScore;
        let   tier  = 'low';
        if (score >= 80) tier = 'high';
        else if (score >= 60) tier = 'moderate';
        return `suggestion-card suggestion-card_${tier} slds-box slds-box_x-small`;
    }

    get confidenceBarStyle() {
        const score = Math.min(100, Math.max(0, this.confidenceScore));
        let   color = '#9E9E9E';
        if (score >= 80) color = '#4CAF50';
        else if (score >= 60) color = '#2196F3';
        return `width:${score}%; background-color:${color};`;
    }

    get sourceBadgeClass() {
        return 'cloud-badge cloud-badge_' + this._cloudKey(this.sourceCloud);
    }

    get targetBadgeClass() {
        return 'cloud-badge cloud-badge_' + this._cloudKey(this.targetCloud);
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleAccept() {
        this.dispatchEvent(new CustomEvent('accept', {
            bubbles : true,
            composed: true,
            detail  : { suggestionId: this.suggestion.Id }
        }));
    }

    handleDismiss() {
        this.dispatchEvent(new CustomEvent('dismiss', {
            bubbles : true,
            composed: true,
            detail  : { suggestionId: this.suggestion.Id }
        }));
    }

    // ── Private ───────────────────────────────────────────────────────────────

    _cloudKey(cloudName) {
        if (!cloudName) return 'default';
        const n = cloudName.toLowerCase();
        if (n.includes('sales'))     return 'sales';
        if (n.includes('service'))   return 'service';
        if (n.includes('marketing')) return 'marketing';
        return 'default';
    }
}