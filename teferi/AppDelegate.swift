import UIKit
import RxSwift
import CoreData
import Foundation
import CoreLocation
import UserNotifications

@UIApplicationMain
class AppDelegate : UIResponder, UIApplicationDelegate
{   
    //MARK: Fields
    fileprivate var didReceiveCategoryNotification = false
    private let disposeBag = DisposeBag()
    private let notificationAuthorizedSubject = PublishSubject<Void>()
    
    private let pipeline : Pipeline
    private let timeService : TimeService
    private let metricsService : MetricsService
    private let loggingService : LoggingService
    private let feedbackService : FeedbackService
    private let locationService : LocationService
    private let settingsService : SettingsService
    private let timeSlotService : TimeSlotService
    private let editStateService : EditStateService
    private let healthKitService : HealthKitService
    private let smartGuessService : SmartGuessService
    private let trackEventService : TrackEventService
    private let appLifecycleService : AppLifecycleService
    private let notificationService : NotificationService
    private let selectedDateService : DefaultSelectedDateService
    private let notificationSchedulingService : NotificationSchedulingService
    
    //MARK: Properties
    var window: UIWindow?
    
    //Initializers
    override init()
    {
        self.timeService = DefaultTimeService()
        self.metricsService = FabricMetricsService()
        self.settingsService = DefaultSettingsService()
        self.loggingService = SwiftyBeaverLoggingService()
        self.appLifecycleService = DefaultAppLifecycleService()
        self.editStateService = DefaultEditStateService(timeService: self.timeService)
        self.locationService = DefaultLocationService(loggingService: self.loggingService)
        self.healthKitService = DefaultHealthKitService(settingsService: self.settingsService, loggingService: self.loggingService)
        self.selectedDateService = DefaultSelectedDateService(timeService: self.timeService)
        self.feedbackService = MailFeedbackService(recipients: ["support@toggl.com"], subject: "Supertoday feedback", body: "")
        
        
        let timeSlotPersistencyService = CoreDataPersistencyService(loggingService: self.loggingService, modelAdapter: TimeSlotModelAdapter())
        let locationPersistencyService = CoreDataPersistencyService(loggingService: self.loggingService, modelAdapter: LocationModelAdapter())
        let smartGuessPersistencyService = CoreDataPersistencyService(loggingService: self.loggingService, modelAdapter: SmartGuessModelAdapter())
        let healthSamplePersistencyService = CoreDataPersistencyService(loggingService: self.loggingService, modelAdapter: HealthSampleModelAdapter())
        
        self.smartGuessService = DefaultSmartGuessService(timeService: self.timeService,
                                                          loggingService: self.loggingService,
                                                          settingsService: self.settingsService,
                                                          persistencyService: smartGuessPersistencyService)
        
        self.timeSlotService = DefaultTimeSlotService(timeService: self.timeService,
                                                      loggingService: self.loggingService,
                                                      locationService: self.locationService,
                                                      persistencyService: timeSlotPersistencyService)
        
        if #available(iOS 10.0, *)
        {
            self.notificationService = PostiOSTenNotificationService(timeService: self.timeService,
                                                                     loggingService: self.loggingService,
                                                                     settingsService: self.settingsService,
                                                                     timeSlotService: self.timeSlotService)
        }
        else
        {
            self.notificationService = PreiOSTenNotificationService(loggingService: self.loggingService,
                                                                    self.notificationAuthorizedSubject.asObservable())
        }
        
        let trackEventServicePersistency = TrackEventPersistencyService(loggingService: self.loggingService,
                                                                        locationPersistencyService: locationPersistencyService,
                                                                        healthSamplePersistencyService: healthSamplePersistencyService)
        
        self.trackEventService = DefaultTrackEventService(loggingService: self.loggingService,
                                                          persistencyService: trackEventServicePersistency,
                                                          withEventSources: locationService, healthKitService)
        
        let locationPump = LocationPump(trackEventService: self.trackEventService,
                                        settingsService: self.settingsService,
                                        smartGuessService: self.smartGuessService,
                                        timeSlotService: self.timeSlotService,
                                        loggingService: loggingService,
                                        timeService: timeService)
        
        let healthKitPump = HealthKitPump(trackEventService: self.trackEventService, loggingService: loggingService)
        
        self.pipeline = Pipeline.with(loggingService: loggingService, pumps: locationPump, healthKitPump)
                                .pipe(to: MergePipe())
                                .pipe(to: MergeMiniCommuteTimeSlotsPipe(timeService: self.timeService))
                                .pipe(to: FirstTimeSlotOfDayPipe(timeService: self.timeService, timeSlotService: self.timeSlotService))
                                .sink(PersistencySink(settingsService: self.settingsService,
                                                      timeSlotService: self.timeSlotService,
                                                      smartGuessService: self.smartGuessService,
                                                      trackEventService: self.trackEventService,
                                                      timeService: self.timeService))

        self.notificationSchedulingService = NotificationSchedulingService(timeService: self.timeService,
                                                                           settingsService: self.settingsService,
                                                                           locationService: self.locationService,
                                                                           smartGuessService: self.smartGuessService,
                                                                           notificationService: self.notificationService)
    }
    
    //MARK: UIApplicationDelegate lifecycle
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool
    {
        setVersionInSettings()
        
        let isInBackground = launchOptions?[UIApplicationLaunchOptionsKey.location] != nil
        
        self.logAppStartup(isInBackground)

        if settingsService.hasHealthKitPermission
        {
            healthKitService.startHealthKitTracking()
        }
        
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        } else {
            if let notification = launchOptions?[UIApplicationLaunchOptionsKey.localNotification] as? UILocalNotification {
                didReceiveCategoryNotification = isCategorySelectionNotification(notification)
            }
        }
        
        
        self.appLifecycleService.publish(isInBackground ? .movedToBackground : .movedToForeground(fromNotification:didReceiveCategoryNotification))

        
        //Faster startup when the app wakes up for location updates
        if isInBackground
        {
            self.locationService.startLocationTracking()
            return true
        }
        
