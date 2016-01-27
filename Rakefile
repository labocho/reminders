require "digest/sha1"

namespace "carthage" do
  directory "Carthage"
  task "update" => "Carthage" do
    sha1_file = "Carthage/sha1"
    sha1 = Digest::SHA1.file("Cartfile.resolved")

    if File.exists?(sha1_file)
      existed = File.read(sha1_file).strip
    end

    if sha1 == existed && ENV["FORCE"].nil?
      puts "skipped: carthage update"
    else
      sh "carthage update"
      File.write(sha1_file, sha1)
    end
  end
end

file "reminders" => ["carthage:update"] do
  sh %(xcrun -sdk macosx swiftc reminders.swift -FCarthage/Build/Mac -Xlinker -rpath -Xlinker "@executable_path/Carthage/Build/Mac" -o reminders)
end

task "clean" do
  rm "reminders"
end

task "default" => "reminders"
