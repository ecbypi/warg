Warg.configure do |config|
  config.variables(:app) do |app|
    app.name = "muchi"
    app.user { name }
  end
end
