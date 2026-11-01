@IsTest
private class ShipmentTriggerHandlerTest {

    // Runs in its own transaction, so the handler's static Set<Id> is empty again in each test method
    @TestSetup
    static void setup() {
        insert new List<Shipment__c>{
            buildShipment('In Transit', 120),
            buildShipment('Exception', 80)
        };
    }

    private static Shipment__c buildShipment(String status, Decimal weightKg) {
        return new Shipment__c(
            Status__c = status,
            Origin__c = 'Copenhagen, DK',
            Destination__c = 'Rotterdam, NL',
            Carrier_Name__c = 'NordFreight',
            Weight_kg__c = weightKg
        );
    }

    private static List<Shipment__c> buildShipments(Integer count, String status) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < count; i++) {
            shipments.add(buildShipment(status, 10 + i));
        }
        return shipments;
    }

    // 250 records = 2 trigger chunks (200 + 50) in one transaction
    @IsTest
    static void bulkInsertFillsTrackingNumberInEveryChunk() {
        Test.startTest();
        insert buildShipments(250, 'Booked');
        Test.stopTest();

        List<Shipment__c> saved = [
            SELECT Tracking_Number__c, Automation_Trace__c
            FROM Shipment__c
            WHERE Status__c = 'Booked'
        ];
        Assert.areEqual(250, saved.size());
        for (Shipment__c s : saved) {
            Assert.isTrue(s.Tracking_Number__c.startsWith('ATL-'), 'Tracking number not generated: ' + s.Tracking_Number__c);
            Assert.isTrue(s.Automation_Trace__c.contains('2-BeforeTrigger'), 'Before trigger did not run');
        }
    }

    @IsTest
    static void existingTrackingNumberIsKept() {
        Shipment__c s = buildShipment('Booked', 50);
        s.Tracking_Number__c = 'MANUAL-001';

        Test.startTest();
        insert s;
        Test.stopTest();

        Assert.areEqual('MANUAL-001', [SELECT Tracking_Number__c FROM Shipment__c WHERE Id = :s.Id].Tracking_Number__c);
    }

    // Proves the order of execution: the before-save flow runs before the before trigger
    @IsTest
    static void beforeSaveFlowRunsBeforeTrigger() {
        Shipment__c s = buildShipment('Booked', 1500);

        Test.startTest();
        insert s;
        Test.stopTest();

        String trace = [SELECT Automation_Trace__c FROM Shipment__c WHERE Id = :s.Id].Automation_Trace__c;
        Assert.isTrue(trace.contains('1-BeforeFlow'), 'Before-save flow did not run: ' + trace);
        Assert.isTrue(trace.indexOf('1-BeforeFlow') < trace.indexOf('2-BeforeTrigger'), 'Wrong order: ' + trace);
        Assert.isTrue(trace.contains('band=Heavy'), 'Trigger did not see the flow\'s Weight_Band__c: ' + trace);
    }

    // A static Boolean guard would only create 200 Tasks here; the Set<Id> guard creates all 250
    @IsTest
    static void bulkInsertWithExceptionCreatesOneTaskPerShipment() {
        Test.startTest();
        List<Shipment__c> shipments = buildShipments(250, 'Exception');
        insert shipments;
        Test.stopTest();

        Map<Id, Shipment__c> byId = new Map<Id, Shipment__c>(shipments);
        Assert.areEqual(250, [SELECT COUNT() FROM Task WHERE WhatId IN :byId.keySet()]);
    }

    @IsTest
    static void statusChangedToExceptionCreatesTask() {
        Shipment__c s = [SELECT Id FROM Shipment__c WHERE Status__c = 'In Transit' LIMIT 1];
        s.Status__c = 'Exception';

        Test.startTest();
        update s;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :s.Id]);
    }

    // Change detection: already Exception, another field edited -> no second Task
    @IsTest
    static void editOnExceptionShipmentDoesNotCreateAnotherTask() {
        Shipment__c s = [SELECT Id FROM Shipment__c WHERE Status__c = 'Exception' LIMIT 1];
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :s.Id], 'Setup should have created one Task');
        s.Destination__c = 'Hamburg, DE';

        Test.startTest();
        update s;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :s.Id]);
    }

    @IsTest
    static void otherStatusChangeDoesNotCreateTask() {
        Shipment__c s = [SELECT Id FROM Shipment__c WHERE Status__c = 'In Transit' LIMIT 1];
        s.Status__c = 'Delivered';

        Test.startTest();
        update s;
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :s.Id AND Subject = 'Investigate shipment exception']);
    }
}