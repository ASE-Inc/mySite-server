worker_processes 3 # amount of unicorn workers to spin up
timeout 30         # restarts workers that hang for 30 seconds
preload_app true   # avoid regeneration of jekyll site for each fork

before_fork do |server, worker|

end

after_fork do |server, worker|

end