import XCTest
import CoreLocation
import Nimble
@testable import teferi

class TrackingServiceTests : XCTestCase
{
    private var midnight : Date!
    private var noon : Date!
    private var locationDummy : CLLocation!
    private var loggingService : LoggingService!
    private var settingsService : SettingsService!
    private var trackingService : TrackingService!
    private var timeSlotService : MockTimeSlotService!
    private var notificationService : NotificationService!
    
    override func setUp()
    {
        self.midnight = Date().ignoreTimeComponents()
        self.noon = self.midnight.addingTimeInterval(12 * 60 * 60)
        self.locationDummy = CLLocation()
        self.loggingService = MockLoggingService()
        self.settingsService = MockSettingsService()
        self.timeSlotService = MockTimeSlotService()
        self.notificationService = MockNotificationService()
        self.trackingService = DefaultTrackingService(loggingService: self.loggingService,
                                               settingsService: self.settingsService,
                                               timeSlotService: self.timeSlotService,
                                               notificationService: self.notificationService)
    }
    
    func testTheAlgorithmWillNotRunForTheFirstLocationEverReceived()
    {
        let location = self.getLocation(withTimestamp: self.noon)
        self.trackingService.onNewLocation(location)
        
        expect(self.timeSlotService.getLastTimeSlotWasCalled).to(beFalse())
    }
    
    func testTheAlgorithmWillNotRunIfTheNewLocationIsOlderThanTheLastLocationReceived()
    {
        self.settingsService.setLastLocationDate(self.noon)
        let oldLocation = self.getLocation(withTimestamp: self.getDate(minutesBeforeNoon: 1))
        
        self.trackingService.onNewLocation(oldLocation)
        
        expect(self.timeSlotService.getLastTimeSlotWasCalled).to(beFalse())
    }
    
    func testTheAlgorithmDetectsACommuteIfMultipleEntriesHappenInAShortPeriodOfTime()
    {
        let date = self.getDate(minutesBeforeNoon: 15)
        
        let timeSlot = TimeSlot(withStartDate: date)
        self.timeSlotService.add(timeSlot: timeSlot)
        
        self.settingsService.setLastLocationDate(date)
        
        let location = self.getLocation(withTimestamp: self.noon)
        
        self.trackingService.onNewLocation(location)
        
        expect(timeSlot.category).to(equal(Category.commute))
    }
    
    func testTheAlgorithmDoesNotChangeTheTimeSlotToCommuteIfTheCurrentTimeSlotCategoryIsAlreadySet()
    {
        let date = getDate(minutesBeforeNoon: 15)
        
        let timeSlot = TimeSlot(withStartDate: date)
        timeSlot.category = .work
        self.timeSlotService.add(timeSlot: timeSlot)
        
        self.settingsService.setLastLocationDate(date)
        
        let location = self.getLocation(withTimestamp: self.noon)
        self.trackingService.onNewLocation(location)
        
        expect(timeSlot.category).to(equal(Category.work))
    }
    
    func testTheAlgorithmCreatesNewTimeSlotWhenANewUpdateComesAfterAWhile()
    {
        let date = self.getDate(minutesBeforeNoon: 30)
        
        let timeSlot = TimeSlot(withStartDate: date)
        self.timeSlotService.add(timeSlot: timeSlot)
        
        self.settingsService.setLastLocationDate(date)
        
        let location = self.getLocation(withTimestamp: self.noon)
        self.trackingService.onNewLocation(location)
        
        let allTimeSlots = self.timeSlotService.getTimeSlots(forDay: date)
        let newlyCreatedTimeSlot = allTimeSlots.last!
        
        expect(allTimeSlots.count).to(equal(2))
        expect(newlyCreatedTimeSlot.startTime).to(equal(location.timestamp))
    }
    
    func testTheAlgorithmDoesNotCreateNewTimeSlotsUntilItDetectsTheUserBeingIdleForAWhile()
    {
        let initialDate = self.getDate(minutesBeforeNoon: 130)
        self.timeSlotService.add(timeSlot: TimeSlot(withStartDate: initialDate))
        
        let dates = [ 120, 110, 90, 50, 40, 45, 0 ].map(self.getDate)
            
        dates.map(self.getLocation)
            .forEach(self.trackingService.onNewLocation)
        
        let allTimeSlots = self.timeSlotService.getTimeSlots(forDay: self.noon)
        let commutesDetected = allTimeSlots.filter { t in t.category == .commute }
        
        expect(allTimeSlots.count).to(equal(5))
        expect(commutesDetected.count).to(equal(2))
        expect(allTimeSlots[3].startTime).to(equal(dates[4]))
    }
    
    func getDate(minutesBeforeNoon: Int) -> Date
    {
        return self.noon
            .addingTimeInterval(Double(-minutesBeforeNoon * 60))
    }
    
    func getLocation(withTimestamp date: Date) -> CLLocation
    {
        let location = self.locationDummy!
        return CLLocation(coordinate: location.coordinate,
                          altitude: location.altitude,
                          horizontalAccuracy: location.horizontalAccuracy,
                          verticalAccuracy: location.verticalAccuracy,
                          timestamp: date)
    }
}
