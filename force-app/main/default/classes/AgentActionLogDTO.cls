/**
 * @description Lightweight DTO bundling Agent_Action_Log__c insertion parameters.
 *              Keeps AgentMemoryService and AgentMemoryTriggerHandler clean
 *              by avoiding long method signatures.
 */
public class AgentActionLogDTO {
    public String  actionName   { get; set; }
    public String  actionType   { get; set; }
    public String  cloudSource  { get; set; }
    public String  entityId     { get; set; }
    public String  inputContext { get; set; }
    public String  outputResult { get; set; }
    public Boolean userAccepted { get; set; }
    public Id      executedBy   { get; set; }

    public AgentActionLogDTO(
            String  actionName,
            String  actionType,
            String  cloudSource,
            String  entityId,
            String  inputContext,
            String  outputResult,
            Boolean userAccepted,
            Id      executedBy) {
        this.actionName   = actionName;
        this.actionType   = actionType;
        this.cloudSource  = cloudSource;
        this.entityId     = entityId;
        this.inputContext = inputContext;
        this.outputResult = outputResult;
        this.userAccepted = userAccepted;
        this.executedBy   = executedBy;
    }
}