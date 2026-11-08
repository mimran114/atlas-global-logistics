@IsTest
private class ShipmentEventHandlerTest {
    @IsTest
    static void lastEventPerShipmentWins() {
        Shipment__c s = new Shipment__c(Status__c = 'Booked', Origin__c = 'Copenhagen, DK',
            Destination__c = 'Oslo, NO', Weight_kg__c = 100, Tracking_Number__c = 'ATL-TEST-1');
        insert s;

        Test.startTest();
        EventBus.publish(new List<Shipment_Event__e>{
            new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-1', Status__c = 'Picked Up'),
            new Shipment_Event__e(Tracking_Number__c = 'ATL-TEST-1', Status__c = 'In Transit')
        });
        Test.stopTest();   // delivers the events to the trigger

        Assert.areEqual('In Transit', [SELECT Status__c FROM Shipment__c WHERE Id = :s.Id].Status__c);
    }
}