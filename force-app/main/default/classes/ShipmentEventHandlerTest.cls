@IsTest
private class ShipmentEventHandlerTest {

    private static Shipment__c insertShipment(String trackingNumber) {
        Shipment__c s = new Shipment__c(Status__c = 'Booked', Origin__c = 'Copenhagen, DK',
            Destination__c = 'Oslo, NO', Weight_kg__c = 100, Tracking_Number__c = trackingNumber);
        insert s;
        return s;
    }

    private static String statusOf(Id shipmentId) {
        return [SELECT Status__c FROM Shipment__c WHERE Id = :shipmentId].Status__c;
    }

    @IsTest
    static void lastEventPerShipmentWins() {
        Shipment__c s = insertShipment('ATL-TEST-1');

        Test.startTest();
        EventBus.publish(new List<Shipment_Event__e>{
            new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-1', Status__c = 'Picked Up'),
            new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-1', Status__c = 'In Transit')
        });
        Test.stopTest();   // delivers the events to the trigger

        Assert.areEqual('In Transit', statusOf(s.Id));
    }

    // The batch fails twice with a transient error, is redelivered, and succeeds on the third attempt
    @IsTest
    static void transientFailureIsRetriedUntilItSucceeds() {
        Shipment__c s = insertShipment('ATL-TEST-2');

        Test.startTest();
        EventBus.publish(new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-2',
            Status__c = 'In Transit', Location__c = ShipmentEventHandler.SIMULATE_FAILURE));

        Test.getEventBus().deliver();   // attempt 1: RetryableException
        Assert.areEqual('Booked', statusOf(s.Id), 'Nothing should be saved on a failed attempt');

        Test.getEventBus().deliver();   // attempt 2 (retry 1): RetryableException
        Assert.areEqual('Booked', statusOf(s.Id));

        Test.getEventBus().deliver();   // attempt 3 (retry 2): succeeds
        Test.stopTest();

        Assert.areEqual('In Transit', statusOf(s.Id));
    }

    // An invalid status can never succeed, so it is not retried and doesn't block the subscription
    @IsTest
    static void permanentFailureIsNotRetried() {
        Shipment__c s = insertShipment('ATL-TEST-3');

        Test.startTest();
        EventBus.publish(new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-3', Status__c = 'Teleported'));
        Test.stopTest();

        Assert.areEqual('Booked', statusOf(s.Id));
    }

    @IsTest
    static void unknownTrackingNumberIsSkipped() {
        Shipment__c s = insertShipment('ATL-TEST-4');

        Test.startTest();
        EventBus.publish(new List<Shipment_Event__e>{
            new Shipment_Event__e(Tracking_Number__c = 'DOES-NOT-EXIST', Status__c = 'Delivered'),
            new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-4', Status__c = 'Picked Up')
        });
        Test.stopTest();

        Assert.areEqual('Picked Up', statusOf(s.Id));
    }
}
