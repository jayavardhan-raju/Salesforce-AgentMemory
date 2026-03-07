/**
 * @description Trigger handler for Agent_Memory__c.
 *              Routes trigger events — zero SOQL, zero DML here.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public with sharing class AgentMemoryTriggerHandler {

    public static void run() {
        if (Trigger.isAfter && Trigger.isUpdate) {
            afterUpdate(Trigger.new, (Map<Id, Agent_Memory__c>) Trigger.oldMap);
        }
    }

    private static void afterUpdate(
            List<Agent_Memory__c> newList,
            Map<Id, Agent_Memory__c> oldMap) {

        List<AgentActionLogDTO> logsToWrite = new List<AgentActionLogDTO>();

        for (Agent_Memory__c mem : newList) {
            Agent_Memory__c old = oldMap.get(mem.Id);
            Decimal newStrength = mem.Memory_Strength__c != null ? mem.Memory_Strength__c : 0;
            Decimal oldStrength = old.Memory_Strength__c != null ? old.Memory_Strength__c : 0;

            if (newStrength > oldStrength) {
                logsToWrite.add(new AgentActionLogDTO(
                    'Memory Reinforced: ' + mem.Name,
                    'Memory_Reinforced',
                    mem.Cloud_Source__c,
                    mem.Entity_Id__c,
                    'Strength: ' + oldStrength + ' → ' + newStrength,
                    null,
                    true,
                    UserInfo.getUserId()
                ));
            }
        }

        for (AgentActionLogDTO dto : logsToWrite) {
            AgentMemoryService.logAction(dto, null);
        }
    }
}