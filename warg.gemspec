Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = "warg"
  s.version = "0.1.0"
  s.summary = "Light-weight interaction with servers"
  s.description = "Running one-off commands, templated scripts, " +
    "or managing output from multiple servers"
  s.authors = ["Eduardo Gutierrez"]

  s.files = Dir[
    "README.md",
    File.join("lib", "**", "*"),
    File.join("bin", "**", "*")
  ]

  s.require_path = "lib"

  s.bindir = "bin"
  s.executables = ["hodor"]

  s.add_dependency "net-ssh"

  s.add_development_dependency "m"
  s.add_development_dependency "byebug"
  s.add_development_dependency "pry"
  s.add_development_dependency "minitest"
  s.add_development_dependency "simplecov"
end
