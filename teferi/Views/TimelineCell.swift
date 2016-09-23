import UIKit
import RxSwift

///Cell that represents a TimeSlot in the timeline
class TimelineCell : UITableViewCell
{
    // MARK: Fields
    private var currentIndex = 0
    private let hourMask = "%02d h %02d min"
    private let minuteMask = "%02d min"
    private lazy var lineHeightConstraint : NSLayoutConstraint =
    {
        return NSLayoutConstraint(item: self.lineView!, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: CGFloat(Constants.minLineSize))
    }()
    
    @IBOutlet weak private var lineView : UIView?
    @IBOutlet weak private var elapsedTime : UILabel?
    @IBOutlet weak private var categoryButton : UIButton?
    @IBOutlet weak private var slotDescription : UILabel?
    @IBOutlet weak private var categoryIcon : UIImageView?
    
    //MARK: Properties
    private(set) var isSubscribedToClickObservable = false
    var editClickObservable : Observable<Int>
    {
        self.isSubscribedToClickObservable = true
        return categoryButton!.rx.tap.map { return self.currentIndex }.asObservable()
    }
    
    
    // MARK: Methods
    override func awakeFromNib()
    {
        super.awakeFromNib()
        lineView?.addConstraint(lineHeightConstraint)
    }
    
    /**
     Binds the current TimeSlot in order to change the UI accordingly.
     
     - Parameter timeSlot: TimeSlot that will be bound.
     */
    func bind(withTimeSlot timeSlot: TimeSlot, shouldFade: Bool, index: Int, isEditingCategory: Bool)
    {
        self.currentIndex = index
        
        let interval = Int(timeSlot.duration)
        let minutes = (interval / 60) % 60
        let hours = (interval / 3600)
        let alpha = shouldFade ? Constants.editingAlpha : 1
        let categoryColor = timeSlot.category.color
        
        //Updates each one of the cell's components
        layoutLine(withColor: categoryColor, hours: hours, minutes: minutes, alpha: alpha)
        
        layoutCategoryIcon(withImageNamed: timeSlot.category.assetInfo.small, color: categoryColor, alpha: alpha)
        
        layoutDescriptionLabel(withStartTime: timeSlot.startTime, category: timeSlot.category, alpha: alpha)
        
        layoutElapsedTimeLabel(withColor: categoryColor, hours: hours, minutes: minutes, alpha: alpha)
        
        guard isEditingCategory else { return }
        
        
    }
    
    /// Updates the icon that indicates the slot's category
    private func layoutCategoryIcon(withImageNamed name: String, color: UIColor, alpha: CGFloat)
    {
        categoryIcon?.alpha = alpha
        categoryIcon?.image = UIImage(named: name)
    }
    
    /// Updates the label that displays the description and starting time of the slot
    private func layoutDescriptionLabel(withStartTime startTime: Date, category: Category, alpha: CGFloat)
    {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let dateString = formatter.string(from: startTime)
        let categoryText = category == .Unknown ? "" : String(describing: category)
        
        let description = "\(categoryText) \(dateString)"
        let nonBoldRange = NSMakeRange(categoryText.characters.count, dateString.characters.count)
        let attributedText = description.getBoldStringWithNonBoldText(nonBoldRange)
        
        slotDescription?.attributedText = attributedText
        slotDescription?.alpha = alpha
    }
    
    ///Updates the label that shows how long the slot lasted
    private func layoutElapsedTimeLabel(withColor color: UIColor, hours: Int, minutes: Int, alpha: CGFloat)
    {
        elapsedTime?.textColor = color
        elapsedTime?.text = hours > 0 ? String(format: hourMask, hours, minutes) : String(format: minuteMask, minutes)
        elapsedTime?.alpha = alpha
    }
    
    ///Updates the line that displays shows how long the TimeSlot lasted
    private func layoutLine(withColor color: UIColor, hours: Int, minutes: Int, alpha: CGFloat)
    {
        let newHeight = CGFloat(Constants.minLineSize * (1 + (minutes / 15) + (hours * 4)))
        lineHeightConstraint.constant = newHeight
        
        lineView?.backgroundColor = color
        lineView?.alpha = alpha
        lineView?.layoutIfNeeded()
    }
}
