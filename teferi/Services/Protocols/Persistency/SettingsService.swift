import Foundation
import CoreLocation

protocol SettingsService
{
    //MARK: Properties
    var installDate : Date? { get }
    
    var lastLocation : CLLocation? { get }
    
    var hasLocationPermission : Bool { get }
    
    var hasHealthKitPermission : Bool { get }
    
    var lastAskedForLocationPermission : Date? { get }
        
    var hasNotificationPermission : Bool { get }
    
    var userEverGaveLocationPermission : Bool { get }
    
    var lastNotificationLocation : CLLocation? { get }
    
    var welcomeMessageHidden : Bool { get }
    
    //MARK: Methods
    func lastHealthKitUpdate(for identifier: String) -> Date
    
    func setLastHealthKitUpdate(for identifier: String, date: Date)
    
    func setInstallDate(_ date: Date)
    
    func setLastLocation(_ location: CLLocation)
    
    func setLastAskedForLocationPermission(_ date: Date)
    
    func setUserGaveLocationPermission()
    
    func setUserGaveHealthKitPermission()
    
    func setLastNotificationLocation(_ location: CLLocation)
    
    func setWelcomeMessageHidden()
}
