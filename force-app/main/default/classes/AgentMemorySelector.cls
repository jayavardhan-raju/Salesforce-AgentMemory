/**
 * @description Selector for Agent_Memory__c — ALL SOQL lives here, NO DML.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public with sharing class AgentMemorySelector {

    public static List<Agent_Memory__c> getByEntityIds(Set<String> entityIds) {
        return [
            SELECT Id, Name, Cloud_Source__c, Context_Payload__c,
                   Entity_Id__c, Entity_Type__c, Intent_Tags__c,
                   Last_Action_Taken__c, Last_Interacted_By__c,
                   Memory_Strength__c, Pattern_Count__c, Org_Context_Hash__c,
                   LastModifiedDate
            FROM   Agent_Memory__c
            WHERE  Entity_Id__c IN :entityIds
            ORDER  BY Memory_Strength__c DESC NULLS LAST
        ];
    }

    public static Agent_Memory__c getByOrgContextHash(String hash) {
        List<Agent_Memory__c> results = [
            SELECT Id, Name, Cloud_Source__c, Context_Payload__c,
                   Entity_Id__c, Entity_Type__c, Intent_Tags__c,
                   Last_Action_Taken__c, Memory_Strength__c, Pattern_Count__c,
                   Org_Context_Hash__c
            FROM   Agent_Memory__c
            WHERE  Org_Context_Hash__c = :hash
            LIMIT  1
        ];
        return results.isEmpty() ? null : results[0];
    }

    public static List<Agent_Memory__c> getByCloudAndStrength(
            String cloudSource, Decimal minStrength) {
        return [
            SELECT Id, Name, Cloud_Source__c, Entity_Id__c, Entity_Type__c,
                   Intent_Tags__c, Last_Action_Taken__c, Memory_Strength__c,
                   Pattern_Count__c, Context_Payload__c
            FROM   Agent_Memory__c
            WHERE  Cloud_Source__c    = :cloudSource
            AND    Memory_Strength__c >= :minStrength
            ORDER  BY Pattern_Count__c DESC
        ];
    }

    public static List<Agent_Suggestion__c> getPendingSuggestionsForEntity(String entityId) {
        return [
            SELECT Id, Name, Source_Cloud__c, Target_Cloud__c,
                   Suggestion_Body__c, Confidence_Score__c, Status__c,
                   Flow_API_Name__c, Expires_At__c, Agent_Memory__c
            FROM   Agent_Suggestion__c
            WHERE  Entity_Id__c = :entityId
            AND    Status__c    = 'Pending'
            AND    (Expires_At__c = NULL OR Expires_At__c > :System.now())
            ORDER  BY Confidence_Score__c DESC
        ];
    }

    public static List<AggregateResult> getSuggestionFeedbackByMemory(Set<Id> memoryIds) {
        return [
            SELECT Agent_Memory__c, Status__c, COUNT(Id) cnt
            FROM   Agent_Suggestion__c
            WHERE  Agent_Memory__c IN :memoryIds
            AND    Status__c IN ('Accepted', 'Dismissed')
            GROUP  BY Agent_Memory__c, Status__c
        ];
    }

    public static List<Agent_Action_Log__c> getRecentActionLogs(
            String entityId, Integer limitCount) {
        return [
            SELECT Id, Action_Name__c, Action_Type__c, Cloud_Source__c,
                   Input_Context__c, Output_Result__c, User_Accepted__c,
                   CreatedDate, Executed_By__c
            FROM   Agent_Action_Log__c
            WHERE  Entity_Id__c = :entityId
            ORDER  BY CreatedDate DESC
            LIMIT  :limitCount
        ];
    }

    public static List<Agent_Memory__c> getDecayedMemories(Decimal decayThreshold) {
        return [
            SELECT Id, Memory_Strength__c, LastModifiedDate
            FROM   Agent_Memory__c
            WHERE  Memory_Strength__c < :decayThreshold
            AND    LastModifiedDate   < :System.now().addDays(-30)
        ];
    }
}