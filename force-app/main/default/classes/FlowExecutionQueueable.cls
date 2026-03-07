/**
 * @description Queueable that invokes a named Salesforce Flow when a suggestion is accepted.
 * @author      Contextual Agent Memory
 * @version     1.0
 */
public class FlowExecutionQueueable implements Queueable {

    private String flowApiName;
    private String entityId;

    public FlowExecutionQueueable(String flowApiName, String entityId) {
        this.flowApiName = flowApiName;
        this.entityId    = entityId;
    }

    public void execute(QueueableContext ctx) {
        try {
            Map<String, Object> inputs = new Map<String, Object>{
                'entityId' => entityId
            };
            Flow.Interview interview = Flow.Interview.createInterview(flowApiName, inputs);
            interview.start();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'FlowExecutionQueueable [' + flowApiName + '] failed: ' + ex.getMessage());
        }
    }
}