#!/usr/bin/env swift -FCarthage/Build/Mac

import CoreFoundation
import EventKit
import OptionKit
import Regex
import SwiftyJSON

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

class JSONFormatter: Formatter {
  override func formatReminder(reminder: EKReminder) -> String {
    var json: JSON = [:]
    json["calendarItemIdentifier"].string = reminder.calendarItemIdentifier
    if reminder.startDateComponents != nil {
      json["startDateComponents"].string = formatDate(reminder.startDateComponents, format: "yyyy-MM-dd'T'HH:mm:ssZ")
    }
    json["title"].string = reminder.title
    if reminder.hasAlarms {
      let alarms: [JSON] = reminder.alarms!.map { (alarm) -> JSON in
        var a: JSON = [:]
        if alarm.absoluteDate != nil {
          let components = NSCalendar.currentCalendar().components(
            [ NSCalendarUnit.Year,
              NSCalendarUnit.Month,
              NSCalendarUnit.Day,
              NSCalendarUnit.Hour,
              NSCalendarUnit.Minute,
              NSCalendarUnit.Second,
            ],
            fromDate: alarm.absoluteDate!
          )
          a["absoluteDate"].string = formatDate(components, format: "yyyy-MM-dd")
        }
        a["relativeOffset"].double = alarm.relativeOffset

        if alarm.structuredLocation != nil {
          let structuredLocation = alarm.structuredLocation!
          var s: JSON = [:]
          s["title"].string = structuredLocation.title
          s["radius"].double = structuredLocation.radius

          if let geoLocation = structuredLocation.geoLocation {
            var g: JSON = [:]
            g["coordinate"] = ["latitude": geoLocation.coordinate.latitude, "longitude": geoLocation.coordinate.longitude]
            s["geoLocation"] = g
          }
          a["structuredLocation"] = s
        }

        switch alarm.proximity {
        case .None:
          a["proximity"] = "none"
        case .Enter:
          a["proximity"] = "enter"
        case .Leave:
          a["proximity"] = "leave"
        }
        return a
      }
      json["alarms"] = JSON(alarms)
    }

    return json.rawString(NSUTF8StringEncoding, options: [])!
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
    let jsonOption = Option(
      trigger: OptionTrigger.Mixed("j", "json"),
      numberOfParameters: 0,
      helpDescription: "Display as JSON lines"
    )

    let parser = OptionParser(definitions: [calendarOption, jsonOption])
    let (options, _) = parseOptions(parser, arguments)
    let formatter: Formatter
    if options[jsonOption] != nil {
      formatter = JSONFormatter()
    } else {
      formatter = Formatter()
    }

    eachReminder(store, options) { reminder in
      print(formatter.formatReminder(reminder))
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

    let dateOption = Option(
      trigger: OptionTrigger.Mixed("d", "date"),
      numberOfParameters: 1,
      helpDescription: "Due date (HH)"
    )

    let latOption = Option(
      trigger: OptionTrigger.Long("latitude"),
      numberOfParameters: 1,
      helpDescription: "Latitude"
    )

    let lngOption = Option(
      trigger: OptionTrigger.Long("longitude"),
      numberOfParameters: 1,
      helpDescription: "Longitude"
    )

    let parser = OptionParser(definitions: [calendarOption, dateOption, latOption, lngOption])
    let (options, rest) = parseOptions(parser, arguments)

    let date: NSDateComponents?
    if options[dateOption] != nil {
      date = parseDate(options[dateOption]![0])
    } else {
      date = nil
    }

    let location: CLLocation?
    if options[latOption] != nil && options[lngOption] != nil {
      location = CLLocation(
        latitude: Double(options[latOption]![0])!,
        longitude: Double(options[lngOption]![0])!
      )
    } else {
      location = nil
    }

    let title:String
    if rest.count > 0 {
      title = rest.joinWithSeparator(" ")
    } else {
      title = ""
    }
    let reminder = addReminder(store, title, date: date, location: location)
    print(Formatter().formatReminder(reminder))
  }

  func addReminder(store: EKEventStore, _ title: String, date: NSDateComponents?, location: CLLocation?) -> EKReminder {
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = store.defaultCalendarForNewReminders()
    reminder.title = title
    reminder.startDateComponents = date

    if location != nil || date != nil{
      let alarm: EKAlarm

      if date != nil {
        alarm = EKAlarm(absoluteDate: NSCalendar.currentCalendar().dateFromComponents(date!)!)
      } else {
        alarm = EKAlarm(relativeOffset: 0)
      }

      if location != nil {
        let structuredLocation = EKStructuredLocation(title: String(location!.coordinate.latitude) + "," + String(location!.coordinate.longitude))
        structuredLocation.geoLocation = location!
        alarm.structuredLocation = structuredLocation
        alarm.proximity = .Enter
      }

      reminder.addAlarm(alarm)
    }

    do {
      try store.saveReminder(reminder, commit: true)
    } catch {
      print("save failed")
      exit(EXIT_FAILURE)
    }

    return reminder
  }

  // 23 # next 23:00
  // 23:15 # next 23:15
  // 3d # 24h * 3 later
  // 3d11:15 # 11:15 at 3d since
  func parseDate(dateString: String, _ dateOrNil: NSDateComponents? = nil) -> NSDateComponents {
    let date: NSDateComponents
    if dateOrNil != nil {
      date = dateOrNil!
    } else {
      date = NSCalendar.currentCalendar().components(
        [ NSCalendarUnit.Year,
          NSCalendarUnit.Month,
          NSCalendarUnit.Day,
          NSCalendarUnit.Hour,
          NSCalendarUnit.Minute,
          NSCalendarUnit.Second,
        ],
        fromDate: NSDate() // now
      )
    }

    switch dateString {
    case Regex("^(\\d?\\d)$"):
      let hour = Int(Regex.lastMatch!.captures[0]!)!
      if dateOrNil == nil && hour < date.hour  {
        date.day += 1
      }
      date.hour = hour
      date.minute = 0
      date.second = 0
    case Regex("^(\\d?\\d):(\\d?\\d)$"):
      let hour = Int(Regex.lastMatch!.captures[0]!)!
      let minute = Int(Regex.lastMatch!.captures[1]!)!
      if dateOrNil == nil && (hour * 60 + minute) < (date.hour * 60 + date.minute)  {
        date.day += 1
      }
      date.hour = hour
      date.minute = minute
      date.second = 0
    case Regex("^(\\d+)d(.*)"):
      let days = Int(Regex.lastMatch!.captures[0]!)!
      let rest = Regex.lastMatch!.captures[1]!
      date.day += days
      if rest.characters.count > 0 {
        return parseDate(rest, date)
      }
    default:
      print("invalid date")
      exit(EXIT_FAILURE)
    }

    return date
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
