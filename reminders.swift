#!/usr/bin/env swift -FCarthage/Build/Mac

import OptionKit
import CoreFoundation
import EventKit


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

class Formatter {
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
}

class Subcommand {
  func parseOptions(parser: OptionParser, _ arguments: Array<String>) -> ParseData {
    do {
      let (options, rest) = try parser.parse(arguments)
      return (options, rest)
    } catch let OptionKitError.InvalidOption(description: description) {
      print(description)
      exit(EXIT_FAILURE)
    } catch {
      print("Unknown error")
      exit(EXIT_FAILURE)
    }
  }
}

class ListRemindersCommand: Subcommand {
  func run(store: EKEventStore, _ arguments: [String]) {
    let calendarOption = Option(
      trigger: OptionTrigger.Mixed("c", "calendar"),
      numberOfParameters: 1,
      helpDescription: "Calendar name"
    )

    let parser = OptionParser(definitions: [calendarOption])
    let (options, _) = parseOptions(parser, arguments)

    eachReminder(store, options) { reminder in
      print(Formatter().formatReminder(reminder))
    }
  }

  func eachReminder(store:EKEventStore, _ options: [Option : [String]], _ proc: (EKReminder) -> Void) {
    let calendar = store.defaultCalendarForNewReminders()
    let calendars = store.calendarsForEntityType(EKEntityType.Reminder)
    // let predicate = store.predicateForRemindersInCalendars([calendar]) // ([calendars[2]])
    let predicate = store.predicateForIncompleteRemindersWithDueDateStarting(nil, ending: nil, calendars: [calendar]) // ([calendars[2]])

    sync { complete in
      store.fetchRemindersMatchingPredicate(predicate) { reminders_or_nil in
        defer { complete() }
        guard let reminders = reminders_or_nil else { return }
        for reminder in reminders {
          proc(reminder)
        }
      }
    }
  }
}

class AddReminderCommand: Subcommand {
  func run(store: EKEventStore, _ arguments: [String]) {
    let calendarOption = Option(
      trigger: OptionTrigger.Mixed("c", "calendar"),
      numberOfParameters: 1,
      helpDescription: "Calendar name"
    )

    let parser = OptionParser(definitions: [calendarOption])
    let (options, rest) = parseOptions(parser, arguments)

    let title:String
    if rest.count > 0 {
      title = rest[0]
    } else {
      title = ""
    }
    let reminder = addReminder(store, title, options)
    print(Formatter().formatReminder(reminder))
  }

  func addReminder(store: EKEventStore, _ title: String, _ options: [Option: [String]]) -> EKReminder {
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
}

class ListCalendarsCommand: Subcommand {
  func run(store: EKEventStore, _ arguments: [String]) {
    let parser = OptionParser(
      definitions: []
    )
    let (_, _) = parseOptions(parser, arguments)
    eachCalendar(store) { calendar in
      print(calendar.title)
    }
  }

  func eachCalendar(store: EKEventStore, _ proc: (EKCalendar) -> Void) {
    let calendars = store.calendarsForEntityType(EKEntityType.Reminder)
    for cal in calendars {
      proc(cal)
    }
  }
}

func main() {
  var arguments = Array((Process.arguments[1..<Process.arguments.count]))
  let subcommand: String

  if arguments.count > 0 {
    subcommand = arguments[0]
  } else {
    print("subcommand required")
    exit(EXIT_FAILURE)
  }
  arguments.removeAtIndex(0)

  guard let store = createStore() else {
    print("cannot access reminders")
    exit(1)
  }

  switch subcommand {
    case "ls":
      ListRemindersCommand().run(store, arguments)
    case "cal":
      ListCalendarsCommand().run(store, arguments)
    case "add":
      AddReminderCommand().run(store, arguments)
    default:
      print("unknow subcommand")
      exit(EXIT_FAILURE)
  }
}

main()
