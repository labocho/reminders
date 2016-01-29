# reminders

!!!WORK IN PROGRESS!!!

Command line interface for OSX's Reminders.app.

# installation

Require Xcode 7 and homebrew.

    brew update
    brew install carthage

    rake
    ln -s $(pwd)/reminders path/to/executables


# usage

    # list incompleted reminder
    $ reminders ls

    # as json
    $ reminders ls --json

    # add reminder
    $ reminders add Buy milk

    # add reminder with alarm
    $ reminders --date 23 Go to bath # reminds next 23:00

    # add reminder with location alarm
    $ reminders --latitude 35.681382 --longitude 139.766084 Buy souvenir
