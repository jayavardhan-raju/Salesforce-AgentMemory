/**
 * @description Scheduled Batch implementing a forgetting curve for agent memories.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public class MemoryStrengthDecayBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Decimal DECAY_AMOUNT      = 5.0;
    private static final Decimal ARCHIVE_THRESHOLD = 5.0;
    private static final Integer BATCH_SIZE        = 200;

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new MemoryStrengthDecayBatch(), BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Memory_Strength__c, LastModifiedDate
            FROM   Agent_Memory__c
            WHERE  LastModifiedDate   < :System.now().addDays(-30)
            AND    Memory_Strength__c > 0
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Agent_Memory__c> scope) {
        List<Agent_Memory__c> toUpdate = new List<Agent_Memory__c>();
        List<Agent_Memory__c> toDelete = new List<Agent_Memory__c>();

        for (Agent_Memory__c m : scope) {
            Decimal newStrength = Math.max(0,
                (m.Memory_Strength__c != null ? m.Memory_Strength__c : 0) - DECAY_AMOUNT
            );
            if (newStrength <= ARCHIVE_THRESHOLD) {
                toDelete.add(m);
            } else {
                m.Memory_Strength__c = newStrength;
                toUpdate.add(m);
            }
        }

        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision decUpdate = Security.stripInaccessible(
                AccessType.UPDATABLE, toUpdate
            );
            Database.update(decUpdate.getRecords(), false);
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'MemoryStrengthDecayBatch completed.');
    }
}