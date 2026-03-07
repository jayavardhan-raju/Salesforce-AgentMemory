/**
 * @description AuraEnabled controller exposing agent memory operations to LWC.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public with sharing class AgentMemoryController {

    @AuraEnabled(cacheable=true)
    public static List<Agent_Suggestion__c> getPendingSuggestions(String entityId) {
        if (String.isBlank(entityId)) {
            throw new AuraHandledException('entityId is required');
        }
        return AgentMemorySelector.getPendingSuggestionsForEntity(entityId);
    }

    @AuraEnabled(cacheable=true)
    public static List<Agent_Memory__c> getMemoriesForEntities(List<String> entityIds) {
        if (entityIds == null || entityIds.isEmpty()) {
            return new List<Agent_Memory__c>();
        }
        return AgentMemorySelector.getByEntityIds(new Set<String>(entityIds));
    }

    @AuraEnabled(cacheable=true)
    public static List<Agent_Action_Log__c> getActionHistory(String entityId) {
        if (String.isBlank(entityId)) {
            throw new AuraHandledException('entityId is required');
        }
        return AgentMemorySelector.getRecentActionLogs(entityId, 20);
    }

    @AuraEnabled
    public static void acceptSuggestion(Id suggestionId) {
        try {
            AgentMemoryService.acceptSuggestion(suggestionId, UserInfo.getUserId());
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void dismissSuggestion(Id suggestionId, String reason) {
        try {
            AgentMemoryService.dismissSuggestion(suggestionId, reason, UserInfo.getUserId());
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void recordMemoryContext(String memoryContextJson) {
        try {
            AgentMemoryService.MemoryContext ctx = (AgentMemoryService.MemoryContext)
                JSON.deserialize(memoryContextJson, AgentMemoryService.MemoryContext.class);
            AgentMemoryService.recordAndLearn(ctx);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getMemoryHeatmap() {
        Map<String, Object> heatmap = new Map<String, Object>();
        for (String cloud : new List<String>{
                'Sales Cloud', 'Service Cloud', 'Marketing Cloud' }) {
            List<Agent_Memory__c> cloudMems =
                AgentMemorySelector.getByCloudAndStrength(cloud, 0.0);
            heatmap.put(cloud, new Map<String, Object>{
                'count'       => cloudMems.size(),
                'avgStrength' => averageStrength(cloudMems),
                'topPatterns' => getTopPatterns(cloudMems, 3)
            });
        }
        return heatmap;
    }

    private static Decimal averageStrength(List<Agent_Memory__c> mems) {
        if (mems.isEmpty()) return 0;
        Decimal total = 0;
        for (Agent_Memory__c m : mems) {
            total += (m.Memory_Strength__c != null ? m.Memory_Strength__c : 0);
        }
        return (total / mems.size()).setScale(1);
    }

    private static List<String> getTopPatterns(List<Agent_Memory__c> mems, Integer topN) {
        List<String> patterns = new List<String>();
        Integer added = 0;
        for (Agent_Memory__c m : mems) {
            if (added >= topN) break;
            if (String.isNotBlank(m.Intent_Tags__c)) {
                patterns.add(m.Intent_Tags__c.split(',')[0]);
                added++;
            }
        }
        return patterns;
    }
}