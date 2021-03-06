import Foundation
import UserNotificationsUI

protocol NotificationService
{
    func requestNotificationPermission(completed: @escaping () -> ())
    
    func scheduleNormalNotification(date: Date, title: String, message: String)
    
    func unscheduleAllNotifications(ofTypes types: NotificationType?...)
    
    func handleNotificationAction(withIdentifier identifier: String?)
    
    func subscribeToCategoryAction(_ action : @escaping (Category) -> ())
}
