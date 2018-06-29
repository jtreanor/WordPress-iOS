import WordPressFlux

protocol ActivityRewindPresenter: class {
    func presentRewindFor(activity: Activity)
}

protocol ActivityDetailPresenter: class {
    func presentDetailsFor(activity: Activity)
}

class ActivityListViewModel: Observable {

    let site: JetpackSiteRef
    let store: ActivityStore

    let changeDispatcher = Dispatcher<Void>()

    private let activitiesReceipt: Receipt
    private let rewindStatusReceipt: Receipt
    private let storeReceipt: Receipt

    var errorViewModel: NoResultsViewController.Model?

    init(site: JetpackSiteRef, store: ActivityStore = StoreContainer.shared.activity) {
        self.site = site
        self.store = store

        activitiesReceipt = store.query(.activities(site: site))
        rewindStatusReceipt = store.query(.restoreStatus(site: site))

        storeReceipt = store.onChange { [weak changeDispatcher] in
            changeDispatcher?.dispatch()
        }
    }

    func noResultsViewModel() -> NoResultsViewController.Model? {
        guard store.getActivities(site: site) == nil else {
            return nil
        }

        if store.isFetching(site: site) {
            return NoResultsViewController.Model(title: NSLocalizedString("Loading Activities...", comment: "Text displayed while loading the activity feed for a site"))
        }

        let appDelegate = WordPressAppDelegate.sharedInstance()
        if (appDelegate?.connectionAvailable)! {
            return NoResultsViewController.Model(title: NSLocalizedString("Oops", comment: "Title for the view when there's an error loading Activity Log"),
                                                 subtitle: NSLocalizedString("There was an error loading activities", comment: "Text displayed when there is a failure loading the activity feed"),
                                                 buttonText: NSLocalizedString("Contact support", comment: "Button label for contacting support"))
        } else {
            return NoResultsViewController.Model(title: NSLocalizedString("No connection", comment: "Title for the error view when there's no connection"),
                                                 subtitle: NSLocalizedString("An active internet connection is required to view activities", comment: ""))

        }
    }

    func tableViewModel(presenter: ActivityDetailPresenter) -> ImmuTable {
        guard let activities = store.getActivities(site: site) else {
            return .Empty
        }

        let activitiesRows = activities.map({ activity in
            return ActivityListRow(
                activity: activity,
                action: { [weak presenter] (row) in
                    presenter?.presentDetailsFor(activity: activity)
                }
            )
        })

        let groupedRows = activitiesRows.sortedGroup {
            return longDateFormatterWithoutTime.string(from: $0.activity.published)
        }

        let activitiesSections = groupedRows
            .map { (date, rows) in
                return ImmuTableSection(headerText: date,
                                        optionalRows: rows,
                                        footerText: nil)
            }

        return ImmuTable(optionalSections: [restoreStatusSection()] + activitiesSections)
        // So far the only "extra" section is the restore one. In the future, this will include
        // showing plugin updates/CTA's and other things like this.
    }

    private func restoreStatusSection() -> ImmuTableSection? {
        guard let restore = store.getRewindStatus(site: site)?.restore, restore.status == .running || restore.status == .queued else {
            return nil
        }

        let title = NSLocalizedString("Currently restoring your site", comment: "Title of the cell displaying status of a rewind in progress")
        let summary: String
        let progress = max(Float(restore.progress) / 100, 0.05)
        // We don't want to show a completely empty progress bar — it'd seem something is broken. 5% looks acceptable
        // for the starting state.

        if let rewindPoint = store.getActivity(site: site, rewindID: restore.id) {
            let dateString = mediumDateFormatterWithTime.string(from: rewindPoint.published)
            let messageFormat = NSLocalizedString("Rewinding to %@",
                comment: "Text showing the point in time the site is being currently restored to. %@' is a placeholder that will expand to a date.")

            summary = String(format: messageFormat, dateString)
        } else {
            summary = ""
        }

        let rewindRow = RewindStatusRow(
            title: title,
            summary: summary,
            progress: progress
        )

        return ImmuTableSection(headerText: NSLocalizedString("Rewind", comment: "Title of section showing rewind status"),
                                rows: [rewindRow],
                                footerText: nil)
    }


    // MARK: - Date/Time handling

    lazy var longDateFormatterWithoutTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = timeZone(for: site)

        return formatter
    }()

    lazy var mediumDateFormatterWithTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone(for: site)

        return formatter
    }()

    private func timeZone(for site: JetpackSiteRef) -> TimeZone {
        let context = ContextManager.sharedInstance().mainContext
        let blogService = BlogService(managedObjectContext: context)

        guard let blog = blogService.blog(byBlogId: site.siteID as NSNumber) else {
            return TimeZone(secondsFromGMT: 0)!
        }

        return blogService.timeZone(for: blog)
    }
}
