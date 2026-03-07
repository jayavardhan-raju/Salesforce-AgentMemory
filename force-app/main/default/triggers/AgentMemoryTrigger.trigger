/**
 * @description Trigger on Agent_Memory__c — delegates only, no logic here.
 */
trigger AgentMemoryTrigger on Agent_Memory__c (
    before insert, before update,
    after  insert, after  update) {
    AgentMemoryTriggerHandler.run();
}