        self.initializeWindowIfNeeded()
        self.smartGuessService.purgeEntries(olderThan: self.timeService.now.add(days: -30))
        
        return true
    }

    private func setVersionInSettings()
    {
        let appVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildNumber: String = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as! String
        UserDefaults.standard.set("\(appVersionString) (\(buildNumber))", forKey: "version_string")
    }
    
    private func logAppStartup(_ isInBackground: Bool)
    {
        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        let startedOn = isInBackground ? "background" : "foreground"
        let message = "Application started on \(startedOn). App Version: \(versionNumber) Build: \(buildNumber)"

        self.loggingService.log(withLogLevel: .debug, message: message)
    }
    
    private func initializeWindowIfNeeded()
    {
        guard self.window == nil else { return }
        
        self.metricsService.initialize()
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        let viewModelLocator = DefaultViewModelLocator(timeService: self.timeService,
                                                       metricsService: self.metricsService,
                                                       feedbackService: self.feedbackService,
                                                       locationService: self.locationService,
                                                       settingsService: self.settingsService,
                                                       timeSlotService: self.timeSlotService,
                                                       editStateService: self.editStateService,
                                                       smartGuessService : self.smartGuessService,
                                                       appLifecycleService: self.appLifecycleService,
                                                       selectedDateService: self.selectedDateService,
                                                       loggingService: self.loggingService,
                                                       healthKitService: self.healthKitService)
        
        let isFirstUse = self.settingsService.installDate == nil
        
        let mainViewController = StoryboardScene.Main.instantiateMain()
        var initialViewController : UIViewController =
            mainViewController.inject(viewModelLocator: viewModelLocator, isFirstUse: isFirstUse)
        
        if isFirstUse
        {
            notificationService.scheduleNormalNotification(date: Date().addingTimeInterval(Constants.timeToWaitBeforeShowingHealthKitPermissions), title: "", message: L10n.notificationHealthKitAccessBody)
            
            let onboardController = StoryboardScene.Onboarding.instantiateOnboardingPager()
            
            initialViewController =
                onboardController.inject(self.timeService,
                                         self.timeSlotService,
                                         self.settingsService,
                                         self.appLifecycleService,
                                         mainViewController,
                                         notificationService)
        }
        
        
        self.window!.rootViewController = initialViewController
        self.window!.makeKeyAndVisible()
    }
    
    func applicationWillResignActive(_ application: UIApplication)
    {
        self.appLifecycleService.publish(.movedToBackground)
    }

    func applicationDidEnterBackground(_ application: UIApplication)
    {
        self.locationService.startLocationTracking()
    }

    func applicationDidBecomeActive(_ application: UIApplication)
    {
        self.appLifecycleService.publish(.movedToForeground(fromNotification:didReceiveCategoryNotification))
        self.pipeline.run()
        self.initializeWindowIfNeeded()
        self.notificationService.unscheduleAllNotifications(ofTypes: .categorySelection)
        
        self.didReceiveCategoryNotification = false
    }
    
    func application(_ application: UIApplication, didRegister notificationSettings: UIUserNotificationSettings)
    {
        self.notificationAuthorizedSubject.on(.next(()))
    }
    
    func application(_ application: UIApplication, didReceive notification: UILocalNotification)
    {
        self.didReceiveCategoryNotification = isCategorySelectionNotification(notification)
    }
    
    private func isCategorySelectionNotification(_ notification:UILocalNotification) -> Bool
    {
        guard
            let identifier = notification.userInfo?["id"] as? String,
            identifier == NotificationType.categorySelection.rawValue
            else { return false }
        
        return true
    }
    
    @available(iOS 10.0, *)
    fileprivate func isCategorySelectionNotification(_ notification:UNNotification) -> Bool
    {
        guard
            let identifier = notification.request.content.userInfo["id"] as? String,
            identifier == NotificationType.categorySelection.rawValue
            else { return false }
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication)
    {
        self.saveContext()
    }
    
    // MARK: Core Data stack
    private lazy var applicationDocumentsDirectory : URL =
    {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.toggl.teferi" in the application's documents Application Support directory.
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count - 1]
    }()

    private lazy var managedObjectModel : NSManagedObjectModel =
    {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = Bundle.main.url(forResource: "teferi", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    private lazy var persistentStoreCoordinator : NSPersistentStoreCoordinator =
    {
        // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        // Create the coordinator and store
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.appendingPathComponent("SingleViewCoreData.sqlite")
        var failureReason = "There was an error creating or loading the application's saved data."
        do
        {
            let options = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
            
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: options)
        }
        catch
        {
            let nsError = error as NSError
            self.loggingService.log(withLogLevel: .error, message: "\(nsError.userInfo)")
        }
        
        return coordinator
    }()

    lazy var managedObjectContext : NSManagedObjectContext =
    {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        var managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()

    private func saveContext()
    {
        if managedObjectContext.hasChanges
        {
            do
            {
                try managedObjectContext.save()
            }
            catch
            {
                // Replace this implementation with code to handle the error appropriately.
                let nsError = error as NSError
                self.loggingService.log(withLogLevel: .error, message: "\(nsError.userInfo)")
            }
        }
    }
}

@available(iOS 10.0, *)
extension AppDelegate:UNUserNotificationCenterDelegate
{
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        self.didReceiveCategoryNotification = isCategorySelectionNotification(response.notification)
        completionHandler()
    }
}
