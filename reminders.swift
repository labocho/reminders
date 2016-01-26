#!/usr/bin/env swift -FCarthage/Build/Mac

import OptionKit
import CoreFoundation
import EventKit

func formatDate(dateComponentsOrNil: NSDateComponents?, format: String = "yyyy-MM-dd HH:mm") -> String {
  guard let dateComponents = dateComponentsOrNil else {
    return String(count: format.characters.count, repeatedValue: Character(" "))
  }
  let gregorian = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
  let date = gregorian.dateFromComponents(dateComponents)!
  let dateFormatter = NSDateFormatter()
  dateFormatter.dateFormat = format
  return dateFormatter.stringFromDate(date)
}

func formatReminder(reminder: EKReminder) -> String {
  let id = reminder.calendarItemIdentifier
  return [
    formatDate(reminder.startDateComponents),
    id[id.startIndex...id.startIndex.advancedBy(7)],
    reminder.title,
  ].joinWithSeparator(" ")
}

// 非同期の処理を 1 つ含む関数 f を同期的に実行
// 非同期処理が終わったら引数として渡した関数を呼ぶ必要がある
// 最後の引数が関数なので sync() {complete in ... } または sync {complete in ... } のように書ける
func sync(f: (() -> Void) -> Void) {
  let sema = dispatch_semaphore_create(0)
  func complete() {
    dispatch_semaphore_signal(sema)
  }
  f(complete)
  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER)
}

func createStore() -> EKEventStore? {
  let store = EKEventStore()
  var permitted: Bool = false

  sync { complete in
    store.requestAccessToEntityType(EKEntityType.Reminder) { granted, error in
      defer { complete() }
      permitted = granted
    }
  }

  return permitted ? store : nil
}

func listReminders(store:EKEventStore) {
  let calendar = store.defaultCalendarForNewReminders()
  let calendars = store.calendarsForEntityType(EKEntityType.Reminder)
  // let predicate = store.predicateForRemindersInCalendars([calendar]) // ([calendars[2]])
  let predicate = store.predicateForIncompleteRemindersWithDueDateStarting(nil, ending: nil, calendars: [calendar]) // ([calendars[2]])

  sync { complete in
    store.fetchRemindersMatchingPredicate(predicate) { reminders_or_nil in
      defer { complete() }
      guard let reminders = reminders_or_nil else { return }
      for reminder in reminders {
        print(formatReminder(reminder))
      }
    }
  }
}

func listCalendars(store:EKEventStore) {
  let calendars = store.calendarsForEntityType(EKEntityType.Reminder)
  for cal in calendars {
    print(cal.title)
  }
}

func addReminder(store: EKEventStore, title: String) -> EKReminder {
  let reminder = EKReminder(eventStore: store)
  reminder.calendar = store.defaultCalendarForNewReminders()
  reminder.title = title

  do {
    try store.saveReminder(reminder, commit: true)
  } catch {
    print("save failed")
    exit(EXIT_FAILURE)
  }

  return reminder
}

func main() {
  let arguments = Array((Process.arguments[1..<Process.arguments.count]))

  // Define options
  let frameRateOption = Option(
    trigger: OptionTrigger.Mixed("f", "fps"),
    numberOfParameters: 1,
    helpDescription: "Recording frames per second"
  )
  let outputPathOption = Option(
    trigger: OptionTrigger.Mixed("o", "outputPath"),
    numberOfParameters: 1,
    helpDescription: "Animation output path"
  )
  let helpOption = Option(
    trigger:.Mixed("h", "help")
  )

  // Create Parser
  let parser = OptionParser(definitions: [frameRateOption, outputPathOption])

  // Parse options
  do {
    let (options, rest) = try parser.parse(arguments)

    if options[helpOption] != nil {
      print(parser.helpStringForCommandName("option-parser"))
      exit(EXIT_FAILURE)
    }

    if let frameRate: UInt = options[frameRateOption]?.flatMap({ UInt($0) }).first {
      print(frameRate)
    }

    if let outputPath = options[outputPathOption]?.first {
      print(outputPath)
    }


    guard let store = createStore() else {
      print("cannot access reminders")
      exit(1)
    }

    // var subcommand:String = ""
    let subcommand:String

    if rest.count > 0 {
      subcommand = rest[0]
    } else {
      subcommand = ""
    }

    switch subcommand {
      case "ls":
        listReminders(store)
      case "cal":
        listCalendars(store)
      case "add":
        let title:String
        if rest.count > 1 {
          title = rest[1]
        } else {
          title = ""
        }
        let reminder = addReminder(store, title: title)
        print(formatReminder(reminder))
      default:
        print("unknow subcommand")
        exit(EXIT_FAILURE)
    }

  } catch let OptionKitError.InvalidOption(description: description) {
    print(description)
    exit(EXIT_FAILURE)
  } catch {
    print("Unknown error")
    exit(EXIT_FAILURE)
  }
}

main()
